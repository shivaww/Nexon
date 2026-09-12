// Deep Research helpers: tool-path resolution plus the research_state fence builder
// Extracted on: 2026-08-26T18:20:45.692448

import 'dart:convert';
import 'package:nexon/widgets/artifact_widgets.dart';

void _resolveToolPaths(Map<String, dynamic> params, String workspace) {
  final resolved =
      resolveToolPathValue(params, workspace) as Map<String, dynamic>;
  params
    ..clear()
    ..addAll(resolved);
}

void resolveToolPaths(Map<String, dynamic> params, String workspace) =>
    _resolveToolPaths(params, workspace);

/// Fenced ```json marker carrying the research state map.
String researchStateFence(Map<String, dynamic> stateMap) =>
    '```json\n{"research_state": ${jsonEncode(stateMap)}}\n```';
