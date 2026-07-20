#!/usr/bin/env bash
# ============================================================================
# Nexon Deep Research Environment Setup
# ============================================================================
set -e

echo "=== Nexon Deep Research Environment Setup ==="
echo "[1/2] Checking and installing system packages..."
pkg update && pkg install -y curl python git wget jq tar clang make

echo "[2/2] Setting up Nexon Bridge..."
mkdir -p "$HOME/nexon_bridge"
cd "$HOME/nexon_bridge"

echo "  -> Copying bridge source..."
if [ -d "./python_bridge" ]; then
    cp -r ./python_bridge/* . || true
elif [ -d "$HOME/projects/termux_forge/python_bridge" ]; then
    cp -r "$HOME/projects/termux_forge/python_bridge/"* . || true
else
    echo "Error: Could not find python_bridge directory locally. Please run this script from the repository root."
    exit 1
fi

echo "  -> Installing Python dependencies..."

cat <<EOF > requirements.txt
websockets>=12.0,<14.0
aiohttp>=3.9,<4.0
aiofiles>=23.0,<25.0
psutil>=5.9.0
requests>=2.31.0
python-docx
EOF

pip install -q -r requirements.txt || pip install -q --break-system-packages -r requirements.txt

echo "=== Deep Research environment ready! ==="
echo "All components (Python deps, python-docx, websockets) have been successfully configured."
echo "You can start the bridge server now by running:"
echo "  cd ~/nexon_bridge && python3 mcp_server.py"
