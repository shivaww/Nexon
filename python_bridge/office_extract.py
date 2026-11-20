"""Stdlib-only text extraction for .pptx and .xlsx (no extra dependencies).

Both formats are ZIP archives of XML parts. Parts larger than
MAX_XML_MEMBER are skipped so a corrupt or hostile file cannot exhaust
memory on the device.
"""
import re
import zipfile
import xml.etree.ElementTree as ET

MAX_XML_MEMBER = 20 * 1024 * 1024

_A = "{http://schemas.openxmlformats.org/drawingml/2006/main}"
_M = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
_R = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"
_PK = "{http://schemas.openxmlformats.org/package/2006/relationships}"


def _load(zf, name):
    """Parse one XML part, or None if it is missing or oversized."""
    try:
        info = zf.getinfo(name)
    except KeyError:
        return None
    if info.file_size > MAX_XML_MEMBER:
        return None
    return ET.fromstring(zf.read(info))


def extract_pptx_text(file_path) -> str:
    """One '--- [Page N] ---' block per slide, so page tracking matches PDFs."""
    parts = []
    with zipfile.ZipFile(file_path, "r") as zf:
        slides = []
        for name in zf.namelist():
            m = re.fullmatch(r"ppt/slides/slide(\d+)\.xml", name)
            if m:
                slides.append((int(m.group(1)), name))
        slides.sort()
        for idx, (_, name) in enumerate(slides):
            root = _load(zf, name)
            if root is None:
                continue
            lines = []
            for para in root.iter(_A + "p"):
                text = "".join(t.text or "" for t in para.iter(_A + "t")).strip()
                if text:
                    lines.append(text)
            parts.append(f"\n--- [Page {idx + 1}] ---\n" + "\n".join(lines))
    return "\n".join(parts)


def _sheet_targets(zf):
    """Sheet (display name, part path) pairs in workbook order."""
    wb = _load(zf, "xl/workbook.xml")
    rels = _load(zf, "xl/_rels/workbook.xml.rels")
    sheets = []
    if wb is not None and rels is not None:
        targets = {r.get("Id"): r.get("Target", "") for r in rels.iter(_PK + "Relationship")}
        for sh in wb.iter(_M + "sheet"):
            tgt = targets.get(sh.get(_R + "id"), "").lstrip("/")
            path = tgt if tgt.startswith("xl/") else "xl/" + tgt
            sheets.append((sh.get("name") or "Sheet", path))
    if not sheets:
        found = [n for n in zf.namelist() if re.fullmatch(r"xl/worksheets/sheet\d+\.xml", n)]
        found.sort(key=lambda n: int(re.findall(r"\d+", n)[0]))
        sheets = [(f"Sheet{i + 1}", n) for i, n in enumerate(found)]
    return sheets


def _cell_text(cell, shared):
    kind = cell.get("t")
    if kind == "inlineStr":
        value = "".join(t.text or "" for t in cell.iter(_M + "t"))
    else:
        node = cell.find(_M + "v")
        value = (node.text or "") if node is not None else ""
        if kind == "s":
            value = shared[int(value)] if value.isdigit() and int(value) < len(shared) else ""
        elif kind == "e":
            value = ""
    return value.strip().replace("\n", " ")


def extract_xlsx_text(file_path) -> str:
    """One '## Sheet: name' block per sheet, one '| a | b |' line per row."""
    out = []
    with zipfile.ZipFile(file_path, "r") as zf:
        shared = []
        sst = _load(zf, "xl/sharedStrings.xml")
        if sst is not None:
            for si in sst.iter(_M + "si"):
                shared.append("".join(t.text or "" for t in si.iter(_M + "t")))
        present = set(zf.namelist())
        for name, path in _sheet_targets(zf):
            if path not in present:
                continue
            root = _load(zf, path)
            if root is None:
                out.append(f"\n## Sheet: {name}\n[Sheet skipped: file too large]")
                continue
            rows = []
            for row in root.iter(_M + "row"):
                vals = [v for v in (_cell_text(c, shared) for c in row.iter(_M + "c")) if v]
                if vals:
                    rows.append("| " + " | ".join(vals) + " |")
            out.append(f"\n## Sheet: {name}\n" + "\n".join(rows))
    return "\n".join(out)
