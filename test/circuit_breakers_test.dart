String normalizeQueryOrUrl(String input) {
  return input
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s\-\.\:\/]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

bool detectMalformedTags(String responseText, List searchMatches, List readUrlMatches, dynamic mcpMatch) {
  bool isMalformed = false;
  final hasRawSearchTag = responseText.contains('<search_request') || responseText.contains('</search_request');
  final hasRawReadTag = responseText.contains('<read_url') || responseText.contains('</read_url');
  final hasRawMcpTag = responseText.contains('<mcp_request') || responseText.contains('</mcp_request');
  
  if ((hasRawSearchTag && searchMatches.isEmpty) ||
      (hasRawReadTag && readUrlMatches.isEmpty) ||
      (hasRawMcpTag && mcpMatch == null)) {
    isMalformed = true;
  }
  return isMalformed;
}

// getModelContextSize: purely structural — reads context size from the model
// name itself.  No hardcoded vendor/brand names so any user-chosen model is
// accepted without restriction.  Used only as an advisory hint; no feature is
// ever blocked based on this value.
int getModelContextSize(String model) {
  final name = model.toLowerCase();
  // 1. Trailing bare number encodes the context window, e.g. "llama3-8b-8192" → 8192.
  final trailingCtxMatch = RegExp(r'-(\d{4,7})$').firstMatch(name);
  if (trailingCtxMatch != null) {
    final val = int.tryParse(trailingCtxMatch.group(1)!);
    if (val != null) return val;
  }
  // 2. "Nk" suffix, e.g. "custom-model-32k" → 32 000.
  final kMatch = RegExp(r'(\d+)k\b').firstMatch(name);
  if (kMatch != null) {
    final val = int.tryParse(kMatch.group(1)!);
    if (val != null) return val * 1000;
  }
  // 3. Safe generous default — never blocks the user.
  return 32768;
}

void main() {
  print("Running plain Dart circuit breaker checks...");
  
  assert(normalizeQueryOrUrl("llama.cpp benchmark") == "llama.cpp benchmark");
  assert(normalizeQueryOrUrl("llama.cpp benchmark ") == "llama.cpp benchmark");
  assert(normalizeQueryOrUrl("Llama.cpp Benchmark!") == "llama.cpp benchmark");
  assert(normalizeQueryOrUrl("https://example.com/some-page?q=1") == "https://example.com/some-pageq1");
  print("normalizeQueryOrUrl assertions passed!");

  final r1 = "<search_request>query without closing tag";
  assert(detectMalformedTags(r1, [], [], null) == true);
  
  final r2 = "<read_url>http://example.com";
  assert(detectMalformedTags(r2, [], [], null) == true);
  
  final r3 = "<search_request>query</search_request>";
  assert(detectMalformedTags(r3, [1], [], null) == false);
  print("detectMalformedTags assertions passed!");

  // Structural heuristics only — no hardcoded vendor/brand names.
  assert(getModelContextSize("llama3-8b-8192") == 8192);      // trailing number
  assert(getModelContextSize("custom-model-32k") == 32000);   // Nk suffix
  assert(getModelContextSize("unknown-custom-model") == 32768); // safe default
  assert(getModelContextSize("mymodel-128k-8192") == 8192);   // trailing number beats Nk
  print("getModelContextSize assertions passed!");

  print("All plain Dart tests passed successfully!");
}
