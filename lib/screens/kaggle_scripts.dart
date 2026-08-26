import 'dart:convert';

class KaggleScripts {
  KaggleScripts._();

  static const _script1 = r'''
#!/usr/bin/env python3
"""
Download precompiled llama.cpp (CUDA) for Kaggle dual T4 GPUs
Source: https://github.com/ai-dock/llama.cpp-cuda
"""

import os
import sys
import tarfile
import urllib.request
from pathlib import Path

# Latest release (as of Aug 2026) - update tag if needed
VERSION = "b10472"
CUDA_VER = "12.8"
ARCH = "amd64"          # Kaggle is x86_64

FILENAME = f"llama.cpp-{VERSION}-cuda-{CUDA_VER}-{ARCH}.tar.gz"
URL = f"https://github.com/ai-dock/llama.cpp-cuda/releases/download/{VERSION}/{FILENAME}"

# Where to put it on Kaggle
DEST_DIR = Path("/kaggle/working/llama.cpp")
ARCHIVE_PATH = DEST_DIR / FILENAME

def download_with_progress(url: str, dest: Path):
    print(f"Downloading: {url}")
    print(f"Saving to  : {dest}")

    dest.parent.mkdir(parents=True, exist_ok=True)

    def reporthook(block_num, block_size, total_size):
        downloaded = block_num * block_size
        if total_size > 0:
            percent = min(100, downloaded * 100 // total_size)
            mb = downloaded / (1024 * 1024)
            total_mb = total_size / (1024 * 1024)
            sys.stdout.write(f"\r[{percent:3d}%] {mb:.1f} / {total_mb:.1f} MB")
            sys.stdout.flush()

    urllib.request.urlretrieve(url, dest, reporthook)
    print("\nDownload complete.")

def extract_tar(archive: Path, dest: Path):
    print(f"Extracting {archive.name} ...")
    with tarfile.open(archive, "r:gz") as tar:
        # filter="data" blocks path-traversal / unsafe members in the archive
        tar.extractall(path=dest, filter="data")
    print("Extraction done.")

def main():
    print("=" * 60)
    print("llama.cpp CUDA prebuilt for Kaggle dual T4 (SM 7.5)")
    print("=" * 60)

    if ARCHIVE_PATH.exists():
        print(f"Archive already exists: {ARCHIVE_PATH}")
    else:
        download_with_progress(URL, ARCHIVE_PATH)

    # Extract into /kaggle/working/llama.cpp/
    extract_tar(ARCHIVE_PATH, DEST_DIR)

    # Typical structure after extraction: cuda-12.8/ or just the binaries
    print("\nContents:")
    for p in sorted(DEST_DIR.rglob("*"))[:20]:
        print(" ", p.relative_to(DEST_DIR))

    print("\nDone!")
    print(f"Binaries are in: {DEST_DIR}")
    print("\nExample usage (dual T4):")
    print(f"  cd {DEST_DIR}")
    print("  ./llama-cli -m your_model.gguf -ngl 99 --tensor-split 0.5,0.5 -fa on")
    print("  # or")
    print("  ./llama-server -m your_model.gguf -ngl 99 --tensor-split 0.5,0.5 -fa on --host 0.0.0.0 --port 8080")

if __name__ == "__main__":
    main()
''';

