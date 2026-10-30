"""Résumé lisible des tests et de la couverture, à partir des journaux CI."""
import pathlib, re, sys

out = pathlib.Path(sys.argv[1])
log = (out / 'test.log').read_text(errors='replace') if (out / 'test.log').exists() else ''
last = [l for l in log.splitlines() if re.search(r'\+\d+', l)]
m = re.search(r'\+(\d+)(?: ~(\d+))?(?: -(\d+))?', last[-1]) if last else None
passed, skipped, failed = (int(m.group(1)), int(m.group(2) or 0), int(m.group(3) or 0)) if m else (0, 0, 0)

files = {}
lcov = out / 'lcov.info'
if lcov.exists():
    cur = None
    for line in lcov.read_text().splitlines():
        if line.startswith('SF:'):
            cur = line[3:].replace('\\\\', '/')
            files[cur] = [0, 0]
        elif line.startswith('LH:') and cur:
            files[cur][0] = int(line[3:])
        elif line.startswith('LF:') and cur:
            files[cur][1] = int(line[3:])

def pct(h, f):
    return 100.0 * h / f if f else 0.0

modules = {}
for path, (h, f) in files.items():
    parts = path.split('lib/')[-1].split('/')
    key = '/'.join(parts[:2]) if parts[0] == 'features' else parts[0]
    agg = modules.setdefault(key, [0, 0])
    agg[0] += h
    agg[1] += f

total_h = sum(h for h, _ in files.values())
total_f = sum(f for _, f in files.values())
print('# Résumé des tests\n')
print(f'- Tests réussis : **{passed}**, échoués : **{failed}**, ignorés : {skipped}')
print(f'- Couverture des lignes (code Dart) : **{pct(total_h, total_f):.1f} %** ({total_h}/{total_f})\n')
print('| Module | Couverture |')
print('|---|---|')
for k in sorted(modules):
    h, f = modules[k]
    print(f'| {k} | {pct(h, f):.0f} % ({h}/{f}) |')
bench = out / 'alpr_pipeline_benchmark.md'
if bench.exists():
    print('\n' + bench.read_text())
