#!/usr/bin/env python3
"""Vérifie les requêtes SQL de l'API d'administration contre une vraie base
PostgreSQL migrée : chaque requête est préparée (PREPARE) avec des paramètres
de type inconnu, comme les envoie le pilote Dart. Détecte les erreurs de
syntaxe, de colonne et de type sans lancer l'API.

  python3 server/database/tools/check_sql.py "host=... dbname=..." fichiers.dart…
"""
import re
import subprocess
import sys

CALL = re.compile(r"\.(query|one|scalar(?:<[^>]*>)?|exec)\(\s*")
# Valeurs représentatives des fragments interpolés dynamiquement.
DYNAMIC = {
    'sort': 'u.created_at DESC',
    'stateSql': 's.ended_at IS NULL',
    'timeout': '',
}


def read_string(src, i):
    """Lit une suite de littéraux de chaîne Dart adjacents à partir de i."""
    out = []
    n = len(src)
    while True:
        while i < n and src[i] in ' \t\r\n':
            i += 1
        raw = False
        if src.startswith("r'", i) or src.startswith('r"', i):
            raw = True
            i += 1
        if src.startswith("'''", i) or src.startswith('"""', i):
            q = src[i:i + 3]
            j = src.index(q, i + 3)
            out.append((src[i + 3:j], raw))
            i = j + 3
            continue
        if i < n and src[i] in "'\"":
            q = src[i]
            j = i + 1
            buf = []
            while src[j] != q:
                if src[j] == '\\' and not raw:
                    buf.append(src[j:j + 2])
                    j += 2
                    continue
                buf.append(src[j])
                j += 1
            out.append((''.join(buf), raw))
            i = j + 1
            continue
        break
    return out, i


def unescape(s):
    return s.replace("\\'", "'").replace('\\"', '"').replace('\\$', '$').replace('\\n', '\n')


def interpolate(s, consts):
    def rep(m):
        name = m.group(1) or m.group(2)
        key = name.split('.')[-1]
        if key in consts:
            return consts[key]
        if key in DYNAMIC:
            return DYNAMIC[key]
        raise KeyError(name)
    return re.sub(r"\$\{([A-Za-z_][\w.]*)\}|\$([A-Za-z_]\w*)", rep, s)


def collect_consts(sources):
    consts = {'onlineWindowSeconds': '150'}
    pat = re.compile(r"(?:static\s+)?(?:const|final)\s+(_?\w+)\s*=\s*")
    for src in sources:
        for m in pat.finditer(src):
            parts, _ = read_string(src, m.end())
            if parts:
                consts[m.group(1)] = ''.join(unescape(p) for p, _ in parts)
    # Résolution des interpolations entre constantes.
    for _ in range(4):
        for k, v in list(consts.items()):
            try:
                consts[k] = interpolate(v, consts)
            except KeyError:
                pass
    return consts


def local_defs(src):
    """Définitions locales (const/final x = '...') avec leur position."""
    out = []
    for m in re.finditer(r"(?:const|final)\s+(\w+)\s*=\s*", src):
        parts, _ = read_string(src, m.end())
        if parts:
            out.append((m.start(), m.group(1), ''.join(unescape(p) for p, _ in parts)))
    return out


def main():
    dsn, files = sys.argv[1], sys.argv[2:]
    sources = [open(f, encoding='utf-8').read() for f in files]
    consts = collect_consts(sources)
    statements = []
    for f, src in zip(files, sources):
        defs = local_defs(src)
        for m in CALL.finditer(src):
            parts, _ = read_string(src, m.end())
            if not parts:
                continue
            text = ''.join(unescape(p) for p, _ in parts)
            scope = dict(consts)
            for pos, name, value in defs:
                if pos < m.start():
                    try:
                        scope[name] = interpolate(value, scope)
                    except KeyError:
                        pass
            try:
                sql = interpolate(text, scope)
            except KeyError as e:
                print(f'?? {f}: interpolation inconnue {e}')
                continue
            line = src.count('\n', 0, m.start()) + 1
            statements.append((f, line, sql))
    failures = 0
    for i, (f, line, sql) in enumerate(statements):
        names = []

        def num(mm):
            name = mm.group(1)
            if name not in names:
                names.append(name)
            return f'${names.index(name) + 1}'

        pg = re.sub(r"(?<![\w@])@(\w+)", num, sql)
        if pg.strip().upper().startswith('LOCK') or not re.match(r"\s*(SELECT|INSERT|UPDATE|DELETE|WITH)", pg, re.I):
            cmd = f'BEGIN; {pg}; ROLLBACK;'
        else:
            cmd = f'PREPARE q{i} AS {pg}; DEALLOCATE q{i};'
        r = subprocess.run(['psql', dsn, '-v', 'ON_ERROR_STOP=1', '-q', '-c', cmd], capture_output=True, text=True)
        if r.returncode != 0:
            failures += 1
            print(f'ÉCHEC {f}:{line}\n  {r.stderr.strip()}\n  SQL: {" ".join(pg.split())[:400]}\n')
    print(f'{len(statements)} requêtes vérifiées, {failures} en échec')
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
