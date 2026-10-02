#!/bin/bash
# start.sh — NoTell Demo Launcher
# Starts the Envio indexer, frontend dev server, and (optionally) the Keeper bot
# in separate tmux panes so you can see all logs during the recording.
#
# Usage:
#   bash start.sh          — starts indexer + frontend (Keeper started manually when needed)
#   bash start.sh --keeper — starts all three including the Keeper

set -e

SESSION="notell"

# Kill any existing session with the same name to start clean
tmux kill-session -t $SESSION 2>/dev/null || true

echo " Starting NoTell demo environment..."

# Create a new tmux session with the first window for the Envio indexer
tmux new-session  -d -s $SESSION -x 220 -y 50 -n "indexer"
tmux send-keys    -t $SESSION:indexer "cd $(pwd)/indexer && npx envio dev" Enter

# Split horizontally for the frontend
tmux split-window -t $SESSION:indexer -v
tmux send-keys    -t $SESSION:indexer "cd $(pwd)/frontend && npm run dev -- --host" Enter

# If --keeper flag is passed, add a third pane for the Keeper bot
if [[ "$1" == "--keeper" ]]; then
  tmux split-window -t $SESSION:indexer -h
  tmux send-keys    -t $SESSION:indexer "cd $(pwd)/cre/notell-cre && node run_keeper.js" Enter
  echo " Keeper started (Policy Registry: 0xcDF2c6f314FEAB8aC1e0bB89a0F22a9009848b41)"
fi

# Make panes roughly equal size
tmux select-layout -t $SESSION:indexer even-vertical 2>/dev/null || true

echo ""
echo " NoTell started in tmux session '$SESSION'"
echo ""
echo "   Frontend:  http://localhost:5176/"
echo "   Indexer:   http://localhost:8080  (GraphQL, password: testing)"
echo ""
echo "To attach:   tmux attach -t $SESSION"
echo "To kill all: tmux kill-session -t $SESSION"
echo ""
echo "  Remember: Start the Keeper BEFORE Force Liquidation:"
echo "   bash start.sh --keeper"
echo "   OR in a new pane: cd cre/notell-cre && node run_keeper.js"

# Attach to the session so the user sees it immediately
tmux attach -t $SESSION