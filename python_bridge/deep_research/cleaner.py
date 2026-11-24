"""Extracts text, including JSON-LD and meta fallbacks for JS-rendered sites."""

from __future__ import annotations

import re
import json
import html

class TextCleaner:
    """Regex-based text normalization to remove boilerplate and extract JSON-LD."""

    _BODY_RE = re.compile(r"<body[^>]*>(.*?)</body>", re.DOTALL | re.IGNORECASE)

    def extract(self, text: str, max_chars: int = 120_000, query: str = "") -> dict:
        if not text:
            return {"text": "", "method": "empty", "status": "empty", "title": ""}

        # 1. Extract meta/title (Server-rendered shells have this)
        title_match = re.search(r"<title[^>]*>(.*?)</title>", text, re.IGNORECASE | re.DOTALL)
        title = html.unescape(title_match.group(1).strip()) if title_match else ""
        
        desc_match = re.search(r'<meta[^>]+name=["\']description["\'][^>]+content=["\'](.*?)["\']', text, re.IGNORECASE)
        if not desc_match:
            desc_match = re.search(r'<meta[^>]+property=["\']og:description["\'][^>]+content=["\'](.*?)["\']', text, re.IGNORECASE)
        desc = html.unescape(desc_match.group(1).strip()) if desc_match else ""

        # 2. Extract JSON from scripts (Next.js, SvelteKit, JSON-LD)
        json_texts = []
        for m in re.finditer(r'<script[^>]*type=["\']application/ld\+json["\'][^>]*>(.*?)</script>', text, re.IGNORECASE | re.DOTALL):
            try:
                json_texts.append(self._extract_json_strings(json.loads(m.group(1))))
            except Exception: pass
                
        for m in re.finditer(r'<script[^>]*id=["\']__NEXT_DATA__["\'][^>]*>(.*?)</script>', text, re.IGNORECASE | re.DOTALL):
            try:
                json_texts.append(self._extract_json_strings(json.loads(m.group(1))))
            except Exception: pass

        # 3. Extract body text
        body_match = self._BODY_RE.search(text)
        body = body_match.group(1) if body_match else text
        
        body = re.sub(r"<(script|style|svg|nav|footer|noscript)[^>]*>.*?</\1>", " ", body, flags=re.DOTALL|re.IGNORECASE)
        body = re.sub(r"<(p|div|br|li|h[1-6]|tr|section|article|pre|blockquote)[^>]*>", "\n", body, flags=re.IGNORECASE)
        body = re.sub(r"<[^>]+>", " ", body)
        body = html.unescape(body)
        
        lines = [line.strip() for line in body.splitlines()]
        filtered_lines = [line for line in lines if line and len(line) > 1]
        body_text = "\n".join(filtered_lines)
        
        # 4. Determine best content
        json_combined = "\n".join(filter(None, json_texts))
        extracted_text = body_text
        method = "html"
        status = "success"

        if len(body_text) < 400 and len(json_combined) > 200:
            extracted_text = json_combined
            method = "json"
        
        if not extracted_text.strip():
            meta_text = f"{title}\n{desc}".strip()
            if meta_text:
                extracted_text = meta_text
                method = "meta"
                status = "shell_only"
            else:
                status = "empty"
                
        # 5. Truncate and apply relevance
        if extracted_text and query and len(extracted_text) > 6000:
            extracted_text = self._filter_by_relevance(extracted_text, query, max_chars=min(max_chars, 6000))

        if max_chars > 0 and len(extracted_text) > max_chars:
            extracted_text = extracted_text[:max_chars] + "\n...[content truncated]"

        return {
            "text": extracted_text,
            "method": method,
            "status": status,
            "title": title
        }

    def _extract_json_strings(self, data) -> str:
        results = []
        if isinstance(data, dict):
            for k, v in data.items():
                if k in ("text", "articleBody", "description", "headline", "value", "body"):
                    if isinstance(v, str) and len(v) > 20:
                        results.append(v)
                else:
                    results.append(self._extract_json_strings(v))
        elif isinstance(data, list):
            for item in data:
                results.append(self._extract_json_strings(item))
        elif isinstance(data, str):
            if len(data) > 50 and " " in data and not data.startswith("http") and not data.startswith("/"):
                results.append(data)
        return "\n".join(r for r in results if r)

    def _filter_by_relevance(self, text: str, query: str, max_chars: int = 6000) -> str:
        keywords = set(k.lower() for k in re.findall(r'\w+', query) if len(k) >= 2)
        if not keywords:
            return text[:max_chars]

        paragraphs = text.split("\n\n")
        if len(paragraphs) <= 1:
            paragraphs = text.split("\n")
            if len(paragraphs) <= 1:
                paragraphs = re.split(r'(?<=[.!?]) +', text)
                
        scored = []
        for idx, para in enumerate(paragraphs):
            para_lower = para.lower()
            score = sum(1 for kw in keywords if kw in para_lower)
            position_bonus = max(0, 3 - idx // 3)
            scored.append((score + position_bonus, idx, para))

        scored.sort(key=lambda x: (-x[0], x[1]))
        kept = []
        total_len = 0
        for score, orig_idx, para in scored:
            if score == 0 and orig_idx > 2 and total_len > max_chars * 0.8:
                continue
            if total_len + len(para) > max_chars:
                if total_len == 0:
                    sliced = para[:max_chars]
                    kept.append((orig_idx, sliced))
                    total_len += len(sliced)
                    break
                continue
            kept.append((orig_idx, para))
            total_len += len(para)

        kept.sort(key=lambda x: x[0])
        result = "\n\n".join(p for _, p in kept)
        if not result:
            result = text[:max_chars]
        if len(result) < len(text):
            result += "\n\n...[content filtered by relevance to query]"
        return result

    def clean(self, text: str, max_chars: int = 120_000, query: str = "") -> str:
        return self.extract(text, max_chars, query)["text"]
