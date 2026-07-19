#!/usr/bin/env bash
# ============================================================================
# Nexon Deep Research Environment Setup
# ============================================================================
set -e

echo "=== Nexon Deep Research Environment Setup ==="
echo "[1/4] Checking and installing system packages..."
pkg update && pkg install -y curl python git wget jq tar clang make

STATE_FILE="$HOME/.nexon_bridge_setup.json"
if [ ! -f "$STATE_FILE" ]; then
    echo "{}" > "$STATE_FILE"
fi

echo "[2/4] Setting up llama.cpp (Android arm64)..."
LATEST_RELEASE=$(curl -s "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest")
ASSET_URL=$(echo "$LATEST_RELEASE" | jq -r '.assets[] | select(.name | test("llama-.*-bin-android-arm64\\.tar\\.gz$")) | .browser_download_url')
ASSET_NAME=$(basename "$ASSET_URL")

CURRENT_LLAMA=$(jq -r '.llama_asset // empty' "$STATE_FILE")
if [ "$CURRENT_LLAMA" == "$ASSET_NAME" ] && [ -x "$PREFIX/bin/llama-server" ]; then
    echo "  -> llama.cpp is already up-to-date ($ASSET_NAME). Skipping."
else
    if [ -z "$ASSET_URL" ] || [ "$ASSET_URL" == "null" ]; then
        echo "Error: Could not find android-arm64 asset in the latest release."
        exit 1
    fi
    echo "  -> Downloading $ASSET_NAME..."
    wget -q --show-progress "$ASSET_URL" -O "$HOME/$ASSET_NAME"
    
    EXPECTED_SHA256=$(echo "$LATEST_RELEASE" | jq -r '.assets[] | select(.name == "'$ASSET_NAME'") | .digest' | sed 's/sha256://')
    if [ -n "$EXPECTED_SHA256" ] && [ "$EXPECTED_SHA256" != "null" ]; then
        echo "  -> Verifying checksum..."
        ACTUAL_SHA256=$(sha256sum "$HOME/$ASSET_NAME" | awk '{print $1}')
        if [ "$EXPECTED_SHA256" != "$ACTUAL_SHA256" ]; then
            echo "Error: Checksum mismatch for $ASSET_NAME!"
            exit 1
        fi
    fi
    
    echo "  -> Extracting..."
    mkdir -p "$HOME/nexon_bridge/bin/llama.cpp"
    tar -xzf "$HOME/$ASSET_NAME" -C "$HOME/nexon_bridge/bin/llama.cpp"
    rm "$HOME/$ASSET_NAME"
    
    # We use find because the exact path inside the tar might be a subdirectory (e.g., build/bin/llama-server or just llama-server)
    SERVER_BIN=$(find "$HOME/nexon_bridge/bin/llama.cpp" -name "llama-server" | head -n 1)
    EMBED_BIN=$(find "$HOME/nexon_bridge/bin/llama.cpp" -name "llama-embedding" | head -n 1)
    
    if [ -z "$SERVER_BIN" ]; then
        echo "Error: Could not find llama-server inside extracted archive."
        exit 1
    fi
    
    cp -f "$SERVER_BIN" "$PREFIX/bin/llama-server.bin"
    if [ -n "$EMBED_BIN" ]; then
        cp -f "$EMBED_BIN" "$PREFIX/bin/llama-embedding.bin"
    fi
    chmod +x "$PREFIX/bin/llama-server.bin" 
    [ -n "$EMBED_BIN" ] && chmod +x "$PREFIX/bin/llama-embedding.bin"
    
    # Copy all shared libraries to PREFIX/lib and PREFIX/bin so the executables can find them
    find "$HOME/nexon_bridge/bin/llama.cpp" -name "*.so" -exec cp -f {} "$PREFIX/lib/" \;
    find "$HOME/nexon_bridge/bin/llama.cpp" -name "*.so" -exec cp -f {} "$PREFIX/bin/" \;
    
    # Create wrapper scripts
    cat << 'EOF2' > "$PREFIX/bin/llama-server"
#!/bin/sh
export LD_LIBRARY_PATH="/data/data/com.termux/files/usr/lib:$LD_LIBRARY_PATH"
exec "/data/data/com.termux/files/usr/bin/llama-server.bin" "$@"
EOF2
    chmod +x "$PREFIX/bin/llama-server"

    if [ -n "$EMBED_BIN" ]; then
        cat << 'EOF2' > "$PREFIX/bin/llama-embedding"
