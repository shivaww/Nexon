/// TermuxForge — Model Control Center Screen
///
/// Provider list with status badges, API key entry, model picker per
/// mode, capability tags, cost hints, and battle mode selector.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:termux_forge/core/theme/app_colors.dart';
import 'package:termux_forge/presentation/widgets/forge_app_bar.dart';
import 'package:termux_forge/presentation/widgets/glass_card.dart';
import 'package:termux_forge/presentation/widgets/mode_selector.dart';
import 'package:termux_forge/presentation/widgets/status_badge.dart';

/// Demo model data.
class _ModelInfo {
  const _ModelInfo({
    required this.name,
    required this.provider,
    required this.capabilities,
    this.contextWindow = '200K',
    this.costPer1kInput,
    this.costPer1kOutput,
    this.isSelected = false,
  });

  final String name;
  final String provider;
  final List<String> capabilities;
  final String contextWindow;
  final double? costPer1kInput;
  final double? costPer1kOutput;
  final bool isSelected;
}

/// The model control center screen.
class ModelCenterScreen extends StatefulWidget {
  const ModelCenterScreen({super.key});

  @override
  State<ModelCenterScreen> createState() => _ModelCenterScreenState();
}

class _ModelCenterScreenState extends State<ModelCenterScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _selectedMode = 'code';

  final List<_ModelInfo> _models = const [
    _ModelInfo(
      name: 'Claude 4 Sonnet',
      provider: 'Anthropic',
      capabilities: ['code', 'reasoning', 'analysis', 'long-context'],
      contextWindow: '200K',
      costPer1kInput: 0.003,
      costPer1kOutput: 0.015,
      isSelected: true,
    ),
    _ModelInfo(
      name: 'Claude 4 Opus',
      provider: 'Anthropic',
      capabilities: ['code', 'reasoning', 'complex', 'creative'],
      contextWindow: '200K',
      costPer1kInput: 0.015,
      costPer1kOutput: 0.075,
    ),
    _ModelInfo(
      name: 'GPT-4.1',
      provider: 'OpenAI',
      capabilities: ['code', 'reasoning', 'tools', 'vision'],
      contextWindow: '1M',
      costPer1kInput: 0.002,
      costPer1kOutput: 0.008,
    ),
    _ModelInfo(
      name: 'GPT-4.1 mini',
      provider: 'OpenAI',
      capabilities: ['code', 'fast', 'tools'],
      contextWindow: '1M',
      costPer1kInput: 0.0004,
      costPer1kOutput: 0.0016,
    ),
    _ModelInfo(
      name: 'Gemini 2.5 Pro',
      provider: 'Google',
      capabilities: ['code', 'reasoning', 'thinking', 'long-context'],
      contextWindow: '1M',
      costPer1kInput: 0.00125,
      costPer1kOutput: 0.01,
    ),
    _ModelInfo(
      name: 'DeepSeek R1',
      provider: 'DeepSeek',
      capabilities: ['code', 'reasoning', 'math', 'open-source'],
      contextWindow: '128K',
      costPer1kInput: 0.00055,
      costPer1kOutput: 0.0022,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Color _providerColor(String provider) {
    return switch (provider) {
      'Anthropic' => AppColors.accentPurple,
      'OpenAI' => AppColors.success,
      'Google' => AppColors.accentBlue,
      'DeepSeek' => AppColors.accentTeal,
      _ => AppColors.textSecondary,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ForgeAppBar(
        title: 'Model Center',
        showBackButton: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: () {},
            tooltip: 'Refresh models',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Models'),
            Tab(text: 'Per Mode'),
            Tab(text: 'Battle'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildModelList(context),
          _buildPerModeConfig(context),
          _buildBattleConfig(context),
        ],
      ),
    );
  }

  Widget _buildModelList(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _models.length,
      itemBuilder: (_, i) {
        final model = _models[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GlassCard(
            padding: const EdgeInsets.all(16),
            borderRadius: 14,
            borderColor: model.isSelected
                ? AppColors.accentBlue.withValues(alpha: 0.3)
                : null,
            onTap: () {
              // TODO: Select model.
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            model.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          StatusBadge(
                            label: model.provider,
                            color: _providerColor(model.provider),
                            size: BadgeSize.small,
                          ),
                        ],
                      ),
                    ),
                    if (model.isSelected)
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.accentBlue.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: AppColors.accentBlue,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                // Capability tags.
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: model.capabilities.map((cap) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundTertiary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        cap,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                // Cost + context info.
                Row(
                  children: [
                    Icon(Icons.memory_rounded, size: 14,
                        color: AppColors.textTertiary),
                    const SizedBox(width: 4),
                    Text(
                      model.contextWindow,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    if (model.costPer1kInput != null) ...[
                      Icon(Icons.attach_money_rounded, size: 14,
                          color: AppColors.textTertiary),
                      const SizedBox(width: 2),
                      Text(
                        '\$${model.costPer1kInput!.toStringAsFixed(4)}/1K in',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '\$${model.costPer1kOutput!.toStringAsFixed(4)}/1K out',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ).animate().fadeIn(
            delay: Duration(milliseconds: i * 60),
            duration: 250.ms,
          ),
        );
      },
    );
  }

  Widget _buildPerModeConfig(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: ModeSelector(
            currentMode: _selectedMode,
            onModeChanged: (m) => setState(() => _selectedMode = m),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Default model for "${_selectedMode}" mode',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 12),
                    ..._models.map((m) => RadioListTile<String>(
                      title: Text(m.name, style: const TextStyle(fontSize: 14)),
                      subtitle: Text(m.provider,
                          style: const TextStyle(fontSize: 12)),
                      value: m.name,
                      groupValue: 'Claude 4 Sonnet',
                      onChanged: (_) {},
                      dense: true,
                    )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBattleConfig(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassCard(
            padding: const EdgeInsets.all(20),
            gradient: AppColors.cardGradient,
            child: Column(
              children: [
                const Icon(
                  Icons.compare_arrows_rounded,
                  size: 48,
                  color: AppColors.accentBlue,
                ),
                const SizedBox(height: 12),
                Text(
                  'Battle Mode',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Compare two models side-by-side on the same prompt',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Model A', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: 'Claude 4 Sonnet',
            items: _models
                .map((m) => DropdownMenuItem(
                      value: m.name,
                      child: Text(m.name, style: const TextStyle(fontSize: 14)),
                    ))
                .toList(),
            onChanged: (_) {},
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(height: 16),
          Text('Model B', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: 'GPT-4.1',
            items: _models
                .map((m) => DropdownMenuItem(
                      value: m.name,
                      child: Text(m.name, style: const TextStyle(fontSize: 14)),
                    ))
                .toList(),
            onChanged: (_) {},
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start Battle'),
            ),
          ),
        ],
      ),
    );
  }
}
