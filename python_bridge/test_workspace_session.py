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

        # Scanned-PDF detection. The extractor is stubbed so the test
        # needs neither pypdf nor poppler.
        def pdf_text(bodies):
            return "\n".join(
                f"\n--- [Page {i + 1}] ---\n{b}" for i, b in enumerate(bodies)
            )

        real = "This page carries plenty of readable sentences about carbon."
        scanned_txt = pdf_text(["", "  ", ""])
        mixed_txt = pdf_text([real, "", real, ""])
        good_txt = pdf_text([real, real, real])

        check(
            "coverage: image-only pdf is all empty",
            WorkspaceManager._pdf_text_coverage(scanned_txt) == (3, 3),
        )
        check(
            "coverage: mixed pdf counts empty pages",
            WorkspaceManager._pdf_text_coverage(mixed_txt) == (4, 2),
        )
        check(
            "coverage: text pdf has no empty pages",
            WorkspaceManager._pdf_text_coverage(good_txt) == (3, 0),
        )
        check(
            "coverage: pdftotext form-feed pages",
            WorkspaceManager._pdf_text_coverage(real + "\f\f") == (2, 1),
        )

        a3 = WorkspaceManager(workspace_path=root)
        a3.ensure_session("sess-A")
        a3.workspace_path.mkdir(parents=True, exist_ok=True)
        texts = {
            "scan.pdf": scanned_txt,
            "mixed.pdf": mixed_txt,
            "good.pdf": good_txt,
        }
        for name in texts:
            (a3.workspace_path / name).write_bytes(b"%PDF-stub")
        a3.extract_text_content = lambda p: texts[p.name]
        res = a3.rebuild_index()
        flagged = {s["file"]: s["status"] for s in res.get("scanned_files", [])}
        check("rebuild flags image-only pdf as scanned", flagged.get("scan.pdf") == "scanned")
        check("rebuild flags half-empty pdf as partial", flagged.get("mixed.pdf") == "partial")
        check("rebuild leaves text pdf unflagged", "good.pdf" not in flagged)
        with open(a3.index_file, encoding="utf-8") as fh:
            index_raw = fh.read()
        check("scanned pdf is kept out of the index", "scan.pdf" not in index_raw)
        check("partial pdf is still indexed", "mixed.pdf" in index_raw)

        # Read-only scoping must not move the ambient active-session marker.
        ro = WorkspaceManager(workspace_path=root)
        before = ro._read_active_session_id()
        check("scope_readonly finds an existing bucket", ro.scope_readonly("sess-B"))
        check("scope_readonly points at that bucket", ro.workspace_path.name == "session_sess-B")
        check("scope_readonly leaves the active marker alone", ro._read_active_session_id() == before)
        check("scope_readonly rejects an unknown session", not ro.scope_readonly("no-such-chat"))
    finally:
        shutil.rmtree(root, ignore_errors=True)

    if FAILURES:
        print("FAILED: " + ", ".join(FAILURES))
        return 1
    print("ALL_SMOKE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