  static const _script2 = r'''
#!/usr/bin/env python3
"""
Download cloudflared binary for Kaggle (Linux amd64)
Used to create a public OpenAI-compatible base URL via Cloudflare Quick Tunnel.
Does NOT start any server or tunnel.
"""

import os
import sys
import urllib.request
from pathlib import Path
import stat

# Latest stable release (update if needed)
VERSION = "2026.8.2"
FILENAME = "cloudflared-linux-amd64"
URL = f"https://github.com/cloudflare/cloudflared/releases/download/{VERSION}/{FILENAME}"

DEST_DIR = Path("/kaggle/working")
BINARY_PATH = DEST_DIR / "cloudflared"

def download_with_progress(url: str, dest: Path):
    print(f"Downloading: {url}")
    print(f"Saving to  : {dest}")

    dest.parent.mkdir(parents=True, exist_ok=True)

    def reporthook(block_num, block_size, total_size):
        downloaded = block_num * block_size
        if total_size > 0:
            percent = min(100, downloaded * 100 // total_size)
            mb = downloaded / (1024 * 1024)
            total_mb = total_size / (1024 * 1024)
            sys.stdout.write(f"\r[{percent:3d}%] {mb:.1f} / {total_mb:.1f} MB")
            sys.stdout.flush()
        else:
            sys.stdout.write(f"\rDownloaded: {downloaded / (1024*1024):.1f} MB")
            sys.stdout.flush()

    urllib.request.urlretrieve(url, dest, reporthook)
    print("\nDownload complete.")

def make_executable(path: Path):
    path.chmod(path.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
    print(f"Made executable: {path}")

def main():
    print("=" * 60)
    print("Downloading cloudflared for Cloudflare Quick Tunnel")
    print("=" * 60)

    if BINARY_PATH.exists():
        print(f"Binary already exists: {BINARY_PATH}")
        make_executable(BINARY_PATH)
    else:
        download_with_progress(URL, BINARY_PATH)
        make_executable(BINARY_PATH)

    print("\nVerifying binary...")
    try:
        result = os.popen(f'"{BINARY_PATH}" --version').read().strip()
        print(f"Version: {result}")
    except Exception as e:
        print(f"Could not run version check: {e}")

    print("\n" + "=" * 60)
    print("Ready!")
    print(f"Binary location: {BINARY_PATH}")
    print("The launch script starts this tunnel automatically.")
    print("=" * 60)

if __name__ == "__main__":
    main()
''';

  static const _script3 = r'''
import os

# Must be set before importing huggingface_hub
os.environ["HF_HUB_DISABLE_XET"] = "1"          # avoids the 70-99% stuck-download issue
os.environ["HF_HUB_DOWNLOAD_TIMEOUT"] = "300"
os.environ["HF_HUB_ETAG_TIMEOUT"] = "60"
os.environ["HF_HOME"] = "/kaggle/tmp/hf_cache"

from huggingface_hub import hf_hub_download, HfApi, login
from pathlib import Path
import time

# Override these via env vars if you swap models, e.g.:
#   %env HF_REPO_ID=unsloth/Qwen3.8-27B-GGUF
#   %env HF_FILENAME=Qwen3.8-27B-UD-Q4_K_XL.gguf
# Default is Unsloth's "Dynamic" 4-bit quant (UD-Q4_K_XL) -- their mixed-precision
# quant that preserves noticeably more accuracy than a plain Q4_K_M at the same
# bit-width. Use plain Q4_K_M/Q4_0 only if you specifically want the smaller
# uniform quant instead.
REPO_ID  = os.environ.get("HF_REPO_ID", "unsloth/Qwen3.8-27B-GGUF")
FILENAME = os.environ.get("HF_FILENAME", "Qwen3.8-27B-UD-Q4_K_XL.gguf")

LOCAL_DIR = Path("/kaggle/tmp/models")   # /kaggle/working caps at 20GiB; use scratch space instead
LOCAL_DIR.mkdir(parents=True, exist_ok=True)

# Optional: only needed for gated repos.
hf_token = os.environ.get("HF_TOKEN")
if hf_token:
    login(token=hf_token)
    print("Logged in with HF_TOKEN")

# Look up the real file size from the Hub so the completeness check works
# for whatever REPO_ID/FILENAME you point it at, not just one hardcoded model.
expected_bytes = None
try:
    info = HfApi().model_info(REPO_ID, files_metadata=True, token=hf_token)
    match = next((s for s in info.siblings if s.rfilename == FILENAME), None)
    if match:
        expected_bytes = match.size
        print(f"Expected size (from Hub): {expected_bytes / 1024**3:.2f} GB")
    else:
        print(f"Warning: {FILENAME} not found in {REPO_ID} file list. Check the name.")
except Exception as e:
    print(f"Could not fetch expected size from Hub ({e}); skipping size check.")

print(f"\nDownloading {REPO_ID}/{FILENAME} -> {LOCAL_DIR}")

for attempt in range(1, 6):
    try:
        print(f"\n--- Attempt {attempt}/5 ---")
        path = hf_hub_download(
            repo_id=REPO_ID,
            filename=FILENAME,
            local_dir=str(LOCAL_DIR),
            token=hf_token,
        )

        actual_bytes = os.path.getsize(path)
        print(f"Downloaded -> {path}")
        print(f"Size: {actual_bytes / 1024**3:.2f} GB")

        if expected_bytes is None or actual_bytes >= expected_bytes * 0.99:
            print("Download complete and size looks correct.")
            break
        else:
            print("File smaller than expected, retrying...")
            time.sleep(8)

    except Exception as e:
        print(f"Error: {e}")
        time.sleep(10 * attempt)
else:
    raise SystemExit("Failed after 5 attempts.")
''';

