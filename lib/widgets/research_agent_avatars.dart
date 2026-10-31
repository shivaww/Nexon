import 'package:flutter/material.dart';

import 'package:nexon/widgets/bot_avatar.dart';

/// The three Deep Research agents, shown as animated faces.
///
/// Replaces the old PLAN/RESEARCH/WRITE text strip. Keeps the same public
/// API so the call site in research_widgets.dart is unchanged. Each avatar
/// maps the pipeline status onto one of the three bot states:
///   planning          -> planner working
///   running           -> researcher working, planner done
///   generating_report -> writer working
///   interrupted       -> researcher sleeping
class ResearchAgentAvatars extends StatelessWidget {
  const ResearchAgentAvatars({
    super.key,
    required this.status,
    required this.isSending,
  });

  final String status;
  final bool isSending;

  static const double _avatarSize = 26;

  @override
  Widget build(BuildContext context) {
    final bool live = isSending;

    // Which agent is currently on stage (-1 = none).
    int active = -1;
    if (live) {
      switch (status) {
        case 'planning':
          active = 0;
        case 'running':
          active = 1;
        case 'generating_report':
          active = 2;
      }
    }

    BotAvatarState stateFor(int i) {
      if (active == i) return BotAvatarState.working;
      if (!live && status == 'running' && i == 1) {
        // Interrupted mid-research: the researcher is the one that stalled.
        return BotAvatarState.sleeping;
      }
      return BotAvatarState.idle;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        BotAvatar(
          type: 'clover',
          state: stateFor(0),
          size: _avatarSize,
          label: 'PLAN',
          seed: 0.0,
          paused: !live,
        ),
        const SizedBox(width: 4),
        BotAvatar(
          type: 'star',
          state: stateFor(1),
          size: _avatarSize,
          label: 'RESEARCH',
          seed: 0.33,
          paused: !live,
        ),
        const SizedBox(width: 4),
        BotAvatar(
          type: 'cat',
          state: stateFor(2),
          size: _avatarSize,
          label: 'WRITE',
          seed: 0.66,
          paused: !live,
        ),
      ],
    );
  }
}
