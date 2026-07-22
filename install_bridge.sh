#!/data/data/com.termux/files/usr/bin/env bash
# ============================================================================
# Nexon Deep Research & Python Bridge Setup Script
# ============================================================================
set -e

echo "=== Nexon Environment Setup ==="
echo "[1/2] Checking and installing system packages..."

# Install system packages cleanly without mirror testing delays
pkg install -y curl python git wget jq tar clang make ripgrep 2>/dev/null || apt-get install -y curl python git wget jq tar clang make ripgrep 2>/dev/null || true

echo "[2/2] Setting up Nexon Bridge..."
mkdir -p "$HOME/nexon_bridge"
TARGET_DIR="$HOME/nexon_bridge"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "  -> Copying bridge source..."
if [ -d "$SCRIPT_DIR/python_bridge" ]; then
    cp -r "$SCRIPT_DIR/python_bridge/"* "$TARGET_DIR/" || true
elif [ -d "$HOME/projects/termux_forge/python_bridge" ]; then
    cp -r "$HOME/projects/termux_forge/python_bridge/"* "$TARGET_DIR/" || true
elif [ -d "$HOME/Nexon/python_bridge" ]; then
    cp -r "$HOME/Nexon/python_bridge/"* "$TARGET_DIR/" || true
else
    echo "Error: Could not find python_bridge directory locally."
    echo "Please run this script from the Nexon repository root directory."
    exit 1
fi

cd "$TARGET_DIR"

echo "  -> Installing Python dependencies..."

cat <<EOF > requirements.txt
websockets>=12.0,<14.0
aiohttp>=3.9,<4.0
aiofiles>=23.0,<25.0
psutil>=5.9.0
requests>=2.31.0
python-docx
EOF

pip install --break-system-packages -q -r requirements.txt 2>/dev/null || pip install -q -r requirements.txt 2>/dev/null || true

echo "=== Nexon Python Bridge environment ready! ==="
echo "All components (Python deps, python-docx, websockets) have been successfully configured."
echo "You can start the bridge server now by running:"
echo "  cd ~/nexon_bridge && python3 mcp_server.py"
