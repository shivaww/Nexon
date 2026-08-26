// Extracted from main.dart lines 8554-8675
// Extracted on: 2026-08-26T18:20:45.733328

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexon/main.dart';

class ChatHeader extends StatefulWidget {
  const ChatHeader({
    required this.provider,
    required this.settings,
    required this.model,
    required this.onOpenProvider,
    required this.onOpenModel,
    this.onOpenLiveVoice,
    super.key,
  });

  final ProviderDefinition provider;
  final ProviderSettings settings;
  final String model;
  final VoidCallback onOpenProvider;
  final VoidCallback onOpenModel;
  final VoidCallback? onOpenLiveVoice;

  @override
  State<ChatHeader> createState() => _ChatHeaderState();
}

class _ChatHeaderState extends State<ChatHeader> {
  bool _isMuted = false;

  @override
  Widget build(BuildContext context) {
    final hasKey = widget.settings.apiKey.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(
        children: [
          // Target #1: Hamburger menu button -> circular glass button
          Builder(
            builder: (context) {
              final hasDrawer = Scaffold.hasDrawer(context);
              if (!hasDrawer) return const SizedBox.shrink();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LiquidGlassIconButton(
                    icon: Icons.menu_rounded,
                    size: 42,
                    tooltip: 'Chats',
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                  const SizedBox(width: 8),
                ],
              );
            },
          ),
          GestureDetector(
            onTap: widget.onOpenProvider,
            child: Tooltip(
              message: '${widget.provider.name} settings',
              child: ProviderAvatar(
                label: widget.provider.shortName,
                small: true,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Target #3: Model selector -> pill-shaped glass container
          Expanded(
            child: LiquidGlassSurface(
              borderRadius: BorderRadius.circular(30),
              onTap: widget.onOpenModel,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: Color(0xFF7B4E2E),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.model,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2D241C),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: Color(0xFF7B4E2E),
                  ),
                ],
              ),
            ),
          ),
          if (widget.onOpenLiveVoice != null) ...[
            const SizedBox(width: 8),
            LiquidGlassIconButton(
              icon: Icons.graphic_eq_rounded,
              size: 38,
              tooltip: 'Live Voice Mode',
              onPressed: widget.onOpenLiveVoice!,
            ),
          ],
          const SizedBox(width: 8),
          Icon(
            hasKey || !widget.provider.requiresKey
                ? Icons.lock_outline
                : Icons.lock_open_outlined,
            size: 18,
            color: hasKey || !widget.provider.requiresKey
                ? const Color(0xFF36764D)
                : const Color(0xFF9B4D39),
          ),
        ],
      ),
    );
  }
}
