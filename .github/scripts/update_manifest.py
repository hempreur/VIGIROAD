#!/usr/bin/env python3
"""Fichier vigiroad-update.json publié avec chaque release : l'application
installée le lit pour proposer (obligatoirement) la nouvelle version.

update_manifest.py <version> <build> <tag> <repo> <apk_arm64> <apk_arm32> <sortie>
"""
import hashlib
import json
import os
import re
import sys

version, build, tag, repo, arm64, arm32, out = sys.argv[1:8]


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def notes():
    """Puces de la section « ## <version> » des notes de version, sinon de la
    première section « Nouveautés » ; texte brut (sans Markdown)."""
    path = f"docs/RELEASE_NOTES_{'.'.join(version.split('.')[:2])}.md"
    if not os.path.exists(path):
        return []
    lines = open(path, encoding="utf-8").read().splitlines()
    start = next((i for i, l in enumerate(lines) if l.strip() == f"## {version}"), None)
    if start is None:
        start = next((i for i, l in enumerate(lines) if l.startswith("## ")), None)
    if start is None:
        return []
    out, cur = [], None
    for l in lines[start + 1 :]:
        if l.startswith("## "):
            break
        if l.startswith("- "):
            if cur:
                out.append(cur)
            cur = l[2:].strip()
        elif cur and l.startswith("  ") and l.strip():
            cur += " " + l.strip()
        elif not l.strip() and cur:
            out.append(cur)
            cur = None
    if cur:
        out.append(cur)
    clean = []
    for n in out:
        n = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", n)  # liens
        n = re.sub(r"[*`]", "", n)
        n = n.split(" : ")[0] if len(n) > 140 else n  # garder l'essentiel
        clean.append(n[:180])
    return clean[:8]


base = f"https://github.com/{repo}/releases/download/{tag}"
manifest = {
    "version": version,
    "build": int(build),
    # Toute version antérieure est obsolète : mise à jour obligatoire.
    "minBuild": int(build),
    "notes": notes() or ["Corrections de bugs", "Améliorations des performances", "Nouvelles fonctionnalités"],
    "apks": {
        "arm64-v8a": {"url": f"{base}/{os.path.basename(arm64)}", "sha256": sha(arm64), "size": os.path.getsize(arm64)},
        "armeabi-v7a": {"url": f"{base}/{os.path.basename(arm32)}", "sha256": sha(arm32), "size": os.path.getsize(arm32)},
    },
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(manifest, f, ensure_ascii=False, indent=2)
print(json.dumps(manifest, ensure_ascii=False, indent=2))
