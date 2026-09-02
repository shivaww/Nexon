// Extracted from main.dart lines 8554-8675
// Extracted on: 2026-08-26T18:20:45.733328

import 'package:flutter/material.dart';
import 'package:nexon/widgets/liquid_glass_widgets.dart';
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
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Row(
        children: [
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
                  const SizedBox(width: 10),
                ],
              );
            },
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openSessionSheet,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.model,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2D241C),
                    ),
                  ),
                  Text(
                    widget.provider.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8B7355),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          LiquidGlassIconButton(
            icon: Icons.tune_rounded,
            size: 40,
            tooltip: 'Model & provider settings',
            onPressed: _openSessionSheet,
          ),
        ],
      ),
    );
  }

  void _openSessionSheet() {
    final hasKey = widget.settings.apiKey.trim().isNotEmpty;
    final keyOk = hasKey || !widget.provider.requiresKey;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SheetFrame(
        title: widget.model,
        subtitle: widget.provider.name,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetRow(
              icon: Icons.auto_awesome,
              label: 'Model',
              value: widget.model,
              onTap: () {
                Navigator.pop(context);
                widget.onOpenModel();
              },
            ),
            _sheetRow(
              icon: Icons.hub_outlined,
              label: 'Provider settings',
              value: widget.provider.name,
              onTap: () {
                Navigator.pop(context);
                widget.onOpenProvider();
              },
            ),
            if (widget.onOpenLiveVoice != null)
              _sheetRow(
                icon: Icons.graphic_eq_rounded,
                label: 'Live voice mode',
                value: 'Hands-free conversation',
                onTap: () {
                  Navigator.pop(context);
                  widget.onOpenLiveVoice!();
                },
              ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF5EFE4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE7D8C4)),
              ),
              child: Row(
                children: [
                  Icon(
                    keyOk ? Icons.lock_outline : Icons.lock_open_outlined,
                    size: 16,
                    color: keyOk
                        ? const Color(0xFF36764D)
                        : const Color(0xFF9B4D39),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.provider.requiresKey
                          ? (hasKey ? 'API key set' : 'No API key set')
                          : 'No API key required',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF4A3424),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7D8C4)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 17, color: const Color(0xFF7B4E2E)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2D241C),
                      ),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8B7355),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Color(0xFF8B7355),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
