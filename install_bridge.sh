#!/data/data/com.termux/files/usr/bin/env bash
# ============================================================================
# Nexon Deep Research & Python Bridge Setup Script
# ============================================================================
set -euo pipefail

echo "=== Nexon Environment Setup ==="
echo "[1/2] Checking and installing system packages..."

# Install essential system packages required by the bridge and document/PDF tooling.
pkg install -y curl python git wget jq tar clang make ripgrep libffi openssl poppler python-aiohttp python-psutil

echo "[2/2] Setting up Nexon Bridge..."
TARGET_DIR="$HOME/nexon_bridge"
mkdir -p "$TARGET_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_CLONE="$(mktemp -d)"
trap 'rm -rf "$TMP_CLONE"' EXIT

# Always fetch the latest bridge source from the canonical repository so a
# stale local python_bridge directory cannot silently install an old version.
echo "  -> Fetching latest python_bridge from GitHub..."
git clone --depth 1 --filter=blob:none --sparse https://github.com/shivaww/Nexon.git "$TMP_CLONE"
git -C "$TMP_CLONE" sparse-checkout set python_bridge

if [ ! -f "$TMP_CLONE/python_bridge/requirements.txt" ]; then
    echo "Error: Latest repository does not contain python_bridge/requirements.txt"
    exit 1
fi

# Replace the installed bridge with the latest repository version.
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"
cp -a "$TMP_CLONE/python_bridge/." "$TARGET_DIR/"

cd "$TARGET_DIR"

echo "  -> Checking Python version..."
python3 - <<'PY'
import sys
if sys.version_info < (3, 10):
    raise SystemExit(
        f"Error: Python 3.10+ is required, found {sys.version_info.major}.{sys.version_info.minor}"
    )
print(f"Python {sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro} OK")
PY

echo "  -> Installing Python dependencies from the latest requirements.txt..."
python3 -m pip install --break-system-packages -q -r requirements.txt

echo "  -> Verifying all required Python modules..."
python3 - <<'PY'
import importlib.util

modules = {
    "websockets": "websockets",
    "aiohttp": "aiohttp",
    "aiofiles": "aiofiles",
    "psutil": "psutil",
    "requests": "requests",
    "python-docx": "docx",
    "pypdf": "pypdf",
}

missing = [name for name, module in modules.items()
           if importlib.util.find_spec(module) is None]
if missing:
    raise SystemExit("Error: Missing Python modules after installation: " + ", ".join(missing))

print("All required Python modules verified successfully!")
PY

# Verify that installed package versions satisfy their declared dependencies.
echo "  -> Running Python dependency consistency check..."
python3 -m pip check

echo "=== Nexon Python Bridge environment ready! ==="
echo "All components have been successfully configured."
echo "You can start the bridge server now by running:"
echo "  cd ~/nexon_bridge && python3 mcp_server.py"
