"""
Nexon Workspace Engine for Study Mode / Cross-Document Analysis
===============================================================

Provides lightweight, memory-conscious workspace management for Termux / mobile devices.
Handles quota enforcement, zip extraction (filtering APKs/binaries), structured text/table
extraction (ignoring images), and disk-backed chunk retrieval.
"""

import os
import shutil
import zipfile
import json
import re
from pathlib import Path
from typing import List, Dict, Any, Optional

# Workspace configuration and mobile limits
WORKSPACE_DIR = os.path.expanduser(os.getenv("NEXON_WORKSPACE_DIR", "~/nexon_workspace"))
MAX_WORKSPACE_MB = 150    # Total workspace disk limit (MB)
MAX_FILE_SIZE_MB = 150    # Max single upload file size (MB)
CHUNK_SIZE_CHARS = 1200   # ~250-300 words per chunk
CHUNK_OVERLAP = 150       # Overlap between consecutive chunks

# Common English stopwords dropped from workspace search keywords.
SEARCH_STOPWORDS = {
    "the", "a", "an", "of", "and", "or", "to", "in", "is", "for", "on",
    "at", "by", "with", "as", "from", "that", "this", "it", "be",
    "are", "was", "were", "has", "have", "had", "will", "would", "can",
}

# Prohibited executable/binary/media/image formats
BLOCKED_EXTENSIONS = {
    ".apk", ".exe", ".dll", ".so", ".bin", ".iso", ".img",
    ".deb", ".rpm", ".dmg", ".class", ".pyc", ".o", ".a", ".elf",
    ".mp3", ".mp4", ".wav", ".avi", ".mov", ".flv", ".wmv", ".webm",
    ".ogg", ".flac", ".aac", ".m4a", ".m4v", ".mkv",
    ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".webp",
    ".svg", ".ico", ".psd", ".ai", ".raw"
}

# Plain-text source/config files, read as UTF-8 text like .txt.
CODE_EXTENSIONS = {".py", ".dart", ".js", ".css", ".yaml", ".yml"}

# Legacy binary Office formats (.doc/.ppt/.xls) are intentionally absent:
# stdlib cannot parse them and they would index only a warning string.
ALLOWED_EXTENSIONS = {
    ".pdf", ".docx", ".txt", ".md", ".csv", ".json",
    ".rtf", ".odt", ".pptx", ".xlsx",
    ".epub", ".html", ".htm", ".xml", ".log", ".tex",
} | CODE_EXTENSIONS

# Accepted at the upload gate: documents plus .zip archives, which
# ingest_file unpacks (members are re-filtered against ALLOWED_EXTENSIONS).
UPLOAD_EXTENSIONS = ALLOWED_EXTENSIONS | {".zip"}


