/// TermuxForge — Terminal Screen
///
/// Terminal pane with scrollable ANSI-aware output, command input,
/// command history, connection status indicator, and clear button.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:termux_forge/core/theme/app_colors.dart';
import 'package:termux_forge/presentation/widgets/forge_app_bar.dart';
import 'package:termux_forge/presentation/widgets/status_badge.dart';

/// The terminal screen.
class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocus = FocusNode();
  final List<_TerminalLine> _lines = [];
  final List<String> _history = [];
  int _historyIndex = -1;
  bool _isConnected = true;

  @override
  void initState() {
    super.initState();
    // Add welcome message.
    _lines.addAll([
      _TerminalLine(
        text: '╔══════════════════════════════════════╗',
        color: AppColors.accentBlue,
      ),
      _TerminalLine(
        text: '║       TermuxForge Terminal v0.1      ║',
        color: AppColors.accentBlue,
      ),
      _TerminalLine(
        text: '╚══════════════════════════════════════╝',
        color: AppColors.accentBlue,
      ),
      const _TerminalLine(text: ''),
      const _TerminalLine(
        text: 'Type commands or let agents execute actions.',
        color: AppColors.textSecondary,
      ),
      const _TerminalLine(text: ''),
    ]);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _executeCommand(String cmd) {
    if (cmd.trim().isEmpty) return;

    setState(() {
      _history.add(cmd);
      _historyIndex = _history.length;
      _lines.add(_TerminalLine(text: '\$ $cmd', color: AppColors.success));

      // Simulated responses.
      final output = switch (cmd.trim().split(' ').first) {
        'ls' => 'lib/  test/  pubspec.yaml  README.md',
        'pwd' => '/data/data/com.termux/files/home/termux_forge',
        'echo' => cmd.replaceFirst('echo ', ''),
        'clear' => null,
        'help' =>
          'Available: ls, pwd, echo, clear, help, dart, flutter',
        _ =>
          'Command executed: $cmd',
      };

      if (cmd.trim() == 'clear') {
        _lines.clear();
      } else if (output != null) {
        _lines.add(_TerminalLine(text: output));
      }

      _lines.add(const _TerminalLine(text: ''));
      _inputController.clear();
    });

    // Scroll to bottom.
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _navigateHistory(bool up) {
    if (_history.isEmpty) return;
    setState(() {
      if (up) {
        _historyIndex = (_historyIndex - 1).clamp(0, _history.length - 1);
      } else {
        _historyIndex = (_historyIndex + 1).clamp(0, _history.length);
      }
      if (_historyIndex < _history.length) {
        _inputController.text = _history[_historyIndex];
        _inputController.selection = TextSelection.collapsed(
          offset: _inputController.text.length,
        );
      } else {
        _inputController.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ForgeAppBar(
        title: 'Terminal',
        showBackButton: true,
        actions: [
          StatusBadge(
            label: _isConnected ? 'Connected' : 'Disconnected',
            color: _isConnected ? AppColors.success : AppColors.error,
            pulsing: _isConnected,
            size: BadgeSize.small,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            onPressed: () => setState(_lines.clear),
            tooltip: 'Clear',
          ),
        ],
      ),
      body: Container(
        color: AppColors.backgroundPrimary,
        child: Column(
          children: [
            // ── Output ──
            Expanded(
              child: GestureDetector(
                onTap: () => _inputFocus.requestFocus(),
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: _lines.length,
                  itemBuilder: (_, i) => _TerminalLineWidget(
                    line: _lines[i],
                  ),
                ),
              ),
            ),

            // ── Input ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.backgroundSecondary,
                border: Border(
                  top: BorderSide(color: AppColors.borderSubtle),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '\$ ',
                    style: GoogleFonts.jetBrainsMono(
                      color: AppColors.success,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Expanded(
                    child: KeyboardListener(
                      focusNode: FocusNode(),
                      onKeyEvent: (event) {
                        if (event is KeyDownEvent) {
                          if (event.logicalKey ==
                              LogicalKeyboardKey.arrowUp) {
                            _navigateHistory(true);
                          } else if (event.logicalKey ==
                              LogicalKeyboardKey.arrowDown) {
                            _navigateHistory(false);
                          }
                        }
                      },
                      child: TextField(
                        controller: _inputController,
                        focusNode: _inputFocus,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Enter command...',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                        ),
                        onSubmitted: (cmd) {
                          _executeCommand(cmd);
                          _inputFocus.requestFocus();
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send_rounded, size: 18),
                    onPressed: () {
                      _executeCommand(_inputController.text);
                      _inputFocus.requestFocus();
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single terminal output line.
class _TerminalLine {
  const _TerminalLine({required this.text, this.color});

  final String text;
  final Color? color;
}

class _TerminalLineWidget extends StatelessWidget {
  const _TerminalLineWidget({required this.line});

  final _TerminalLine line;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: SelectableText(
        line.text,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 13,
          color: line.color ?? AppColors.textPrimary,
          height: 1.5,
        ),
      ),
    );
  }
}
