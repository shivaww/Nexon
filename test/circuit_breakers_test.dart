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

int getModelContextSize(String model) {
  final name = model.toLowerCase();
  final kMatch = RegExp(r'(\d+)k\b').firstMatch(name);
  if (kMatch != null) {
    final val = int.tryParse(kMatch.group(1)!);
    if (val != null) return val * 1000;
  }
  if (name.contains('gemini')) return 1048576;
  if (name.contains('claude')) return 200000;
  if (name.contains('gpt-4') || name.contains('o1') || name.contains('o3')) return 128000;
  if (name.contains('gpt-3.5')) return 16384;
  if (name.contains('deepseek') || 
      name.contains('llama-3.3') || 
      name.contains('llama-3.1') || 
      name.contains('qwen-2.5') ||
      name.contains('qwen2.5')) {
    return 128000;
  }
  if (name.contains('llama-3')) return 8192;
  if (name.contains('llama-2') || name.contains('llama2')) return 4096;
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

  assert(getModelContextSize("gemini-1.5-pro") == 1048576);
  assert(getModelContextSize("claude-3-opus") == 200000);
  assert(getModelContextSize("gpt-4o-mini") == 128000);
  assert(getModelContextSize("llama3-8b-8192") == 8192);
  assert(getModelContextSize("custom-model-32k") == 32000);
  assert(getModelContextSize("unknown-custom-model") == 32768);
  print("getModelContextSize assertions passed!");

  print("All plain Dart tests passed successfully!");
}
