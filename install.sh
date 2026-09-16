#!/usr/bin/env bash
set -euo pipefail

ID="luizgustavosaraiva.ai-memory"
DEST="$HOME/.config/omarchy/plugins/$ID"
REPO="https://github.com/luizgustavosaraiva/omarchy-ai-memory"
# Security: the installed code is pinned to an exact commit. This constant is
# updated at release time; the installer itself is fetched from an immutable
# pinned raw URL (see the README one-liner), never from a mutable branch.
REPO_REF="v1.1.2"

if [ -d "$DEST/.git" ]; then
  echo "Updating $ID to ${REPO_REF:0:12}..."
  git -C "$DEST" fetch --tags --force origin main
  git -C "$DEST" checkout --quiet "$REPO_REF"
elif [ -d "$DEST" ]; then
  # Manual (non-git) install found: back it up, then install the pinned clone.
  BACKUP="$DEST.bak.$(date +%s)"
  echo "Backing up existing non-git install to $BACKUP"
  mv "$DEST" "$BACKUP"
  git clone --quiet "$REPO" "$DEST"
  git -C "$DEST" checkout --quiet "$REPO_REF"
else
  echo "Installing $ID at ${REPO_REF:0:12}..."
  git clone --quiet "$REPO" "$DEST"
  git -C "$DEST" checkout --quiet "$REPO_REF"
fi

omarchy-shell shell rescanPlugins
omarchy plugin enable "$ID"
omarchy bar move "$ID" --section right

echo "✓ $ID installed at ${REPO_REF:0:12} (right side of the bar)."
if ! command -v ai-memory >/dev/null 2>&1; then
  echo "NOTE: no ai-memory server found. The widget will show as offline until one is running."
  echo "      On Arch:  omarchy pkg aur add ai-memory-bin"
  echo "      Then:     ai-memory init && systemctl --user enable --now ai-memory.service"
fi
