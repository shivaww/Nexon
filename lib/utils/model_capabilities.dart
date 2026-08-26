// Extracted from main.dart lines 13105-13356
// Extracted on: 2026-08-26T18:20:45.711254

import 'package:nexon/main.dart';

/// Returns true if [modelName] supports image/vision input.
///
/// Detection priority:
/// 1. Runtime set populated from API modality metadata during [fetchModels].
/// 2. Keyword heuristics — catches models with capability keywords in their
///    name regardless of provider-specific naming conventions.
bool modelHasVision(String modelName) {
  // 1. Runtime API-detected set (most reliable)
  if (ChatClient.modelsWithVision.contains(modelName)) return true;

  final lower = modelName.toLowerCase();

  // 2. Generic capability keywords in model name
  //    These reliably indicate vision regardless of model family.
  if (lower.contains('vision') ||
      lower.contains('-vl') ||
      lower.contains('vlm') ||
      lower.contains('visual') ||
      lower.contains('multimodal') ||
      lower.contains('omni') ||
      lower.contains('llava') ||
      lower.contains('moondream') ||
      lower.contains('pixtral') ||
      lower.contains('minicpm-v') ||
      lower.contains('internvl') ||
      lower.contains('smolvlm') ||
      lower.contains('cogvlm') ||
      lower.contains('idefics') ||
      lower.contains('bakllava')) {
    return true;
  }

  // 3. Well-known model families where vision is a standard feature.
  //    Kept minimal — only cover broad families, not specific version numbers,
  //    so new models in these families are automatically detected.

  // OpenAI gpt-4 class (gpt-4o, gpt-4-turbo, gpt-4.1, gpt-4.5, etc.)
  if (lower.startsWith('gpt-4') || lower.startsWith('chatgpt-4o')) return true;

  // OpenAI o-series (o1, o3, o4 etc. — all support vision)
  if (RegExp(r'^o\d').hasMatch(lower)) return true;

  // Anthropic Claude 3+ family (all claude-3, claude-4+ support vision)
  if (RegExp(r'claude-[3-9]').hasMatch(lower)) return true;

  // Google Gemini 1.5+ and Gemini 2+ (all support vision)
  if (RegExp(r'gemini-(1\.[5-9]|[2-9])').hasMatch(lower) ||
      lower.contains('gemini-flash') ||
      lower.contains('gemini-pro')) {
    return true;
  }

  // Google Gemma 3+ (has vision)
  if (RegExp(r'gemma-?[3-9]').hasMatch(lower)) return true;

  // Qwen VL / Qwen 2.x VL
  if (lower.contains('qwen') && lower.contains('-vl')) return true;

  // Llama 3.2+ vision variants
  if (lower.contains('llama-3.2') && lower.contains('vision')) return true;

  // Microsoft Phi vision variants
  if (lower.contains('phi') && lower.contains('vision')) return true;
  if (lower.contains('phi-4-multimodal')) return true;

  // Mistral vision (pixtral already caught above; mistral-medium-3+)
  if (lower.contains('mistral') && lower.contains('medium')) return true;

  // Molmo, Aria (always multimodal)
  if (lower.contains('molmo') || lower.contains('aria')) return true;

  return false;
}

/// Returns true if [modelName] can generate images from text (text-to-image).
///
/// Detection priority:
/// 1. Runtime set populated from API output-modality metadata during [fetchModels].
/// 2. Keyword heuristics — catches models whose names indicate image generation.
bool modelCanGenerateImages(String modelName) {
  // 1. Runtime API-detected set
  if (ChatClient.modelsWithImageGeneration.contains(modelName)) return true;

  final lower = modelName.toLowerCase();

  // 2. Generic image-generation keywords
  if (lower.contains('dall-e') ||
      lower.contains('dalle') ||
      lower.contains('flux') ||
      lower.contains('stable-diffusion') ||
      lower.contains('stable diffusion') ||
      lower.contains('qwen-image') ||
      lower.contains('trellis') ||
      lower.contains('sdxl') ||
      lower.contains('imagen') ||
      lower.contains('midjourney') ||
      lower.contains('ideogram') ||
      lower.contains('kandinsky') ||
      lower.contains('wuerstchen') ||
      lower.contains('aura-flow') ||
      lower.contains('kolors') ||
      lower.contains('playgroundai') ||
      lower.contains('text-to-image') ||
      lower.contains('img-gen') ||
      lower.contains('image-gen') ||
      lower.contains('image-generation')) {
    return true;
  }

  // Gemini image-gen models
  if (lower.contains('gemini') && lower.contains('image')) return true;

  return false;
}

