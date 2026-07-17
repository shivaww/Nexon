"""Lightweight, deterministic text cleaner for boilerplate stripping."""

from __future__ import annotations

import re


class TextCleaner:
    """Regex-based text normalization to remove web scraping noise/boilerplate."""

    # Patterns for inline CSS & JS
    _CSS_BLOCK_RE = re.compile(r"<style[^>]*>.*?</style>", re.DOTALL | re.IGNORECASE)
    _JS_BLOCK_RE = re.compile(r"<script[^>]*>.*?</script>", re.DOTALL | re.IGNORECASE)
    _STYLE_ATTR_RE = re.compile(r"\bstyle=(['\"])[^\1]*?\1", re.IGNORECASE)

    # HTML tags
    _HTML_TAG_RE = re.compile(r"<[^>]+>")

    # CSS curly brace declarations (sometimes leaked during scrapings)
    _CSS_DECLARATION_RE = re.compile(
        r"(?:[a-z0-9_\-\.\#\s\>\+\:\,\*]+)\s*\{[^\}]*\}", re.DOTALL | re.IGNORECASE
    )

    # Common navigation boilerplate list patterns:
    # e.g., "Home | About | Products | Contact" or "Login • Register • Blog"
    _NAV_LINKS_RE = re.compile(
        r"^.*?(?:Home|About|Contact|Login|Register|Privacy|Terms|Terms of Service|FAQ|Sitemap)\s*(?:[\|•·\-\*\/])\s*(?:Home|About|Contact|Login|Register|Privacy|Terms|Terms of Service|FAQ|Sitemap).*?$",
        re.MULTILINE | re.IGNORECASE,
    )

    # Copyright footer noise
    _COPYRIGHT_RE = re.compile(
        r"(?:Copyright|©|&copy;)\s*(?:\d{4})?\s*.*?(?:All Rights Reserved|Privacy Policy|Terms of Use|Terms of Service|Terms & Conditions).*?$",
        re.MULTILINE | re.IGNORECASE,
    )

    # Sidebar/Related topics banners
    _RELATED_RE = re.compile(
        r"^(?:Related Articles|Related Topics|You might also like|Read next|Recommended for you).*?$",
        re.MULTILINE | re.IGNORECASE,
    )

    # Abnormal control characters (BOM, vertical tabs, backspaces)
    _CONTROL_CHARS_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f\ufeff]")

    def clean(self, text: str) -> str:
        if not text:
            return ""

        # 1. Strip CSS/JS code blocks first
        cleaned = self._CSS_BLOCK_RE.sub(" ", text)
        cleaned = self._JS_BLOCK_RE.sub(" ", cleaned)
        cleaned = self._STYLE_ATTR_RE.sub(" ", cleaned)

        # 2. Strip raw CSS styling declarations left outside tags
        cleaned = self._CSS_DECLARATION_RE.sub(" ", cleaned)

        # 3. Strip HTML tags
        cleaned = self._HTML_TAG_RE.sub(" ", cleaned)

        # 4. Remove navigation panels, copyright footers, related article links
        cleaned = self._NAV_LINKS_RE.sub("", cleaned)
        cleaned = self._COPYRIGHT_RE.sub("", cleaned)
        cleaned = self._RELATED_RE.sub("", cleaned)

        # 5. Normalize control characters
        cleaned = self._CONTROL_CHARS_RE.sub(" ", cleaned)

        # 6. Normalize spacing & newlines
        # Split into lines to clean line by line
        lines = [line.strip() for line in cleaned.splitlines()]
        # Remove consecutive blank lines and lines that are pure noise (e.g. only separators like ----)
        filtered_lines = []
        consecutive_blanks = 0

        for line in lines:
            if not line:
                consecutive_blanks += 1
                if consecutive_blanks <= 1:  # Allow at most one empty line between blocks
                    filtered_lines.append("")
            else:
                consecutive_blanks = 0
                # Filter lines containing just menu separator symbols
                if len(line) < 10 and all(c in " -_+=*|·•" for c in line):
                    continue
                filtered_lines.append(line)

        # Reconstruct text and normalize multiple inline spaces
        reconstructed = "\n".join(filtered_lines).strip()
        reconstructed = re.sub(r"[ \t]+", " ", reconstructed)

        return reconstructed
