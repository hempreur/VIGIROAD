#!/usr/bin/env bash
# Publie les journaux et captures d'un job CI sur la branche ci-logs/<job>,
# pour qu'ils soient consultables sans accès à l'interface GitHub Actions.
set -euo pipefail
job="$1"; src="$2"
[ -d "$src" ] || exit 0
tmp="$(mktemp -d)"
cp -r "$src"/. "$tmp"/
{
  echo "job=$job"; echo "sha=${GITHUB_SHA}"; echo "ref=${GITHUB_REF}"
  echo "run=${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
  echo "status=${JOB_STATUS:-unknown}"
} > "$tmp/META.txt"
cd "$tmp"
git init -q -b "ci-logs/$job"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add -A
git commit -q -m "CI $job @ ${GITHUB_SHA::8} (${JOB_STATUS:-unknown})"
remote="https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
# Dernier journal du job (toutes branches) et journal propre à la branche,
# pour que des exécutions simultanées ne s'écrasent pas.
branch="$(printf '%s' "${GITHUB_REF_NAME:-local}" | tr '/' '-' | tr -cd 'A-Za-z0-9._-')"
git push -q -f "$remote" "HEAD:refs/heads/ci-logs/$job" "HEAD:refs/heads/ci-logs/$job--$branch"