/// Returns true if [modelName] can generate videos from text (text-to-video).
///
/// Detection priority:
/// 1. Runtime set populated from API output-modality metadata during [fetchModels].
/// 2. Keyword heuristics — catches models whose names indicate video generation.
bool modelCanGenerateVideos(String modelName) {
  // 1. Runtime API-detected set
  if (ChatClient.modelsWithVideoGeneration.contains(modelName)) return true;

  final lower = modelName.toLowerCase();

  // 2. Generic video-generation keywords
  if (lower.contains('video') ||
      lower.contains('cosmos') ||
      lower.contains('sora') ||
      lower.contains('runway') ||
      lower.contains('kling') ||
      lower.contains('pika') ||
      lower.contains('luma') ||
      lower.contains('veo') ||
      lower.contains('minimax-video') ||
      lower.contains('cogvideo') ||
      lower.contains('wan') ||
      lower.contains('text-to-video') ||
      lower.contains('vid-gen') ||
      lower.contains('video-gen') ||
      lower.contains('video-generation')) {
    return true;
  }

  return false;
}

/// Returns true if [modelName] is a dedicated reasoning / coding model.
///
/// Detection uses keyword heuristics. Runtime metadata from providers that
/// expose capability fields (e.g. OpenRouter's `reasoning` flag) is NOT yet
/// parsed, so this relies solely on name patterns.
bool modelIsReasoningOrCoding(String modelName) {
  final lower = modelName.toLowerCase();

  // Reasoning keywords
  if (lower.contains('reason') ||
      lower.contains('think') ||
      lower.contains('reflect') ||
      lower.contains('qwq') ||
      lower.contains('marco-o') ||
      lower.contains('skywork-o') ||
      lower.contains('deepseek-r') ||
      lower.contains('-r1') ||
      lower.contains('-r2') ||
      lower.contains('aya-expanse')) {
    return true;
  }

  // OpenAI o-series reasoning models (o1, o3, o4 …)
  // BUT NOT other "o" models like "olmo", "ollama" etc.
  if (RegExp(r'\bo[1-9]\b').hasMatch(lower)) return true;

  // Coding-specialist keywords
  if (lower.contains('coder') ||
      lower.contains('codex') ||
      lower.contains('starcoder') ||
      lower.contains('deepseek-coder') ||
      lower.contains('qwen-coder') ||
      lower.contains('qwen2.5-coder') ||
      lower.contains('yi-coder') ||
      lower.contains('wizardcoder') ||
      lower.contains('phind-code') ||
      lower.contains('code-llama') ||
      lower.contains('codellama') ||
      lower.contains('granite-code') ||
      lower.contains('-code-') ||
      lower.contains('instruct-code') ||
      lower.contains('code-instruct')) {
    return true;
  }

  return false;
}

/// Classifies [modelName] into a category string.
///
/// Priority order (a model can only have one category here):
/// image > video > vision > reasoning > normal
String modelCategoryOf(String modelName) {
  if (modelCanGenerateImages(modelName)) return 'image';
  if (modelCanGenerateVideos(modelName)) return 'video';
  if (modelHasVision(modelName)) return 'vision';
  if (modelIsReasoningOrCoding(modelName)) return 'reasoning';
  return 'normal';
}

/// Counts of models per category for a given model list.
class _ModelCounts {
  const _ModelCounts({
    required this.total,
    required this.normal,
    required this.reasoning,
    required this.vision,
    required this.image,
    required this.video,
  });

  final int total;
  final int normal;
  final int reasoning;
  final int vision;
  final int image;
  final int video;

  factory _ModelCounts.of(List<String> models) {
    int normal = 0, reasoning = 0, vision = 0, image = 0, video = 0;
    for (final m in models) {
      switch (modelCategoryOf(m)) {
        case 'image':
          image++;
        case 'video':
          video++;
        case 'vision':
          vision++;
        case 'reasoning':
          reasoning++;
        default:
          normal++;
      }
    }
    return _ModelCounts(
      total: models.length,
      normal: normal,
      reasoning: reasoning,
      vision: vision,
      image: image,
      video: video,
    );
  }
}
