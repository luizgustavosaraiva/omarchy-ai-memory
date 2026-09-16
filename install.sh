#!/usr/bin/env bash
set -euo pipefail

ID="luizgustavosaraiva.ai-memory"
DEST="$HOME/.config/omarchy/plugins/$ID"
REPO="https://github.com/luizgustavosaraiva/omarchy-ai-memory"

if [ -d "$DEST/.git" ]; then
  echo "Updating $ID..."
  git -C "$DEST" pull --ff-only
else
  echo "Installing $ID..."
  git clone --depth 1 "$REPO" "$DEST"
fi

omarchy-shell shell rescanPlugins
omarchy plugin enable "$ID"
omarchy bar move "$ID" --section right

echo "✓ $ID installed and placed on the right side of the bar."
if ! command -v ai-memory >/dev/null 2>&1; then
  echo "NOTE: no ai-memory server found. The widget will show as offline until one is running."
  echo "      On Arch:  omarchy pkg aur add ai-memory-bin"
  echo "      Then:     ai-memory init && systemctl --user enable --now ai-memory.service"
fi
