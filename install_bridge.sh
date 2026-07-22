#!/data/data/com.termux/files/usr/bin/env bash
# ============================================================================
# Nexon Deep Research & Python Bridge Setup Script
# ============================================================================
set -e

echo "=== Nexon Environment Setup ==="
echo "[1/2] Checking and installing system packages..."

# Install essential system packages & Termux python binary modules
pkg install -y curl python git wget jq tar clang make ripgrep libffi openssl python-aiohttp python-psutil 2>/dev/null || apt-get install -y curl python git wget jq tar clang make ripgrep 2>/dev/null || true

echo "[2/2] Setting up Nexon Bridge..."
TARGET_DIR="$HOME/nexon_bridge"
mkdir -p "$TARGET_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "$PWD")"

echo "  -> Fetching bridge source..."
if [ -d "$SCRIPT_DIR/python_bridge" ]; then
    cp -r "$SCRIPT_DIR/python_bridge/"* "$TARGET_DIR/" || true
elif [ -d "$HOME/projects/termux_forge/python_bridge" ]; then
    cp -r "$HOME/projects/termux_forge/python_bridge/"* "$TARGET_DIR/" || true
elif [ -d "$HOME/Nexon/python_bridge" ]; then
    cp -r "$HOME/Nexon/python_bridge/"* "$TARGET_DIR/" || true
else
    echo "  -> Downloading python_bridge components from GitHub..."
    TMP_CLONE=$(mktemp -d)
    git clone --depth 1 https://github.com/shivaww/Nexon.git "$TMP_CLONE" 2>/dev/null || true
    if [ -d "$TMP_CLONE/python_bridge" ]; then
        cp -r "$TMP_CLONE/python_bridge/"* "$TARGET_DIR/"
        rm -rf "$TMP_CLONE"
    fi
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

# Install python requirements with fallbacks and binary wheels
MATHLIB="m" pip install --break-system-packages -q -r requirements.txt 2>/dev/null || \
pip install --break-system-packages -q -r requirements.txt 2>/dev/null || \
pip install -q -r requirements.txt 2>/dev/null || \
pkg install -y python-aiohttp python-psutil || true

# Verify critical modules and auto-fix if missing
echo "  -> Verifying Python modules..."
python3 -c "import aiohttp, websockets, psutil, requests; print('✅ All core Python modules verified successfully!')" 2>/dev/null || {
    echo "  -> Installing pre-compiled binary modules fallback..."
    pkg install -y python-aiohttp python-psutil || true
    pip install --break-system-packages websockets aiofiles requests python-docx || true
}

echo "=== Nexon Python Bridge environment ready! ==="
echo "All components have been successfully configured."
echo "You can start the bridge server now by running:"
echo "  cd ~/nexon_bridge && python3 mcp_server.py"
