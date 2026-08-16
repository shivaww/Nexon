library;

class SlashCommandCallbacks {
  const SlashCommandCallbacks({
    required this.createNew,
    required this.listSessions,
    required this.switchSession,
    required this.saveSession,
    required this.resumeSession,
    required this.summarizeSession,
    required this.createCheckpoint,
    required this.restoreCheckpoint,
    required this.listCheckpoints,
    required this.clearCurrent,
    required this.showSystemMessage,
  });

  final Future<String> Function(String? title) createNew;
  final Future<String> Function() listSessions;
  final Future<String> Function(String target) switchSession;
  final Future<String> Function({String? name, String? path}) saveSession;
  final Future<String> Function(String target) resumeSession;
  final Future<String> Function(int keepLast) summarizeSession;
  final Future<String> Function(String? name) createCheckpoint;
  final Future<String> Function(String target) restoreCheckpoint;
  final Future<String> Function() listCheckpoints;
  final Future<String> Function() clearCurrent;
  final Future<void> Function(String message) showSystemMessage;
}

class SlashCommandService {
  /// Whether agentic file access is enabled; gates /new, /list, /save.
  static bool agenticAccessEnabled = true;

  static const Set<String> _agenticOnly = <String>{'/new', '/list', '/save'};

  /// Catalog filtered by current agentic access for autocomplete and /help.
  static List<String> availableCatalog() {
    if (agenticAccessEnabled) return commandCatalog;
    return commandCatalog
        .where((c) => !_agenticOnly.contains(c.split(' ').first))
        .toList(growable: false);
  }

  static const List<String> commandCatalog = <String>[
    '/new [title]',
    '/list',
    '/switch <id|index>',
    '/save [name] [path]',
    '/resume <name|id|path>',
    '/load <name|id|path>',
    '/summarize [keep_last=5]',
    '/checkpoint [name]',
    '/ckpt [name]',
    '/restore <id>',
    '/list_ckpt',
    '/clear',
    '/help',
  ];

  static List<String> filterCommands(String input) {
    if (!input.trimLeft().startsWith('/')) return const <String>[];
    final needle = input.trim().toLowerCase();
    return availableCatalog()
        .where((cmd) => cmd.toLowerCase().startsWith(needle))
        .toList(growable: false);
  }

  static Future<void> handle(
    String rawPrompt,
    SlashCommandCallbacks callbacks,
  ) async {
    final trimmed = rawPrompt.trim();
    if (!trimmed.startsWith('/')) return;
    final parts = trimmed.split(RegExp(r'\s+'));
    final command = parts.first.toLowerCase();
    final args = parts.length > 1 ? parts.sublist(1) : const <String>[];

    if (!agenticAccessEnabled && _agenticOnly.contains(command)) {
      await callbacks.showSystemMessage(
        '$command is only available when Agentic File Access is enabled. '
        'Turn it on in Input & Settings → Features.',
      );
      return;
    }

    String output;
    switch (command) {
      case '/new':
        output = await callbacks.createNew(
          args.isEmpty ? null : args.join(' ').trim(),
        );
        break;
      case '/list':
        output = await callbacks.listSessions();
        break;
      case '/switch':
        if (args.isEmpty) {
          output = 'Usage: /switch <id|index>';
        } else {
          output = await callbacks.switchSession(args.join(' ').trim());
        }
        break;
      case '/save':
        output = await callbacks.saveSession(
          name: args.isEmpty ? null : args.first.trim(),
          path: args.length > 1 ? args.sublist(1).join(' ').trim() : null,
        );
        break;
      case '/resume':
      case '/load':
        if (args.isEmpty) {
          output = 'Usage: /resume <name|id|path>';
        } else {
          output = await callbacks.resumeSession(args.join(' ').trim());
        }
        break;
      case '/summarize':
        var keepLast = 5;
        if (args.isNotEmpty) {
          keepLast = int.tryParse(args.first.trim()) ?? 5;
        }
        output = await callbacks.summarizeSession(keepLast);
        break;
      case '/checkpoint':
      case '/ckpt':
        output = await callbacks.createCheckpoint(
          args.isEmpty ? null : args.join(' ').trim(),
        );
        break;
      case '/restore':
        if (args.isEmpty) {
          output = 'Usage: /restore <id>';
        } else {
          output = await callbacks.restoreCheckpoint(args.join(' ').trim());
        }
        break;
      case '/list_ckpt':
        output = await callbacks.listCheckpoints();
        break;
      case '/clear':
        output = await callbacks.clearCurrent();
        break;
      case '/help':
        output = 'Slash commands:\n${availableCatalog().map((c) => '- $c').join('\n')}';
        break;
      default:
        output = 'Unknown slash command: $command';
    }
    await callbacks.showSystemMessage(output);
  }
}
