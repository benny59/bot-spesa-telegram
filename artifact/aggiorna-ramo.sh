#!/usr/bin/env bash
# Copia a senso unico: artifact/ (repository del bot) -> worktree del ramo artifact-basket-index, poi commit.
# Uso: artifact/aggiorna-ramo.sh "messaggio del commit"      (senza messaggio: solo anteprima delle differenze)
# Non tocca mai artifact/campioni/ (PDF con dati personali) e non fa push.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)/"
WT="${ARTIFACT_WORKTREE:-$HOME/repos/artifact-basket-index}"
[ -d "$WT/.git" ] || [ -f "$WT/.git" ] || { echo "Worktree non trovato: $WT (git worktree add $WT artifact-basket-index)"; exit 1; }
[ "$(git -C "$WT" rev-parse --abbrev-ref HEAD)" = "artifact-basket-index" ] || { echo "Il worktree non è sul ramo artifact-basket-index"; exit 1; }
mkdir -p "$WT/artifact"
rsync -a --delete --exclude 'campioni/' --exclude '.git' "$SRC" "$WT/artifact/"
cd "$WT"
git add -A artifact
if git diff --cached --quiet; then echo "Nessuna modifica rispetto all'ultimo commit."; exit 0; fi
git diff --cached --stat
if [ $# -eq 0 ]; then echo; echo "Anteprima: nessun commit. Rilancia con un messaggio per committare."; git reset -q; exit 0; fi
git commit -q -m "$1

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
git log --oneline -1
