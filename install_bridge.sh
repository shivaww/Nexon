#!/data/data/com.termux/files/usr/bin/env bash
# ============================================================================
# Nexon Deep Research & Python Bridge Setup Script
# ============================================================================
# IMPROVEMENT: fresh-Termux ready and build-error tolerant.
#  - runs `pkg update` first (fresh installs fail on stale package indexes)
#  - retries flaky network steps (pkg / git / pip) on mobile connections
#  - falls back to the local python_bridge/ next to this script when GitHub
#    is unreachable, instead of dying on the clone
#  - isolates a failing pip package (per-package fallback) so one broken
#    C-extension build no longer kills the whole install
#  - smoke-tests `import termux_forge_bridge` at the end so build errors are
#    caught at install time, not at first runtime use
#  - compiles the native C++ tools bridge (tools.cpp) on-device and gates it
#    on `tools --selftest` (a failing binary is removed, never left in place)
# ============================================================================
set -euo pipefail

if [ -n "${BASH_SOURCE[0]:-}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  # Piped (curl ... | bash): BASH_SOURCE is unset; use cwd so set -u survives.
  # The GitHub clone below is the real source in that case.
  SCRIPT_DIR="$(pwd)"
fi
TARGET_DIR="$HOME/nexon_bridge"
REPO_URL="https://github.com/shivaww/Nexon.git"

fail() { echo "ERROR: $*" >&2; exit 1; }

# retry <attempts> <description> <command...>
retry() {
  local attempts="$1" desc="$2" n=1
  shift 2
  until "$@"; do
    if [ "$n" -ge "$attempts" ]; then
      return 1
    fi
    echo "  -> $desc failed (attempt $n/$attempts), retrying in 3s..."
    n=$((n + 1))
    sleep 3
  done
}

echo "=== Nexon Environment Setup ==="

# ── [1/5] System packages ──────────────────────────────────────────────
echo "[1/6] Updating package indexes (required on fresh Termux)..."
pkg update -y || apt-get update -y || \
  echo "  -> index update failed; continuing with existing indexes."

echo "[2/6] Installing system packages..."
# clang/make/pkg-config/libffi/openssl: compile C extensions (psutil) on-device.
# ripgrep: fast search backend. poppler: PDF tooling.
retry 3 "system package install" pkg install -y \
  curl python git wget jq tar clang make pkg-config libffi openssl poppler ripgrep || \
  echo "  -> WARNING: system package install had failures; later steps will report what is missing."
# dart powers on-device dart_format / dart_diagnostics; optional, never blocks setup.
pkg install -y dart 2>/dev/null || \
  echo "  -> dart not installed (dart_format/dart_diagnostics need it later)."
# gh powers the GitHub hooks (auth/workflows/runs/releases); optional, never blocks.
pkg install -y gh 2>/dev/null || \
  echo "  -> gh not installed (github_hooks workflow/release tools need it later)."

# ── [3/6] Bridge sources (GitHub first, local checkout fallback) ───────
echo "[3/6] Fetching bridge sources (Python + C++)..."
TMP_CLONE="$(mktemp -d)"
trap 'rm -rf "$TMP_CLONE"' EXIT

SOURCE_DIR=""
if git clone --depth 1 --filter=blob:none --sparse "$REPO_URL" "$TMP_CLONE" 2>/dev/null && \
   git -C "$TMP_CLONE" sparse-checkout set python_bridge cpp_bridge 2>/dev/null && \
   [ -f "$TMP_CLONE/python_bridge/requirements.txt" ]; then
  SOURCE_DIR="$TMP_CLONE/python_bridge"
else
  echo "  -> GitHub unreachable; falling back to local python_bridge in this checkout."
  [ -f "$SCRIPT_DIR/python_bridge/requirements.txt" ] || \
    fail "no bridge source available: GitHub clone failed and $SCRIPT_DIR/python_bridge is missing."
  SOURCE_DIR="$SCRIPT_DIR/python_bridge"
fi

# C++ bridge sources: prefer the clone, fall back to this checkout. Missing
# sources degrade gracefully in step [6/6] (warning, no native tools)
# instead of blocking the Python bridge install.
CPP_SOURCE_DIR=""
if [ -f "$TMP_CLONE/cpp_bridge/tools.cpp" ]; then
  CPP_SOURCE_DIR="$TMP_CLONE/cpp_bridge"
elif [ -f "$SCRIPT_DIR/cpp_bridge/tools.cpp" ]; then
  CPP_SOURCE_DIR="$SCRIPT_DIR/cpp_bridge"
fi

rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"
cp -a "$SOURCE_DIR/." "$TARGET_DIR/"
if [ -n "$CPP_SOURCE_DIR" ]; then
  cp "$CPP_SOURCE_DIR/tools.cpp" "$TARGET_DIR/tools.cpp"
  cp "$CPP_SOURCE_DIR/py_tool.py" "$TARGET_DIR/py_tool.py"
fi
cd "$TARGET_DIR"

# ── [4/6] Python version + pip bootstrap + dependencies ────────────────
echo "[4/6] Checking Python and installing dependencies..."
python3 - <<'PY'
import sys
if sys.version_info < (3, 10):
    raise SystemExit(
        f"Error: Python 3.10+ is required, found {sys.version_info.major}.{sys.version_info.minor}"
    )
print(f"Python {sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro} OK")
PY

python3 -m pip --version >/dev/null 2>&1 || \
  python3 -m ensurepip --upgrade || \
  fail "pip is unavailable and ensurepip failed; reinstall the python package."

pip_install() {
  python3 -m pip install --break-system-packages "$@" 2>/dev/null || \
    python3 -m pip install "$@"
}

if ! retry 2 "requirements.txt install" pip_install -q -r requirements.txt; then
  echo "  -> bulk install failed; installing package-by-package to isolate the failure..."
  while IFS= read -r pkg; do
    case "$pkg" in ''|\#*) continue ;; esac
    echo "  -> pip install $pkg"
    retry 2 "install of $pkg (C extensions need clang/make/libffi)" pip_install -q "$pkg" || \
      fail "could not install '$pkg'. See the pip error above; on Termux this usually means a missing compiler package (clang/make/pkg-config/libffi/openssl)."
  done < requirements.txt
fi

# ── [5/6] Verify modules + bridge import smoke test ────────────────────
echo "[5/6] Verifying Python modules..."
python3 - <<'PY'
import importlib.util

modules = {
    "websockets": "websockets",
    "aiohttp": "aiohttp",
    "psutil": "psutil",
    "python-docx": "docx",
    "pypdf": "pypdf",
}

missing = [name for name, module in modules.items()
           if importlib.util.find_spec(module) is None]
if missing:
    raise SystemExit("Error: Missing Python modules after installation: " + ", ".join(missing))

print("All required Python modules verified successfully!")
PY

echo "  -> Smoke-testing bridge import (catches build errors at install time)..."
if ! python3 -c "import termux_forge_bridge" 2>"$TARGET_DIR/.import_check.err"; then
  echo "ERROR: bridge import failed. First lines of the traceback:" >&2
  head -25 "$TARGET_DIR/.import_check.err" >&2
  rm -f "$TARGET_DIR/.import_check.err"
  fail "fix the error above (usually: pip install <missing module>) and re-run ./build.sh"
fi
rm -f "$TARGET_DIR/.import_check.err"

# ── [6/6] Native C++ tools bridge (compile + selftest gate) ────────────
echo "[6/6] Building native C++ tools bridge..."
if [ ! -f "$TARGET_DIR/tools.cpp" ]; then
  echo "  -> WARNING: cpp_bridge sources not found; agentic file tools will be unavailable."
elif ! command -v clang++ >/dev/null 2>&1; then
  echo "  -> WARNING: clang++ not installed; agentic file tools unavailable (fix: pkg install clang, re-run)."
elif clang++ -O2 -std=c++17 "$TARGET_DIR/tools.cpp" -o "$TARGET_DIR/tools" 2>"$TARGET_DIR/.cpp_build.err"; then
  chmod +x "$TARGET_DIR/tools"
  echo "  -> Running tools --selftest install gate..."
  if "$TARGET_DIR/tools" --selftest >/dev/null; then
    echo "  -> Native tools bridge OK (selftest passed)."
  else
    rm -f "$TARGET_DIR/tools"
    echo "  -> WARNING: tools --selftest FAILED; binary removed. Agentic file tools unavailable until a rebuild succeeds."
  fi
else
  echo "  -> WARNING: C++ bridge compile failed. First lines of the build log:" >&2
  head -25 "$TARGET_DIR/.cpp_build.err" >&2
  echo "  -> Agentic file tools will be unavailable (fix the errors above and re-run)."
fi
rm -f "$TARGET_DIR/.cpp_build.err"

echo "=== Nexon Bridge environment ready! ==="
echo "All components have been successfully configured."
echo "You can start the bridge server now by running:"
echo "  cd ~/nexon_bridge && python3 mcp_server.py"
