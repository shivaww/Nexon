#!/usr/bin/env python3
"""Stateless Python tool shim for the `tools` C++ bridge (py tool).

Protocol: one JSON request on stdin -> one JSON response on stdout.
  request:  {"m": "<method>", "p": {...}, "workspace": "<project dir>"}
  response: {"st": "ok", "r": ...}  or  {"st": "fail", "r": "<reason>"}

Only STATELESS methods live here (chmod, dart_format, read_url). Anything
with in-memory state — background service registry, sessions, locks — stays
in the long-running Python bridge over WebSocket; a one-shot process cannot
see another process's memory.

Imports inside handlers on purpose: cold start stays short because heavy
modules load only when the method that needs them runs.
"""
import json
import os
import subprocess
import sys
import traceback


def resolve_in_workspace(workspace, path):
    """Resolve `path` against the workspace jail and refuse escapes."""
    if not path:
        raise ValueError("empty path")
    ws = os.path.realpath(workspace)
    full = os.path.realpath(os.path.join(ws, path) if not os.path.isabs(path) else path)
    if full != ws and not full.startswith(ws + os.sep):
        raise ValueError("path escapes workspace: " + str(path))
    return full


def do_chmod(params, workspace):
    path = resolve_in_workspace(workspace, params.get("path", ""))
    mode = str(params.get("mode", "")).strip()
    if not mode:
        raise ValueError("'mode' required (e.g. '755')")
    mode_int = int(mode, 8)
    recursive = bool(params.get("recursive", False))
    if recursive and os.path.isdir(path):
        for root, dirs, files in os.walk(path):
            for name in dirs + files:
                os.chmod(os.path.join(root, name), mode_int)
    os.chmod(path, mode_int)
    return {"path": path, "mode": mode, "recursive": recursive}


def do_dart_format(params, workspace):
    path = resolve_in_workspace(workspace, params.get("path", ""))
    output = str(params.get("output", "none")).strip().lower()
    if output not in ("none", "write"):
        raise ValueError("'output' must be 'none' (check) or 'write' (apply)")
    cmd = ["dart", "format"]
    if output == "none":
        cmd += ["--output=none", "--set-exit-if-changed"]
    cmd.append(path)
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    return {
        "path": path,
        "output": output,
        "changed_or_error": proc.returncode != 0,
        "rc": proc.returncode,
        "stdout": proc.stdout[-4000:],
        "stderr": proc.stderr[-2000:],
    }


def do_read_url(params, workspace):
    import urllib.request
    url = str(params.get("url", "")).strip()
    if not url.startswith(("http://", "https://")):
        raise ValueError("'url' must start with http:// or https://")
    timeout = min(int(params.get("timeout", 20)), 120)
    max_bytes = min(int(params.get("max_bytes", 2000000)), 8000000)
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (compatible; nexon-tools/1.1)",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    })
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = resp.read(max_bytes + 1)
        truncated = len(data) > max_bytes
        data = data[:max_bytes]
        charset = resp.headers.get_content_charset() or "utf-8"
    return {
        "url": url,
        "bytes": len(data),
        "truncated": truncated,
        "text": data.decode(charset, errors="replace"),
    }


HANDLERS = {
    "chmod": do_chmod,
    "dart_format": do_dart_format,
    "read_url": do_read_url,
}


def main():
    raw = sys.stdin.read()
    try:
        req = json.loads(raw) if raw.strip() else {}
    except Exception as e:
        print(json.dumps({"st": "fail", "r": "bad request JSON: " + str(e)}))
        return 1
    method = str(req.get("m", ""))
    params = req.get("p") or {}
    workspace = str(req.get("workspace", os.getcwd()))
    handler = HANDLERS.get(method)
    if handler is None:
        print(json.dumps({"st": "fail",
                          "r": "unknown py method: '" + method +
                               "' (valid: " + ", ".join(sorted(HANDLERS)) + ")"}))
        return 1
    try:
        result = handler(params, workspace)
        print(json.dumps({"st": "ok", "r": result}))
        return 0
    except Exception as e:
        print(json.dumps({"st": "fail", "r": type(e).__name__ + ": " + str(e),
                          "tb": traceback.format_exc(limit=3)}))
        return 1


if __name__ == "__main__":
    sys.exit(main())
