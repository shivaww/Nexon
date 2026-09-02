import '../../data/models/provider_models.dart';

/// Shared chat-message sanitization used before messages are serialized for
/// any provider.
///
/// Chat history contains UI-only and transient entries (empty streaming
/// placeholders, failed assistant messages, welcome cards). Providers reject
/// these as invalid messages, which surfaces as HTTP 400 only after enough
/// turns have accumulated them. This pipeline keeps provider requests clean
/// without mutating the UI session history.
class MessagePipeline {
  MessagePipeline._();

  /// Returns the subset of [messages] that is safe to send to an
  /// OpenAI-compatible chat completions endpoint.
  static List<ChatMessage> sanitizeForProvider(
    List<ChatMessage> messages,
  ) {
    final cleaned = <ChatMessage>[];

    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];

      // Failed UI assistant messages are diagnostics for the user, not
      // conversation turns. Sending them back to the model corrupts the
      // history and can make one HTTP 400 sticky across subsequent requests.
      if (message.isError) continue;

      final hasText = message.text.trim().isNotEmpty;
      final hasAttachments =
          message.images.isNotEmpty ||
          message.videos.isNotEmpty ||
          message.files.isNotEmpty;

      // A stopped or interrupted stream can leave an empty assistant
      // placeholder in the session. The provider rejects empty assistant
      // content, so drop it.
      if (!hasText && !hasAttachments) continue;

      // Nexon stores tool results and injected notices as system messages
      // inside the conversation. OpenAI-compatible providers only allow a
      // leading system message; a system message after user/assistant turns
      // is rejected as HTTP 400. Serialize these as user content on the wire
      // while keeping the UI role unchanged.
      if (message.role == MessageRole.system && i > 0) {
        cleaned.add(
          ChatMessage(
            role: MessageRole.user,
            text: message.text,
            isError: message.isError,
            reasoning: message.reasoning,
            images: message.images,
            videos: message.videos,
            files: message.files,
            tokensPerSec: message.tokensPerSec,
            tokenUsage: message.tokenUsage,
          ),
        );
        continue;
      }

      cleaned.add(message);
    }

    return cleaned;
  }
}
