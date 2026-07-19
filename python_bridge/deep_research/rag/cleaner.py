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



        # 3. Strip HTML tags
        cleaned = self._HTML_TAG_RE.sub(" ", cleaned)

        # 4. Normalize control characters
        cleaned = self._CONTROL_CHARS_RE.sub(" ", cleaned)

        # 5. Split into lines to clean line by line (safe from backtracking on long lines)
        lines = [line.strip() for line in cleaned.splitlines()]
        filtered_lines = []
        consecutive_blanks = 0

        for line in lines:
            if not line:
                consecutive_blanks += 1
                if consecutive_blanks <= 1:  # Allow at most one empty line between blocks
                    filtered_lines.append("")
                continue
            
            # Apply nav/copyright filters only to shorter lines to avoid catastrophic backtracking
            if len(line) < 500:
                if self._NAV_LINKS_RE.search(line):
                    continue
                if self._COPYRIGHT_RE.search(line):
                    continue
                if self._RELATED_RE.search(line):
                    continue

            consecutive_blanks = 0
            # Filter lines containing just menu separator symbols
            if len(line) < 10 and all(c in " -_+=*|·•" for c in line):
                continue
            filtered_lines.append(line)

        # Reconstruct text and normalize multiple inline spaces
        reconstructed = "\n".join(filtered_lines).strip()
        reconstructed = re.sub(r"[ \t]+", " ", reconstructed)

        return reconstructed
