#!/data/data/com.termux/files/usr/bin/env bash
# Forwarding build script for Nexon Termux setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
chmod +x "$SCRIPT_DIR/install_bridge.sh"
exec "$SCRIPT_DIR/install_bridge.sh" "$@"
