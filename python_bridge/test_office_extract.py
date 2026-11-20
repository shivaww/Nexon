"""Smoke tests for .pptx/.xlsx/.py extraction and the zip-bomb guard.

Builds tiny Office files with zipfile inside a throwaway directory under
$HOME (Termux has no writable /tmp). Run: python3 python_bridge/test_office_extract.py
"""
import os
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from workspace import WorkspaceManager, UPLOAD_EXTENSIONS, ALLOWED_EXTENSIONS  # noqa: E402

FAILURES = []
A = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"'
M = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
R = 'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
P = 'xmlns="http://schemas.openxmlformats.org/package/2006/relationships"'


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        FAILURES.append(name)


def make_pptx(path):
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("ppt/slides/slide2.xml", f"<root {A}><a:p><a:t>Second slide</a:t></a:p></root>")
        z.writestr("ppt/slides/slide1.xml", f"<root {A}><a:p><a:t>First</a:t><a:t> slide</a:t></a:p></root>")


def make_xlsx(path):
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("xl/workbook.xml", f'<workbook {M} {R}><sheets><sheet name="Budget" sheetId="1" r:id="rId1"/></sheets></workbook>')
        z.writestr("xl/_rels/workbook.xml.rels", f'<Relationships {P}><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>')
        z.writestr("xl/sharedStrings.xml", f"<sst {M}><si><t>Item</t></si><si><t>Cost</t></si></sst>")
        z.writestr("xl/worksheets/sheet1.xml", f'<worksheet {M}><sheetData><row><c t="s"><v>0</v></c><c t="s"><v>1</v></c></row><row><c t="inlineStr"><is><t>Pen</t></is></c><c><v>3.5</v></c></row></sheetData></worksheet>')


def main():
    root = tempfile.mkdtemp(prefix="nexon_ws_test_", dir=os.path.expanduser("~"))
    try:
        mgr = WorkspaceManager(workspace_path=root)
        mgr.ensure_session("office")
        ws = mgr.workspace_path

        make_pptx(ws / "deck.pptx")
        txt = mgr.extract_text_content(ws / "deck.pptx")
        check("pptx slides in order with page markers", txt.index("[Page 1]") < txt.index("First slide") < txt.index("[Page 2]") < txt.index("Second slide"))

        make_xlsx(ws / "sheet.xlsx")
        txt = mgr.extract_text_content(ws / "sheet.xlsx")
        check("xlsx sheet name", "## Sheet: Budget" in txt)
        check("xlsx shared-string row", "| Item | Cost |" in txt)
        check("xlsx inline-string row", "| Pen | 3.5 |" in txt)

        (ws / "tool.py").write_text("def hello():\n    return 1\n", encoding="utf-8")
        check(".py read as plain text", "def hello" in mgr.extract_text_content(ws / "tool.py"))

        check("legacy .doc/.ppt/.xls not allowed", not ({".doc", ".ppt", ".xls"} & ALLOWED_EXTENSIONS))
        check(".zip allowed at upload gate only", ".zip" in UPLOAD_EXTENSIONS and ".zip" not in ALLOWED_EXTENSIONS)

        res = mgr.rebuild_index()
        check("rebuild_index chunks office files", res["total_chunks"] >= 3 and not res["failed_files"])

        zpath = Path(root) / "safe.zip"
        with zipfile.ZipFile(zpath, "w") as z:
            z.writestr("notes/a.txt", "hello zip")
            z.writestr("../evil.txt", "escape")
        out = mgr.ingest_file(str(zpath), rebuild=False)
        check("zip extracts allowed members", out.get("status") == "success" and (ws / "notes" / "a.txt").exists())
        check("zip-slip member not written outside", not (Path(root) / "evil.txt").exists() and not (Path(root).parent / "evil.txt").exists())
    finally:
        shutil.rmtree(root, ignore_errors=True)

    if FAILURES:
        print("FAILED: " + ", ".join(FAILURES))
        return 1
    print("ALL_OFFICE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