#!/bin/sh
export LD_LIBRARY_PATH="/data/data/com.termux/files/usr/lib:$LD_LIBRARY_PATH"
exec "/data/data/com.termux/files/usr/bin/llama-embedding.bin" "$@"
EOF2
        chmod +x "$PREFIX/bin/llama-embedding"
    fi
    
    echo "  -> Smoke testing llama-server..."
    if ! llama-server --version >/dev/null 2>&1; then
        echo "Error: llama-server smoke test failed. The binary might not be compatible."
        exit 1
    fi
    
    jq --arg asset "$ASSET_NAME" '.llama_asset = $asset' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
fi

echo "[3/4] Setting up Nexon Bridge..."
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

# Dependency notes (Termux / Android arm64):
#   * numpy is a HARD requirement for the RAG storage layer.  The hierarchical
#     retriever computes cosine similarity by stacking candidate embeddings
#     into a single numpy float32 matrix, so numpy must be importable at
#     runtime.  numpy ships solid ARM64 wheels, so this installs cleanly.
#   * sqlite-vec is intentionally NOT used.  There is no viable Android/Termux
#     wheel for it, so the vector store is implemented with plain sqlite3 BLOB
#     storage (float32 embeddings) + numpy cosine similarity.  Do not add
#     sqlite-vec back without a working Termux wheel.
#   * Termux's Python is externally-managed (PEP 668), so pip needs
#     --break-system-packages.  We fall back to it automatically below.
cat <<EOF > requirements.txt
websockets>=12.0,<14.0
aiohttp>=3.9,<4.0
aiofiles>=23.0,<25.0
psutil>=5.9.0
requests>=2.31.0
pypdf
python-docx
numpy>=1.26
EOF

pip install -q -r requirements.txt || pip install -q --break-system-packages -r requirements.txt

echo "  -> Verifying numpy is importable and functional in this Termux env..."
python3 - <<'PYEOF'
import numpy as np
a = np.array([1.0, 2.0, 3.0], dtype=np.float32)
b = np.array([4.0, 5.0, 6.0], dtype=np.float32)
dot = float(np.dot(a, b))
assert dot == 32.0, f"unexpected dot product: {dot}"
# confirm the same dtype used by the RAG BLOB serializer round-trips
raw = np.asarray([0.1, 0.2, 0.3], dtype=np.float32).tobytes()
back = np.frombuffer(raw, dtype=np.float32).tolist()
assert abs(back[0] - 0.1) < 1e-6, "numpy float32 BLOB round-trip failed"
print(f"numpy smoke test OK: dot(a,b)={dot}, float32 BLOB round-trip OK")
PYEOF
if [ $? -ne 0 ]; then
    echo "Error: numpy smoke test failed. Cannot proceed without a working numpy."
    exit 1
fi

echo "[4/4] Setting up Embedding Model..."
MODEL_DIR="$HOME/nexon_bridge/models"
MODEL_NAME="embeddinggemma-300m-Q4_0.gguf"
MODEL_PATH="$MODEL_DIR/$MODEL_NAME"
MODEL_URL="https://huggingface.co/second-state/embeddinggemma-300m-GGUF/resolve/main/embeddinggemma-300m-Q4_0.gguf"
mkdir -p "$MODEL_DIR"

if [ -f "$MODEL_PATH" ]; then
    echo "  -> Model already exists. Skipping download."
else
    echo "  -> Downloading EmbeddingGemma model..."
    wget -q --show-progress "$MODEL_URL" -O "$MODEL_PATH"
    # Basic size check (should be ~170MB to 200MB)
    MODEL_SIZE=$(stat -c%s "$MODEL_PATH")
    if [ "$MODEL_SIZE" -lt 100000000 ]; then
        echo "Error: Downloaded model seems too small, possibly failed. Removing..."
        rm "$MODEL_PATH"
        exit 1
    fi
fi

echo "=== Deep Research environment ready! ==="
echo "All components (Python deps including a verified numpy, llama.cpp binary, embedding model) have been successfully configured and verified."
echo "Vector storage uses plain sqlite3 BLOB + numpy cosine similarity (no sqlite-vec needed)."
echo "You can start the bridge server now by running:"
echo "  cd ~/nexon_bridge && python3 mcp_server.py"
