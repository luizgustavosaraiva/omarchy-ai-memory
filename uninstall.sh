#!/usr/bin/env bash
set -euo pipefail
ID="luizgustavosaraiva.ai-memory"
omarchy plugin disable "$ID" 2>/dev/null || true
rm -rf "$HOME/.config/omarchy/plugins/$ID"
omarchy-shell shell rescanPlugins
echo "✓ $ID removed."