  static const _script4 = r'''
#!/usr/bin/env python3
"""
Find llama.cpp + model, load a DENSE model split across dual T4 GPUs,
KV cache on GPU (spilling weight layers to CPU/RAM as needed), launch a
direct Cloudflare Quick Tunnel. Prints step-by-step status and live
model-loading progress.
"""

import os, sys, subprocess, time, secrets, signal, threading, re
from pathlib import Path
import urllib.request

LLAMA_DIR   = Path("/kaggle/working/llama.cpp")
MODEL_DIR   = Path("/kaggle/tmp/models")
CLOUDFLARED = Path("/kaggle/working/cloudflared")
LOG_FILE    = Path("/kaggle/working/llama-server.log")
PORT        = 8080
API_KEY     = secrets.token_hex(16)
TOTAL_STEPS = 5

URL_RE = re.compile(r"https://[a-zA-Z0-9\-]+\.trycloudflare\.com")

# KV cache (context) always stays on GPU -- fast, no PCIe round-trips per
# token, and no idle gaps that could trip the Quick Tunnel's ~60s timeout.
# To make room for it, excess weight LAYERS spill to CPU/RAM instead
# (--ngl steps down) rather than moving KV cache itself off GPU. 64k is the
# target context; only shrinks if even minimal GPU-layer offload can't fit it.
CONTEXT_CANDIDATES = [65536, 32768, 16384, 8192, 4096]
NGL_CANDIDATES = [99, 80, 64, 48, 32, 24, 16, 8]

OOM_PATTERNS = (
    "out of memory", "cudamalloc failed", "cuda error", "failed to allocate",
    "bad_alloc", "cannot allocate memory",
)

PROGRESS_KEYWORDS = (
    "load_tensors", "offload", "n_ctx", "kv self size",
    "n_gpu_layers", "server is listening",
)

SYSTEM_LIB_DIRS = (
    "/usr/lib/x86_64-linux-gnu",
    "/usr/local/nvidia/lib64",
    "/usr/local/cuda/lib64",
    "/usr/lib/nvidia",
)


def step(n, msg):
    print(f"\n[{n}/{TOTAL_STEPS}] {msg}")


def find_binary(name: str) -> Path:
    matches = list(LLAMA_DIR.rglob(name))
    if not matches:
        sys.exit(f"ERROR: {name} not found under {LLAMA_DIR}")
    return matches[0]


def find_model() -> Path:
    override = os.environ.get("MODEL_FILENAME")
    if override:
        p = MODEL_DIR / override
        if not p.exists():
            sys.exit(f"ERROR: {p} not found")
        return p
    matches = list(MODEL_DIR.rglob("*.gguf"))
    if not matches:
        sys.exit(f"ERROR: no .gguf found under {MODEL_DIR}")
    # most recently downloaded, not largest -- avoids silently picking an old
    # bigger quant when you've since downloaded a smaller one to switch models
    return max(matches, key=lambda p: p.stat().st_mtime)


def lib_dirs_for(binary: Path) -> str:
    dirs = {p.parent for p in LLAMA_DIR.rglob("*.so*")}
    dirs.add(binary.parent)
    for d in SYSTEM_LIB_DIRS:
        if Path(d).exists():
            dirs.add(Path(d))
    return ":".join(str(d) for d in dirs)


def tail_progress(log_path: Path, stop_event: threading.Event):
    while not log_path.exists() and not stop_event.is_set():
        time.sleep(0.5)
    with open(log_path) as f:
        while not stop_event.is_set():
            line = f.readline()
            if not line:
                time.sleep(0.3)
                continue
            if any(k in line.lower() for k in PROGRESS_KEYWORDS):
                print(f"    {line.strip()}")


def log_has_oom(log_path: Path) -> bool:
    if not log_path.exists():
        return False
    text = log_path.read_text(errors="ignore").lower()
    return any(p in text for p in OOM_PATTERNS)


def wait_for_ready(proc: subprocess.Popen, port: int, timeout: int = 420):
    """Returns 'ready', 'crashed', or 'timeout'."""
    url = f"http://127.0.0.1:{port}/health"
    start = time.time()
    while time.time() - start < timeout:
        if proc.poll() is not None:
            return "crashed"
        try:
            urllib.request.urlopen(url, timeout=3)
            return "ready"
        except Exception:
            time.sleep(2)
    return "timeout"


def build_server_cmd(server_bin, model_path, ctx, ngl):
    return [
        str(server_bin),
        "-m", str(model_path),
        "-ngl", str(ngl),            # weight layers offloaded to GPU; rest run on CPU/RAM
        "--tensor-split", "1,1",     # equal split across the two T4s
        "--cache-type-k", "q8_0",    # quantized KV cache -> more context fits in leftover VRAM
        "--cache-type-v", "q8_0",
        "-c", str(ctx),
        "-fa", "on",                 # flash attention (required for KV cache quantization)
        "--temp", "0.1",
        "--repeat-penalty", "1.1",   # mild -- 1.15 combined with presence-penalty was pushing
        "--repeat-last-n", "256",    # the model into unrelated-word "word salad" on long outputs
        "--host", "0.0.0.0",
        "--port", str(PORT),
        "--api-key", API_KEY,
    ]


def start_server(server_bin, model_path, env, ctx, ngl):
    log = open(LOG_FILE, "w", buffering=1)
    cmd = build_server_cmd(server_bin, model_path, ctx, ngl)
    proc = subprocess.Popen(["stdbuf", "-oL", "-eL", *cmd], stdout=log, stderr=subprocess.STDOUT, env=env)
    stop_event = threading.Event()
    threading.Thread(target=tail_progress, args=(LOG_FILE, stop_event), daemon=True).start()
    return proc, stop_event


def load_model(server_bin, model_path, env):
    for ctx in CONTEXT_CANDIDATES:
        for ngl in NGL_CANDIDATES:
            print(f"    attempting context={ctx}, gpu_layers={ngl}...")
            proc, stop_event = start_server(server_bin, model_path, env, ctx, ngl)
            result = wait_for_ready(proc, PORT)
            stop_event.set()

            if result == "ready":
                print(f"    model loaded, context={ctx}, gpu_layers={ngl}, server listening on port {PORT}")
                return proc, ctx, ngl

            proc.terminate()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()

            if result == "crashed" and log_has_oom(LOG_FILE):
                print(f"    did not fit in VRAM, offloading fewer layers to GPU...")
                continue
            elif result == "crashed":
                sys.exit(f"ERROR: server crashed for a non-OOM reason. Check {LOG_FILE}")
            else:
                sys.exit(f"ERROR: server did not become healthy within timeout (ctx={ctx}, ngl={ngl}). Check {LOG_FILE}")

        print(f"    context {ctx} did not fit even with minimal GPU layers, trying smaller context...")

    sys.exit(f"ERROR: model did not fit even at smallest context/ngl combination. Check {LOG_FILE}")


def main():
    step(1, "Locating llama.cpp binary...")
    server_bin = find_binary("llama-server")
    print(f"    found: {server_bin}")

    step(2, "Locating model file...")
    model_path = find_model()
    size_gb = model_path.stat().st_size / 1024**3
    print(f"    found: {model_path} ({size_gb:.1f} GB)")

    step(3, "Locating cloudflared binary...")
    if not CLOUDFLARED.exists():
        sys.exit(f"ERROR: cloudflared not found at {CLOUDFLARED}")
    print(f"    found: {CLOUDFLARED}")

    step(4, "Loading model into GPUs (dual T4, tensor-split 1:1, KV cache on GPU, spilling layers to CPU as needed)...")
    env = os.environ.copy()
    lib_path = lib_dirs_for(server_bin)
    env["LD_LIBRARY_PATH"] = lib_path + ":" + env.get("LD_LIBRARY_PATH", "")

    server_proc, ctx_used, ngl_used = load_model(server_bin, model_path, env)

    step(5, "Starting cloudflared tunnel...")
    tunnel_proc = subprocess.Popen(
        [str(CLOUDFLARED), "tunnel", "--url", f"http://localhost:{PORT}"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
    )

    def shutdown(*_):
        print("\nShutting down...")
        tunnel_proc.terminate()
        server_proc.terminate()
        sys.exit(0)

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    public_url = None
    for line in tunnel_proc.stdout:
        match = URL_RE.search(line)
        if match:
            public_url = match.group(0)
            break

    if not public_url:
        sys.exit("ERROR: tunnel did not return a public URL. Check cloudflared output.")

    print()
    print("=" * 60)
    print("READY")
    print("=" * 60)
    print(f"Base URL   : {public_url}/v1")
    print(f"API key    : {API_KEY}")
    print(f"Context    : {ctx_used} tokens")
    print(f"GPU layers : {ngl_used}")
    print("=" * 60)
    print()

    server_proc.wait()


if __name__ == "__main__":
    main()
''';