class WorkspaceManager:
    """Memory-efficient document workspace engine for Termux/mobile environments."""

    def __init__(self, workspace_path: str = WORKSPACE_DIR):
        # workspace_path is the ROOT bucket (~/nexon_workspace). Documents
        # are scoped per chat session under <root>/<session_id>/ so switching
        # or restarting never wipes another session's uploads; the active
        # session is ambient state in <root>/.workspace_session (set on
        # upload, re-read on every WorkspaceManager() construction).
        self.root_path = Path(workspace_path)
        self.root_path.mkdir(parents=True, exist_ok=True)
        self.session_marker = self.root_path / ".workspace_session"
        active = self._read_active_session_id()
        if active:
            self.workspace_path = self.root_path / active
        else:
            # Legacy flat mode (CLI use / hybrid tools before any upload):
            # operate directly on the root bucket.
            self.workspace_path = self.root_path
        self.workspace_path.mkdir(parents=True, exist_ok=True)
        self.index_file = self.workspace_path / ".workspace_index.json"

    def check_storage_quota(self, incoming_bytes: int = 0) -> Dict[str, Any]:
        """Ensures the global workspace quota (all session buckets) and device storage are respected."""
        total_used = 0
        for f in self.root_path.rglob('*'):
            try:
                if f.is_file() and not f.is_symlink():
                    total_used += f.stat().st_size
            except OSError:
                continue
        total_used_mb = total_used / (1024 * 1024)
        incoming_mb = incoming_bytes / (1024 * 1024)

        if (total_used_mb + incoming_mb) > MAX_WORKSPACE_MB:
            return {
                "allowed": False,
                "reason": f"Workspace limit exceeded ({total_used_mb:.1f}MB used out of {MAX_WORKSPACE_MB}MB quota)."
            }

        usage = shutil.disk_usage(self.workspace_path)
        free_mb = usage.free / (1024 * 1024)
        if free_mb < 200:
            return {
                "allowed": False,
                "reason": f"Low device storage ({free_mb:.1f}MB free). Clear device storage to continue."
            }

        return {
            "allowed": True,
            "used_mb": round(total_used_mb, 2),
            "quota_mb": MAX_WORKSPACE_MB,
            "free_disk_mb": round(free_mb, 2)
        }

    def clear_session_documents(self, session_id: Optional[str] = None) -> Dict[str, Any]:
        """Clear ONE session's document bucket (the active session by default).

        Per-session buckets mean other chats keep their uploads; the LRU
        pass in ensure_session reclaims space when the global quota is hit.
        With no session marker set (legacy flat mode) the whole root bucket
        is cleared, preserving the original semantics.
        """
        removed, freed = 0, 0

        def _size(p: Path) -> int:
            try:
                return p.stat().st_size
            except OSError:
                return 0

        if session_id:
            dirname = self._session_dir_name(session_id)
            target = self.root_path / dirname if dirname else None
        elif self._read_active_session_id():
            target = self.workspace_path
        else:
            target = self.root_path  # legacy flat mode

        if target is None or not target.exists():
            return {"status": "success", "removed_items": 0, "freed_mb": 0.0}

        keep_marker = target == self.root_path
        for entry in list(target.iterdir()):
            if keep_marker and (
                entry.name == ".workspace_session" or entry.name.startswith("session_")
            ):
                continue
            try:
                if entry.is_dir() and not entry.is_symlink():
                    freed += sum(f.stat().st_size for f in entry.rglob('*') if f.is_file())
                    shutil.rmtree(entry)
                else:
                    if entry.is_file():
                        freed += _size(entry)
                    os.remove(entry)
                removed += 1
            except OSError:
                continue
        return {
            "status": "success",
            "removed_items": removed,
            "freed_mb": round(freed / (1024 * 1024), 2),
        }

    @staticmethod
    def _session_dir_name(session_id: str) -> Optional[str]:
        """Sanitise a chat session id into a safe single path segment."""
        sid = str(session_id or "").strip()
        if not sid:
            return None
        safe = re.sub(r"[^A-Za-z0-9_-]+", "_", sid)[:80]
        if not safe or safe in {".", ".."}:
            return None
        return f"session_{safe}"

    def _read_active_session_id(self) -> Optional[str]:
        try:
            raw = self.session_marker.read_text().strip()
        except (OSError, ValueError):
            return None
        return self._session_dir_name(raw) if raw else None

    def _iter_session_dirs(self):
        """All per-session directories under the root bucket."""
        if not self.root_path.is_dir():
            return
        for entry in self.root_path.iterdir():
            if entry.is_dir() and not entry.is_symlink() and entry.name.startswith("session_"):
                yield entry

    def _enforce_global_quota(self) -> None:
        """LRU eviction: drop oldest session buckets until the quota is met.

        The active session's bucket is never evicted; loose root files are
        left alone (legacy flat-mode docs adopted on next ensure_session).
        """
        def dir_size(p: Path) -> int:
            total = 0
            try:
                for f in p.rglob("*"):
                    try:
                        if f.is_file() and not f.is_symlink():
                            total += f.stat().st_size
                    except OSError:
                        continue
            except OSError:
                pass
            return total

        def dir_mtime(p: Path) -> float:
            try:
                return p.stat().st_mtime
            except OSError:
                return 0.0

        try:
            sessions = list(self._iter_session_dirs())
        except OSError:
            return
        used = sum(dir_size(s) for s in sessions)
        limit = MAX_WORKSPACE_MB * 1024 * 1024
        if used <= limit:
            return
        active = self.workspace_path.resolve()
        evictable = [s for s in sessions if s.resolve() != active]
        evictable.sort(key=dir_mtime)  # oldest first
        for victim in evictable:
            if used <= limit:
                break
            used -= dir_size(victim)
            try:
                shutil.rmtree(victim)
            except OSError:
                pass

    def ensure_session(self, session_id: str) -> None:
        """Scope the workspace to one chat session without wiping others.

        Each session owns <root>/<session_id>/; switching sessions just
        moves the ambient marker. The first scoping call adopts loose
        legacy files from the flat root into the new session bucket so
        pre-upgrade docs stay reachable, then enforces the LRU quota.
        """
        dirname = self._session_dir_name(session_id)
        if not dirname:
            return
        session_dir = self.root_path / dirname
        session_dir.mkdir(parents=True, exist_ok=True)

        prev = self._read_active_session_id()
        if prev != dirname:
            # Adopt loose legacy files (flat-root era) into this session.
            for entry in list(self.root_path.iterdir()):
                if entry.name == ".workspace_session" or entry.name.startswith("session_"):
                    continue
                try:
                    if entry.is_file() and not entry.is_symlink():
                        shutil.move(str(entry), str(session_dir / entry.name))
                    elif entry.is_dir() and not entry.is_symlink():
                        shutil.move(str(entry), str(session_dir / entry.name))
                except (OSError, shutil.Error):
                    continue

        self.session_marker.write_text(str(session_id).strip())
        self.workspace_path = session_dir
        self.index_file = session_dir / ".workspace_index.json"
        try:
            os.utime(session_dir, None)  # LRU freshness touch
        except OSError:
            pass
        self._enforce_global_quota()

    def _resolve_workspace_path(self, file_path: str):
        """Resolve a caller-supplied path strictly inside the workspace root.

        Blocks path traversal: absolute paths outside the workspace and
        relative paths that escape it via '..' both resolve to None, as do
        paths whose canonical location leaves the workspace via symlinks.
        """
        root = self.workspace_path.resolve()
        try:
            raw = Path(file_path)
            if raw.is_absolute():
                candidate = raw.resolve()
            else:
                candidate = (self.workspace_path / raw).resolve()
        except (OSError, RuntimeError, ValueError):
            return None
        try:
            if candidate.is_relative_to(root):
                return candidate
        except AttributeError:
            # Python < 3.9 fallback (is_relative_to landed in 3.9)
            if str(candidate) == str(root) or str(candidate).startswith(str(root) + os.sep):
                return candidate
        return None

    def ingest_file(self, file_path: str, rebuild: bool = True) -> Dict[str, Any]:
        """Ingests a file or unzips archives safely, discarding prohibited binaries."""
        path = Path(file_path)
        if not path.exists():
            return {"status": "error", "message": f"File not found: {file_path}"}

        file_size_mb = path.stat().st_size / (1024 * 1024)
        if file_size_mb > MAX_FILE_SIZE_MB:
            return {"status": "error", "message": f"File exceeds maximum single file limit of {MAX_FILE_SIZE_MB}MB"}

        quota_check = self.check_storage_quota(path.stat().st_size)
        if not quota_check["allowed"]:
            return {"status": "error", "message": quota_check["reason"]}

        extracted_files = []

        # Unpack Zip
        if path.suffix.lower() == ".zip":
            try:
                with zipfile.ZipFile(path, 'r') as zip_ref:
                    # Zip-bomb guard: the declared size of every member we would
                    # extract must fit in 150 MB, checked before extracting anything.
                    declared = sum(
                        m.file_size for m in zip_ref.infolist()
                        if not m.is_dir() and Path(m.filename).suffix.lower() in ALLOWED_EXTENSIONS
                    )
                    if declared > 150 * 1024 * 1024:
                        return {"status": "error", "message": "Archive expands beyond the 150 MB workspace limit"}
                    for member in zip_ref.infolist():
                        member_path = Path(member.filename)

                        # Prevent Zip-Slip: is_relative_to, not a string
                        # prefix check (a sibling dir like nexon_workspace_evil
                        # must not pass, and symlinked escapes resolve out).
                        zip_root = self.workspace_path.resolve()
                        target_path = (self.workspace_path / member_path).resolve()
                        try:
                            inside_ws = target_path.is_relative_to(zip_root)
                        except AttributeError:
                            inside_ws = str(target_path).startswith(str(zip_root) + os.sep)
                        if not inside_ws:
                            continue

                        # Reject APKs and binary formats
                        if member_path.suffix.lower() in BLOCKED_EXTENSIONS:
                            continue

                        if not member.is_dir() and member_path.suffix.lower() in ALLOWED_EXTENSIONS:
                            zip_ref.extract(member, self.workspace_path)
                            extracted_files.append(str(member_path))

                # Remove original zip archive to save mobile disk space
                if path.exists() and str(path.parent.resolve()) == str(self.workspace_path.resolve()):
                    os.remove(path)

                index_res = self.rebuild_index() if rebuild else {"total_files": 0, "total_chunks": 0}
                return {
                    "status": "success",
                    "action": "unzipped",
                    "extracted_files": extracted_files,
                    "index_summary": index_res
                }
            except Exception as e:
                return {"status": "error", "message": f"Failed to unpack zip archive: {str(e)}"}
        else:
            if path.suffix.lower() in BLOCKED_EXTENSIONS:
                return {"status": "error", "message": f"Security restriction: {path.suffix} binary files are blocked."}

            if path.suffix.lower() not in ALLOWED_EXTENSIONS:
                return {"status": "error", "message": f"Unsupported format {path.suffix}. Allowed: {ALLOWED_EXTENSIONS}"}

            dest = self.workspace_path / path.name
            if path.resolve() != dest.resolve():
                shutil.copy(path, dest)

            index_res = self.rebuild_index() if rebuild else {"total_files": 0, "total_chunks": 0}
            return {
                "status": "success",
                "action": "ingested",
                "file": path.name,
                "index_summary": index_res
            }

    def extract_text_content(self, file_path: Path) -> str:
        """Extracts readable text and tables while ignoring bitmap images."""
        ext = file_path.suffix.lower()

        if ext in [".txt", ".md", ".csv", ".json"] or ext in CODE_EXTENSIONS:
            try:
                with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                    return f.read()
            except Exception as e:
                return f"[Error reading text file: {e}]"

        elif ext == ".pdf":
            try:
                import pypdf
                reader = pypdf.PdfReader(file_path)
                pages = []
                for idx, page in enumerate(reader.pages):
                    # Extract text only — images are explicitly skipped
                    page_text = page.extract_text() or ""
                    pages.append(f"\n--- [Page {idx + 1}] ---\n{page_text}")
                return "\n".join(pages)
            except ImportError:
                if shutil.which("pdftotext"):
                    # pdftotext extracts text only, images are ignored.
                    # List-form subprocess: no shell string, so apostrophes
                    # or shell metacharacters in a filename cannot inject
                    # commands; bounded by a 60s timeout.
                    import subprocess
                    out_txt = file_path.with_suffix(".tmp.txt")
                    try:
                        subprocess.run(
                            ["pdftotext", str(file_path), str(out_txt)],
                            check=False,
                            timeout=60,
                        )
                    except Exception:
                        pass
                    if out_txt.exists():
                        res = out_txt.read_text(errors="ignore")
                        out_txt.unlink()
                        return res
                return "[PDF Extractor unavailable: Install pypdf or poppler in Termux]"

        elif ext == ".docx":
            try:
                import docx
                doc = docx.Document(file_path)
                content = []

                # Paragraph text
                for p in doc.paragraphs:
                    if p.text.strip():
                        content.append(p.text)

                # Preserve tables in Markdown format
                for t_idx, table in enumerate(doc.tables):
                    content.append(f"\n[Table {t_idx + 1}]")
                    for row in table.rows:
                        row_cells = [cell.text.strip().replace("\n", " ") for cell in row.cells]
                        content.append("| " + " | ".join(row_cells) + " |")
                    content.append("")

                return "\n".join(content)
            except ImportError:
                return "[docx Extractor unavailable: Install python-docx in Termux]"

        elif ext in [".html", ".htm"]:
            try:
                import re as _re
                raw = file_path.read_text(encoding="utf-8", errors="ignore")
                text = _re.sub(r'<script[^>]*>[\s\S]*?</script>', '', raw, flags=_re.IGNORECASE)
                text = _re.sub(r'<style[^>]*>[\s\S]*?</style>', '', text, flags=_re.IGNORECASE)
                text = _re.sub(r'<[^>]+>', ' ', text)
                text = _re.sub(r'\s+', ' ', text).strip()
                return text
            except Exception as e:
                return f"[Error reading HTML: {e}]"

        elif ext == ".xml":
            try:
                import re as _re
                raw = file_path.read_text(encoding="utf-8", errors="ignore")
                text = _re.sub(r'<[^>]+>', ' ', raw)
                text = _re.sub(r'\s+', ' ', text).strip()
                return text
            except Exception:
                return ""

        elif ext in [".rtf"]:
            try:
                raw = file_path.read_text(encoding="utf-8", errors="ignore")
                import re as _re
                text = _re.sub(r'\\[a-zA-Z]+-?\d*\s?', '', raw)
                text = _re.sub(r'[{}]', '', text)
                return text.strip()
            except Exception:
                return ""

        elif ext in [".log", ".tex"]:
            try:
                return file_path.read_text(encoding="utf-8", errors="ignore")
            except Exception:
                return ""

        elif ext == ".doc":
            return "[Legacy .doc format not supported. Convert to .docx for text extraction.]"

        elif ext == ".pptx":
            from office_extract import extract_pptx_text
            return extract_pptx_text(file_path)

        elif ext == ".xlsx":
            from office_extract import extract_xlsx_text
            return extract_xlsx_text(file_path)

        elif ext == ".epub":
            try:
                import zipfile, re as _re
                text_parts = []
                with zipfile.ZipFile(file_path, 'r') as zf:
                    for name in zf.namelist():
                        if name.endswith(('.html', '.xhtml', '.htm')):
                            raw = zf.read(name).decode('utf-8', errors='ignore')
                            raw = _re.sub(r'<[^>]+>', ' ', raw)
                            text_parts.append(_re.sub(r'\s+', ' ', raw).strip())
                return "\n\n".join(text_parts)
            except Exception:
                return ""

        elif ext == ".odt":
            try:
                import zipfile, re as _re
                with zipfile.ZipFile(file_path, 'r') as zf:
                    content_xml = zf.read('content.xml').decode('utf-8', errors='ignore')
                    text = _re.sub(r'<[^>]+>', ' ', content_xml)
                    return _re.sub(r'\s+', ' ', text).strip()
            except Exception:
                return ""

        return ""

    def _chunk_text(self, text: str, file_name: str, rel_path: str) -> List[Dict[str, Any]]:
        """Structure-aware chunking: splits by paragraphs/headers, merges small ones."""
        chunks = []
        lines = text.split('\n')
        current_chunk = []
        current_len = 0
        
        current_page = 1
        chunk_page = 1
        page_re = re.compile(r'---\s*\[Page (\d+)\]')

        def flush_chunk():
            nonlocal current_chunk, current_len
            if current_chunk:
                chunk_text = '\n'.join(current_chunk).strip()
                if chunk_text:
                    chunks.append({
                        "file": file_name,
                        "relative_path": rel_path,
                        "chunk_id": len(chunks),
                        "page": chunk_page,
                        "content": chunk_text
                    })
                current_chunk = []
                current_len = 0

        for line in lines:
            stripped = line.strip()
            # Track the source page: PDF extraction emits --- [Page N] lines.
            page_hit = page_re.search(stripped)
            if page_hit:
                # New page marker starts a new chunk so each chunk keeps one accurate page.
                flush_chunk()
                current_page = int(page_hit.group(1))
            if not current_chunk:
                chunk_page = current_page
            # Structural boundaries
            is_header = stripped.startswith('#') or stripped.startswith('--- [Page')
            is_table_row = stripped.startswith('|')
            
            # If we hit a structural boundary and current chunk is big enough, flush
            if (is_header or is_table_row) and current_len > CHUNK_SIZE_CHARS * 0.5:
                flush_chunk()
            
            current_chunk.append(line)
            current_len += len(line) + 1  # +1 for newline
            
            # If chunk exceeds max size, flush
            if current_len >= CHUNK_SIZE_CHARS:
                flush_chunk()
                
        flush_chunk() # Flush any remaining
        
        # Post-processing: if any chunk is STILL too big (e.g., a single massive line),
        # split it manually by characters.
        final_chunks = []
        for c in chunks:
            if len(c["content"]) > CHUNK_SIZE_CHARS * 2:
                text_content = c["content"]
                step = CHUNK_SIZE_CHARS - CHUNK_OVERLAP
                for i in range(0, len(text_content), step):
                    chunk_text = text_content[i : i + CHUNK_SIZE_CHARS]
                    final_chunks.append({
                        "file": file_name,
                        "relative_path": rel_path,
                        "chunk_id": len(final_chunks),
                        "page": c["page"],
                        "content": chunk_text
                    })
            else:
                c["chunk_id"] = len(final_chunks) # Reindex
                final_chunks.append(c)
                
        return final_chunks

    def check_dependencies(self) -> Dict[str, Any]:
        """Checks for required system and python dependencies for text extraction."""
        deps = {
            "pypdf": False,
            "python-docx": False,
            "pdftotext": False
        }
        try:
            import pypdf
            deps["pypdf"] = True
        except ImportError:
            pass
        try:
            import docx
            deps["python-docx"] = True
        except ImportError:
            pass
        
        if shutil.which("pdftotext"):
            deps["pdftotext"] = True
            
        missing = [k for k, v in deps.items() if not v]
        commands = []
        if "pypdf" in missing:
            commands.append("pip install pypdf")
        if "python-docx" in missing:
            commands.append("pip install python-docx")
        if "pdftotext" in missing:
            commands.append("pkg install poppler")
            
        return {
            "dependencies": deps,
            "missing": missing,
            "commands": commands,
            "all_present": len(missing) == 0
        }

    @staticmethod
    def _pdf_text_coverage(text):
        """Return (total_pages, empty_pages) for extracted PDF text.

        A page counts as empty when it has fewer than 20 non-space
        characters, which is what an image-only (scanned) PDF yields.
        """
        import re as _re
        if "--- [Page " in text:
            parts = _re.split(r"\n--- \[Page \d+\] ---\n", text)
            pages = parts[1:] if len(parts) > 1 else parts
        else:
            pages = text.split("\f")
            if pages and not pages[-1].strip():
                pages = pages[:-1]
        if not pages:
            return 1, 1
        empty = sum(1 for p in pages if len("".join(p.split())) < 20)
        return len(pages), empty

    def rebuild_index(self) -> Dict[str, Any]:
        """Chunk workspace documents and save chunk index to disk."""
        chunks = []
        failed_files = []
        scanned_files = []
        files = [f for f in self.workspace_path.rglob('*') if f.is_file() and not f.name.startswith('.')]

        for f in files:
            if f.suffix.lower() in ALLOWED_EXTENSIONS:
                try:
                    text = self.extract_text_content(f)
                    if not text.strip():
                        continue
                    if f.suffix.lower() == ".pdf":
                        total_pages, empty_pages = self._pdf_text_coverage(text)
                        if empty_pages == total_pages:
                            # Image-only PDF: nothing searchable, so skip it
                            # instead of indexing page headers as noise.
                            scanned_files.append({
                                "file": f.name,
                                "pages": total_pages,
                                "empty_pages": empty_pages,
                                "status": "scanned",
                            })
                            continue
                        if empty_pages * 2 >= total_pages:
                            scanned_files.append({
                                "file": f.name,
                                "pages": total_pages,
                                "empty_pages": empty_pages,
                                "status": "partial",
                            })
                    chunks.extend(self._chunk_text(text, f.name, str(f.relative_to(self.workspace_path))))
                except Exception as exc:
                    # One malformed document must not kill the whole reindex;
                    # record it and continue so the app still gets a success signal.
                    failed_files.append({"file": f.name, "reason": str(exc)})

        with open(self.index_file, "w", encoding="utf-8") as idx_f:
            json.dump(chunks, idx_f)

        return {
            "total_files": len(files),
            "total_chunks": len(chunks),
            "failed_files": failed_files,
            "scanned_files": scanned_files,
        }

    def read_page(self, file_path: str, page: int = 1) -> Dict[str, Any]:
        """Read a specific page of a document (text only, images skipped)."""
        path = self._resolve_workspace_path(file_path)
        if path is None or not path.exists():
            return {"status": "error", "message": f"File not found in workspace: {file_path}"}

        ext = path.suffix.lower()
        if ext not in ALLOWED_EXTENSIONS:
            return {"status": "error", "message": f"Unsupported format {ext}"}

        if ext == ".pdf":
            try:
                import pypdf
                reader = pypdf.PdfReader(str(path))
                total_pages = len(reader.pages)
                if page < 1 or page > total_pages:
                    return {"status": "error", "message": f"Page {page} out of range (1-{total_pages})"}
                page_text = reader.pages[page - 1].extract_text() or ""
                result = {
                    "status": "success",
                    "file": path.name,
                    "page": page,
                    "total_pages": total_pages,
                    "content": page_text.strip()
                }
                if len(page_text.strip()) < 20:
                    result["note"] = (
                        "No extractable text on this page; it is probably a scanned "
                        "image. Tell the user the page cannot be read and suggest "
                        "a text-based copy or OCR."
                    )
                return result
            except ImportError:
                if shutil.which("pdftotext"):
                    import subprocess
                    result = subprocess.run(
                        ["pdftotext", "-f", str(page), "-l", str(page), str(path), "-"],
                        capture_output=True, text=True
                    )
                    return {
                        "status": "success",
                        "file": path.name,
                        "page": page,
                        "content": result.stdout.strip()
                    }
                return {"status": "error", "message": "PDF extractor unavailable"}
        elif ext == ".docx":
            try:
                import docx
                doc = docx.Document(str(path))
                # Paragraphs + tables as Markdown rows, so page slicing no
                # longer drops table content (parity with extract_text_content).
                blocks = [p.text for p in doc.paragraphs if p.text.strip()]
                for table in doc.tables:
                    rows = []
                    for row in table.rows:
                        cells = [cell.text.strip().replace("\n", " ") for cell in row.cells]
                        rows.append("| " + " | ".join(cells) + " |")
                    if rows:
                        blocks.append("\n[Table]\n" + "\n".join(rows))
                total_blocks = len(blocks)
                blocks_per_page = max(1, total_blocks // 10) if total_blocks > 50 else total_blocks
                total_pages = max(1, (total_blocks + blocks_per_page - 1) // blocks_per_page)
                start_idx = (page - 1) * blocks_per_page
                end_idx = min(start_idx + blocks_per_page, total_blocks)
                if page < 1 or start_idx >= total_blocks:
                    return {"status": "error", "message": f"Page {page} out of range (1-{total_pages})"}
                content = "\n".join(blocks[start_idx:end_idx])
                return {
                    "status": "success",
                    "file": path.name,
                    "page": page,
                    "total_pages": total_pages,
                    "content": content
                }
            except ImportError:
                return {"status": "error", "message": "python-docx unavailable"}
            except Exception as e:
                return {"status": "error", "message": f"Failed to read docx: {e}"}
        else:
            # Non-PDF/DOCX text files: paginate at ~5000 chars per virtual
            # page so a large .txt/.csv/.html no longer dumps the whole
            # file into one response.
            text = (self.extract_text_content(path) or "").strip()
            page_chars = 5000
            if not text:
                return {
                    "status": "success",
                    "file": path.name,
                    "page": 1,
                    "total_pages": 1,
                    "content": ""
                }
            total_pages = max(1, (len(text) + page_chars - 1) // page_chars)
            if page < 1 or page > total_pages:
                return {"status": "error", "message": f"Page {page} out of range (1-{total_pages})"}
            start = (page - 1) * page_chars
            return {
                "status": "success",
                "file": path.name,
                "page": page,
                "total_pages": total_pages,
                "content": text[start:start + page_chars]
            }

    def get_outline(self, file_path: str) -> Dict[str, Any]:
        """Get document structure (headings, chapters, outline) — text only."""
        path = self._resolve_workspace_path(file_path)
        if path is None or not path.exists():
            return {"status": "error", "message": f"File not found in workspace: {file_path}"}

        ext = path.suffix.lower()
        if ext not in ALLOWED_EXTENSIONS:
            return {"status": "error", "message": f"Unsupported format {ext}"}

        if ext == ".pdf":
            try:
                import pypdf
                reader = pypdf.PdfReader(str(path))
                outline = []
                total_pages = len(reader.pages)

                def _walk_outline(items, depth=0):
                    for item in items:
                        if isinstance(item, list):
                            _walk_outline(item, depth + 1)
                        else:
                            title = item.title if hasattr(item, 'title') else str(item)
                            page_num = None
                            try:
                                page_num = reader.get_destination_page_number(item) + 1
                            except Exception:
                                pass
                            outline.append({
                                "title": title,
                                "page": page_num,
                                "depth": depth
                            })

                if reader.outline:
                    _walk_outline(reader.outline)

                if not outline:
                    # Fallback: generate outline from text content (first lines of each page)
                    for idx, pg in enumerate(reader.pages):
                        text = (pg.extract_text() or "").strip()[:200]
                        if text:
                            outline.append({
                                "title": text.split("\n")[0][:100],
                                "page": idx + 1,
                                "depth": 0
                            })

                return {
                    "status": "success",
                    "file": path.name,
                    "total_pages": total_pages,
                    "outline": outline
                }
            except ImportError:
                return {"status": "error", "message": "pypdf unavailable for outline"}
        elif ext == ".docx":
            try:
                import docx
                doc = docx.Document(str(path))
                outline = []
                for p in doc.paragraphs:
                    if p.style and p.style.name and "Heading" in p.style.name:
                        try:
                            level = int(p.style.name.split()[-1])
                        except (ValueError, IndexError):
                            level = 1
                        outline.append({"title": p.text, "page": None, "depth": level - 1})
                return {
                    "status": "success",
                    "file": path.name,
                    "total_pages": 1,
                    "outline": outline
                }
            except ImportError:
                return {"status": "error", "message": "python-docx unavailable"}
        else:
            # For text/md files, extract headings
            text = self.extract_text_content(path)
            lines = text.split("\n")
            outline = []
            for idx, line in enumerate(lines):
                stripped = line.strip()
                if stripped.startswith("#"):
                    level = len(stripped) - len(stripped.lstrip("#"))
                    outline.append({
                        "title": stripped.lstrip("# ").strip(),
                        "page": None,
                        "depth": level - 1
                    })
                elif stripped and len(stripped) < 100 and idx == 0:
                    outline.append({
                        "title": stripped,
                        "page": None,
                        "depth": 0
                    })
            return {
                "status": "success",
                "file": path.name,
                "total_pages": 1,
                "outline": outline
            }

    def search_chunks(self, query, top_k: int = 5) -> List[Dict[str, Any]]:
        if not self.index_file.exists():
            self.rebuild_index()

        try:
            with open(self.index_file, "r", encoding="utf-8") as idx_f:
                chunks = json.load(idx_f)
        except Exception:
            return []

        # Multi-query support: each item in a queries list is searched
        # separately and the results merged + deduped (old code flattened
        # the list into one string, losing per-query intent).
        query_list: List[str] = []
        if isinstance(query, list):
            query_list = [str(q).strip() for q in query if str(q).strip()]
        elif isinstance(query, str) and query.strip():
            query_list = [query.strip()]

        keyword_sets: List[List[str]] = []
        for q in query_list:
            terms = [
                k.lower() for k in re.findall(r'\w+', q)
                if len(k) >= 2 and k.lower() not in SEARCH_STOPWORDS
            ]
            if terms:
                keyword_sets.append(terms)
        if not keyword_sets and query_list:
            # Punctuation/stopword-only queries: fall back to raw strings so
            # short technical terms (5G, pH, Q1, AI) still search.
            keyword_sets = [[q.lower() for q in query_list]]

        scored = []
        for chunk in chunks:
            text_lower = chunk["content"].lower()
            best = 0
            for terms in keyword_sets:
                score = 0
                for term in terms:
                    # Word-boundary match: "car" must not hit "carbon".
                    score += len(re.findall(
                        r"(?<![0-9a-z])" + re.escape(term) + r"(?![0-9a-z])",
                        text_lower,
                    ))
                best = max(best, score)
            if best <= 0:
                continue
            enriched = dict(chunk)
            if "page" not in enriched:
                page_match = re.search(r'\[Page (\d+)\]', chunk["content"])
                if page_match:
                    enriched["page"] = int(page_match.group(1))
            scored.append((best, enriched))

        scored.sort(key=lambda x: x[0], reverse=True)
        seen = set()
        results = []
        for scored_item in scored:
            item = scored_item[1]
            key = (item.get("relative_path"), item.get("chunk_id"))
            if key in seen:
                continue
            seen.add(key)
            results.append(item)
            if len(results) >= top_k:
                break
        return results

    def cross_compare(self, query, max_per_doc: int = 2, queries: list = None) -> Dict[str, Any]:
        """Like search_chunks, but guarantees EVERY matching document contributes
        its own top chunks — needed for timeline / cross-year comparisons where
        a global top-k would let one verbose document dominate.

        Documents are grouped by relative_path (not basename) so same-named
        files in different folders — 2024/report.pdf vs 2025/report.pdf —
        stay separate documents. Every match carries its source page, and
        each item of a queries array is scored independently."""
        if not self.index_file.exists():
            self.rebuild_index()
        try:
            with open(self.index_file, "r", encoding="utf-8") as idx_f:
                chunks = json.load(idx_f)
        except Exception:
            return {"status": "error", "message": "Workspace index unavailable.", "per_document": []}

        query_list: List[str] = []
        if isinstance(queries, list):
            query_list += [str(q).strip() for q in queries if str(q).strip()]
        if isinstance(query, list):
            query_list += [str(q).strip() for q in query if str(q).strip()]
        elif isinstance(query, str) and query.strip() and query.strip() not in query_list:
            query_list.append(query.strip())

        keyword_sets: List[List[str]] = []
        for q in query_list:
            terms = [
                k.lower() for k in re.findall(r'\w+', q)
                if len(k) >= 2 and k.lower() not in SEARCH_STOPWORDS
            ]
            if terms:
                keyword_sets.append(terms)
        if not keyword_sets:
            return {"status": "error", "message": "Query too short. Use specific terms of at least 2 characters (e.g. 'crude oil price').", "per_document": []}

        max_per_doc = max(1, min(int(max_per_doc), 4))
        by_doc: Dict[str, list] = {}
        for chunk in chunks:
            text_lower = chunk["content"].lower()
            best = 0
            for terms in keyword_sets:
                score = 0
                for term in terms:
                    # Word-boundary match: "car" must not hit "carbon".
                    score += len(re.findall(
                        r"(?<![0-9a-z])" + re.escape(term) + r"(?![0-9a-z])",
                        text_lower,
                    ))
                best = max(best, score)
            if best > 0:
                rel = chunk.get("relative_path") or chunk.get("file") or "unknown"
                by_doc.setdefault(rel, []).append((best, chunk))

        per_document = []
        for rel in sorted(by_doc):
            items = sorted(by_doc[rel], key=lambda x: x[0], reverse=True)
            matches = []
            for s, c in items[:max_per_doc]:
                page = c.get("page")
                if page is None:
                    page_match = re.search(r"\[Page (\d+)\]", c["content"])
                    page = int(page_match.group(1)) if page_match else None
                match = {"content": c["content"][:900], "score": s}
                if page is not None:
                    match["page"] = page
                matches.append(match)
            per_document.append({
                "file": rel.rsplit("/", 1)[-1],
                "relative_path": rel,
                "matches": matches,
            })

        return {
            "status": "success",
            "query": query if isinstance(query, str) else query_list,
            "documents_matched": len(per_document),
            "per_document": per_document,
        }

    def list_files(self) -> Dict[str, Any]:
        """Returns workspace file inventory and quota details."""
        files = []
        total_size = 0
        for f in self.workspace_path.rglob('*'):
            if f.is_file() and not f.name.startswith('.'):
                sz = f.stat().st_size
                total_size += sz
                files.append({
                    "name": f.name,
                    "path": str(f.relative_to(self.workspace_path)),
                    "size_kb": round(sz / 1024, 1),
                    "ext": f.suffix.lower()
                })

        quota = self.check_storage_quota()
        return {
            "workspace_dir": str(self.workspace_path),
            "file_count": len(files),
            "total_used_mb": round(total_size / (1024 * 1024), 2),
            "quota_mb": MAX_WORKSPACE_MB,
            "files": files
        }


if __name__ == "__main__":
    import sys
    mgr = WorkspaceManager()
    if len(sys.argv) > 1:
        cmd = sys.argv[1]
        if cmd == "list":
            print(json.dumps(mgr.list_files(), indent=2))
        elif cmd == "ingest" and len(sys.argv) > 2:
            print(json.dumps(mgr.ingest_file(sys.argv[2]), indent=2))
        elif cmd == "search" and len(sys.argv) > 2:
            print(json.dumps(mgr.search_chunks(" ".join(sys.argv[2:])), indent=2))
        else:
            print(json.dumps({"error": f"Unknown command {cmd}"}))
    else:
        print(json.dumps(mgr.list_files(), indent=2))
