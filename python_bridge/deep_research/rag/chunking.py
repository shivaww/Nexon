"""Deterministic, configurable section-aware chunking for Hierarchical RAG."""

from __future__ import annotations

import re


class ChunkingConfig:
    # Tunable knobs
    chunk_words: int = 220          # chunk size: short enough for recall
    overlap_words: int = 30         # small but non-zero overlap
    min_chunk_words: int = 24       # drop near-empty tail chunks

    def __init__(self, chunk_words: int | None = None, overlap_words: int | None = None) -> None:
        if chunk_words is not None:
            self.chunk_words = max(40, chunk_words)
        if overlap_words is not None:
            self.overlap_words = max(0, min(overlap_words, self.chunk_words - 1))


def split_into_sections(text: str) -> list[tuple[str | None, str]]:
    """Split text into sections using markdown headings as separators.

    Returns a list of (section_title, section_content) tuples.
    If no headings are found, falls back to paragraph grouping.
    """
    lines = text.splitlines()
    sections: list[tuple[str | None, str]] = []

    current_title: str | None = None
    current_lines: list[str] = []

    heading_pattern = re.compile(r"^#{1,6}\s+(.+)$")

    for line in lines:
        match = heading_pattern.match(line)
        if match:
            # Save the previous section
            if current_lines or current_title is not None:
                content = "\n".join(current_lines).strip()
                if content:
                    sections.append((current_title, content))
            current_title = match.group(1).strip()
            current_lines = [line]  # Keep the heading in the content for context!
        else:
            current_lines.append(line)

    # Append the last section
    if current_lines or current_title is not None:
        content = "\n".join(current_lines).strip()
        if content:
            sections.append((current_title, content))

    # If no markdown headings were found (or only one), fallback to paragraph grouping
    if len(sections) <= 1:
        paragraphs = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
        sections = []
        current_section_parts: list[str] = []
        word_count = 0
        section_idx = 1

        for p in paragraphs:
            p_words = p.split()
            current_section_parts.append(p)
            word_count += len(p_words)

            # Target section size: ~600 words
            if word_count >= 600:
                sections.append((f"Section {section_idx}", "\n\n".join(current_section_parts)))
                current_section_parts = []
                word_count = 0
                section_idx += 1

        if current_section_parts:
            sections.append((f"Section {section_idx}", "\n\n".join(current_section_parts)))

    return sections


def chunk_section(
    section_content: str,
    chunk_words: int = 220,
    overlap_words: int = 30,
    min_chunk_words: int = 24,
) -> list[str]:
    """Split section content into overlapping word windows."""
    words = re.findall(r"\S+", section_content)
    if not words:
        return []
    chunks: list[str] = []
    step = max(1, chunk_words - overlap_words)
    start = 0
    while start < len(words):
        window = words[start : start + chunk_words]
        if len(window) >= min_chunk_words or not chunks:
            chunks.append(" ".join(window))
        if start + chunk_words >= len(words):
            break
        start += step
    return chunks


def chunk_text(text: str, config: ChunkingConfig | None = None) -> list[str]:
    """Legacy compatibility: chunks text directly."""
    cfg = config or ChunkingConfig()
    return chunk_section(text, cfg.chunk_words, cfg.overlap_words, cfg.min_chunk_words)


def truncate_to_tokens(text: str, max_tokens: int = 512) -> str:
    """Truncate text to a conservative character length approximating max_tokens."""
    max_chars = max_tokens * 3
    if len(text) > max_chars:
        orig_len = len(text)
        truncated = text[:max_chars] + " [...]"
        import logging
        logger = logging.getLogger("termux_forge.deep_research")
        logger.warning(
            f"Truncated text from {orig_len} to {max_chars} chars (>{max_tokens} tokens estimated)"
        )
        return truncated
    return text

