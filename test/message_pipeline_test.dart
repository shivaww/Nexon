import 'package:flutter_test/flutter_test.dart';
import 'package:nexon/data/models/provider_models.dart';
import 'package:nexon/services/llm/message_pipeline.dart';

void main() {
  group('MessagePipeline.sanitizeForProvider', () {
    test('keeps a healthy system-user-assistant sequence intact', () {
      const messages = [
        ChatMessage(role: MessageRole.system, text: 'system prompt'),
        ChatMessage(role: MessageRole.user, text: 'hello'),
        ChatMessage(role: MessageRole.assistant, text: 'hi there'),
      ];

      final cleaned = MessagePipeline.sanitizeForProvider(messages);

      expect(cleaned.length, 3);
      expect(cleaned[0].role, MessageRole.system);
      expect(cleaned[1].role, MessageRole.user);
      expect(cleaned[2].role, MessageRole.assistant);
    });

    test('drops empty assistant placeholders and merges adjacent user turns', () {
      const messages = [
        ChatMessage(role: MessageRole.user, text: 'first'),
        ChatMessage(role: MessageRole.assistant, text: ''),
        ChatMessage(role: MessageRole.user, text: 'second'),
      ];

      final cleaned = MessagePipeline.sanitizeForProvider(messages);

      expect(cleaned.length, 1);
      expect(cleaned.first.role, MessageRole.user);
      expect(cleaned.first.text, 'first\n\nsecond');
    });

    test('drops failed assistant messages and merges resulting adjacent user turns', () {
      const messages = [
        ChatMessage(role: MessageRole.user, text: 'question'),
        ChatMessage(
          role: MessageRole.assistant,
          text: 'Request failed: Provider error (HTTP 400).',
          isError: true,
        ),
        ChatMessage(role: MessageRole.user, text: 'retry'),
      ];

      final cleaned = MessagePipeline.sanitizeForProvider(messages);

      expect(cleaned.length, 1);
      expect(cleaned.any((m) => m.isError), isFalse);
      expect(cleaned.first.text, 'question\n\nretry');
    });

    test('converts mid-conversation tool result system messages to user and merges adjacent user turns', () {
      const messages = [
        ChatMessage(role: MessageRole.system, text: 'system prompt'),
        ChatMessage(role: MessageRole.user, text: 'run a command'),
        ChatMessage(role: MessageRole.assistant, text: 'Running tool...'),
        ChatMessage(role: MessageRole.system, text: 'Tool Result [sh]: done'),
        ChatMessage(role: MessageRole.user, text: 'continue'),
      ];

      final cleaned = MessagePipeline.sanitizeForProvider(messages);

      expect(cleaned.length, 4);
      expect(cleaned[0].role, MessageRole.system);
      expect(cleaned[3].role, MessageRole.user);
      expect(cleaned[3].text, 'Tool Result [sh]: done\n\ncontinue');
      expect(
        cleaned.where((m) => m.role == MessageRole.system).length,
        1,
      );
    });

    test('handles many accumulated corrupt messages consistently', () {
      final messages = <ChatMessage>[
        const ChatMessage(role: MessageRole.user, text: 'turn 1'),
        const ChatMessage(role: MessageRole.assistant, text: ''),
        const ChatMessage(role: MessageRole.user, text: 'turn 2'),
        const ChatMessage(
          role: MessageRole.assistant,
          text: 'Request failed: Provider error (HTTP 400).',
          isError: true,
        ),
        const ChatMessage(role: MessageRole.user, text: 'turn 3'),
        const ChatMessage(role: MessageRole.assistant, text: 'ok'),
        const ChatMessage(role: MessageRole.system, text: 'Tool Result [read]: data'),
      ];

      final cleaned = MessagePipeline.sanitizeForProvider(messages);

      final roleText = cleaned.map((m) => '${m.role.apiName}:${m.text}').toList();
      expect(
        roleText,
        [
          'user:turn 1\n\nturn 2\n\nturn 3',
          'assistant:ok',
          'user:Tool Result [read]: data',
        ],
      );
    });
    test('is provider-agnostic for the same accumulated input', () {
      const providers = ['openrouter', 'mistral', 'anthropic'];
      const messages = [
        ChatMessage(role: MessageRole.user, text: 'hello'),
        ChatMessage(role: MessageRole.assistant, text: ''),
        ChatMessage(
          role: MessageRole.assistant,
          text: 'Request failed: Provider error (HTTP 400).',
          isError: true,
        ),
        ChatMessage(role: MessageRole.system, text: 'Tool Result [read]: ok'),
      ];

      for (final provider in providers) {
        final cleaned = MessagePipeline.sanitizeForProvider(messages);
        final roles = cleaned.map((m) => m.role).toList();

        expect(
          roles.where((r) => r == MessageRole.system).length,
          0,
          reason: 'provider $provider must not send mid-conversation system',
        );
        expect(
          cleaned.any((m) => m.isError),
          isFalse,
          reason: 'provider $provider must not receive failed messages',
        );
      }
    });
  });
}