  static const List<KaggleStep> steps = [
    KaggleStep(
      number: 1,
      title: 'Download llama.cpp',
      description: 'Downloads the precompiled llama.cpp CUDA binary for Kaggle dual T4 GPUs.',
      script: _script1,
    ),
    KaggleStep(
      number: 2,
      title: 'Download cloudflared',
      description: 'Downloads the cloudflared binary for creating a public tunnel URL.',
      script: _script2,
    ),
    KaggleStep(
      number: 3,
      title: 'Download the model',
      description: 'Downloads the Qwen3.8-27B GGUF model from HuggingFace. This is the largest download (~15 GB).',
      script: _script3,
    ),
    KaggleStep(
      number: 4,
      title: 'Launch the server',
      description: 'Loads the model across both T4 GPUs and starts a public OpenAI-compatible API endpoint. When it finishes, you\'ll see your Base URL and API key.',
      script: _script4,
    ),
  ];

  static const String instructions = '''
1. Create a free Kaggle account at kaggle.com
2. Create a new notebook: Create → New Notebook
3. In the settings panel on the right, set Accelerator → GPU T4 x2
4. For each step below, create a new code cell, paste the script, and run it
5. Run cells 1-3 first (each downloads files, takes a few minutes)
6. Run cell 4 last — it loads the model and creates a public URL
7. When cell 4 finishes, copy the Base URL and API key into this app's provider settings

To keep it running without your phone being active:
- Click Save Version (top right) → Save & Run All (Commit)
- This runs on Kaggle's servers even if you close your browser
- Check the Output/version log tab later for your Base URL and API key

Limits: ~30 GPU hours/week, ~9-12 hours per run. URL and key change each restart.
''';
}

class KaggleStep {
  final int number;
  final String title;
  final String description;
  final String script;

  const KaggleStep({
    required this.number,
    required this.title,
    required this.description,
    required this.script,
  });
}
