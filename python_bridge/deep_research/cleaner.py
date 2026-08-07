"""Lightweight, deterministic text cleaner for boilerplate stripping."""

from __future__ import annotations

import re


class TextCleaner:
    """Regex-based text normalization to remove web scraping noise/boilerplate."""

    _CSS_BLOCK_RE = re.compile(r"<style[^>]*>.*?</style>", re.DOTALL | re.IGNORECASE)
    _JS_BLOCK_RE = re.compile(r"<script[^>]*>.*?</script>", re.DOTALL | re.IGNORECASE)
    _SVG_BLOCK_RE = re.compile(r"<svg[^>]*>.*?</svg>", re.DOTALL | re.IGNORECASE)
    _COMMENT_RE = re.compile(r"<!--.*?-->", re.DOTALL)
    _STYLE_ATTR_RE = re.compile(r"\bstyle=(['\"])[^\1]*?\1", re.IGNORECASE)
    _HTML_TAG_RE = re.compile(r"<[^>]+>")
    _BOILERPLATE_RE = re.compile(
        r"<(nav|header|footer|aside|form|noscript)\b[^>]*>.*?</\1>",
        re.DOTALL | re.IGNORECASE,
    )

    _NAV_LINKS_RE = re.compile(
        r"^.*?(?:Home|About|Contact|Login|Register|Privacy|Terms|Terms of Service|FAQ|Sitemap)\s*(?:[\|•·\-\*\/])\s*(?:Home|About|Contact|Login|Register|Privacy|Terms|Terms of Service|FAQ|Sitemap).*?$",
        re.MULTILINE | re.IGNORECASE,
    )
    _COPYRIGHT_RE = re.compile(
        r"(?:Copyright|©|&copy;)\s*(?:\d{4})?\s*.*?(?:All Rights Reserved|Privacy Policy|Terms of Use|Terms of Service|Terms & Conditions).*?$",
        re.MULTILINE | re.IGNORECASE,
    )
    _RELATED_RE = re.compile(
        r"^(?:Related Articles|Related Topics|You might also like|Read next|Recommended for you).*?$",
        re.MULTILINE | re.IGNORECASE,
    )
    _CONTROL_CHARS_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f\ufeff]")
    _BODY_RE = re.compile(r"<body[^>]*>(.*?)</body>", re.DOTALL | re.IGNORECASE)

    def clean(self, text: str, max_chars: int = 120_000, query: str = "") -> str:
        if not text:
            return ""

        cleaned = self._CSS_BLOCK_RE.sub(" ", text)
        cleaned = self._JS_BLOCK_RE.sub(" ", cleaned)
        cleaned = self._SVG_BLOCK_RE.sub(" ", cleaned)
        cleaned = self._COMMENT_RE.sub(" ", cleaned)
        cleaned = self._STYLE_ATTR_RE.sub(" ", cleaned)

        # Strip boilerplate elements (nav, header, footer, aside, form, noscript)
        # before extracting body — removes navigation menus, cookie notices, etc.
        cleaned = self._BOILERPLATE_RE.sub(" ", cleaned)

        body_match = self._BODY_RE.search(cleaned)
        if body_match:
            cleaned = body_match.group(1)

        cleaned = self._HTML_TAG_RE.sub(" ", cleaned)
        cleaned = self._CONTROL_CHARS_RE.sub(" ", cleaned)

        lines = [line.strip() for line in cleaned.splitlines()]
        filtered_lines: list[str] = []
        consecutive_blanks = 0

        for line in lines:
            if not line:
                consecutive_blanks += 1
                if consecutive_blanks <= 1:
                    filtered_lines.append("")
                continue

            if len(line) < 500:
                if self._NAV_LINKS_RE.search(line):
                    continue
                if self._COPYRIGHT_RE.search(line):
                    continue
                if self._RELATED_RE.search(line):
                    continue

            consecutive_blanks = 0
            if len(line) < 10 and all(c in " -_+=*|·•" for c in line):
                continue
            filtered_lines.append(line)

        reconstructed = "\n".join(filtered_lines).strip()
        reconstructed = re.sub(r"[ \t]+", " ", reconstructed)
        reconstructed = re.sub(r"\n{3,}", "\n\n", reconstructed)

        # Keyword relevance filtering: if a query is provided, score paragraphs
        # and keep only the most relevant ones to reduce LLM input by ~90%.
        if query and len(reconstructed) > 6000:
            reconstructed = self._filter_by_relevance(reconstructed, query, max_chars=6000)

        if max_chars > 0 and len(reconstructed) > max_chars:
            # Truncate at sentence boundary to avoid cutting mid-sentence
            substring = reconstructed[:max_chars]
            last_period = substring.rfind(". ")
            end_idx = last_period if last_period > max_chars * 0.8 else max_chars
            reconstructed = reconstructed[:end_idx] + "\n...[content truncated]"

        return reconstructed

    def _filter_by_relevance(self, text: str, query: str, max_chars: int = 6000) -> str:
        """Score paragraphs by keyword overlap with the query; keep top matches."""
        import re as _re
        keywords = set(k.lower() for k in _re.findall(r'\w+', query) if len(k) > 2)
        if not keywords:
            return text[:max_chars]

        paragraphs = text.split("\n\n")
        scored = []
        for idx, para in enumerate(paragraphs):
            para_lower = para.lower()
            score = sum(1 for kw in keywords if kw in para_lower)
            # Bonus for paragraphs near the top (lede/intro usually has key info)
            position_bonus = max(0, 3 - idx // 3)
            scored.append((score + position_bonus, idx, para))

        # Sort by score descending, keep top paragraphs until we hit max_chars
        scored.sort(key=lambda x: (-x[0], x[1]))
        kept = []
        total_len = 0
        for score, orig_idx, para in scored:
            if score == 0 and total_len > max_chars * 0.5:
                continue
            if total_len + len(para) > max_chars:
                break
            kept.append((orig_idx, para))
            total_len += len(para)

        # Restore original order
        kept.sort(key=lambda x: x[0])
        result = "\n\n".join(p for _, p in kept)
        if len(result) < len(text):
            result += "\n\n...[content filtered by relevance to query]"
        return result
