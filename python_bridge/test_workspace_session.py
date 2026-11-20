"""Smoke tests for per-session workspace scoping + chunk/search semantics.

Runs entirely inside a throwaway directory under $HOME (Termux has no
writable /tmp). Execute from anywhere:
    python3 python_bridge/test_workspace_session.py
"""
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from workspace import WorkspaceManager  # noqa: E402

FAILURES = []


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        FAILURES.append(name)


def main():
    home = os.path.expanduser("~")
    root = tempfile.mkdtemp(prefix="nexon_ws_test_", dir=home)
    try:
        a = WorkspaceManager(workspace_path=root)
        a.ensure_session("sess-A")
        (a.workspace_path / "notes.txt").write_text(
            "carbon taxes rose in the region\n--- [Page 3] ---\n"
            "AI adoption and 5G rollout; pH 7.2; Q1 results for cars.\n",
            encoding="utf-8",
        )

        b = WorkspaceManager(workspace_path=root)
        b.ensure_session("sess-B")
        (b.workspace_path / "b.txt").write_text("beta only", encoding="utf-8")
        check("active session switches to B", b.workspace_path.name == "session_sess-B")

        a2 = WorkspaceManager(workspace_path=root)
        a2.ensure_session("sess-A")
        check("session A docs survive switch", (a2.workspace_path / "notes.txt").exists())

        text = (a2.workspace_path / "notes.txt").read_text(encoding="utf-8")
        chunks = a2._chunk_text(text, "notes.txt", "notes.txt")
        check("chunks carry page numbers", 3 in {c["page"] for c in chunks})

        a2.rebuild_index()

        car_hits = [h for h in a2.search_chunks("car") if h.get("file") == "notes.txt"]
        check("word boundary: car does not match carbon/cars", not car_hits)

        short_hits = [h for h in a2.search_chunks(["AI", "pH"]) if h.get("file") == "notes.txt"]
        check("short 2-char terms searchable", bool(short_hits))

        cc = a2.cross_compare("carbon AI")
        docs = {d.get("relative_path"): d for d in cc.get("per_document", [])}
        nd = docs.get("notes.txt")
        check("cross_compare groups by relative_path", nd is not None)
        if nd:
            check("cross_compare match carries page", any(m.get("page") == 3 for m in nd["matches"]))

        cleared = a2.clear_session_documents()
        check(
            "clear removes only session A docs",
            cleared.get("status") == "success"
            and not (a2.workspace_path / "notes.txt").exists()
            and (b.workspace_path / "b.txt").exists(),
        )
    finally:
        shutil.rmtree(root, ignore_errors=True)

    if FAILURES:
        print("FAILED: " + ", ".join(FAILURES))
        return 1
    print("ALL_SMOKE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
