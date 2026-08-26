// ============================================================================
// NexonChart — template-based chart rendering, 'Field Instrument' edition.
// LLMs emit a simple line-based format; the app renders crafted figures.
// Design: parchment/espresso surfaces, ink baseline signature, mono data voice.
// ============================================================================

import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';

const String _kMono = 'monospace';

// ── Design tokens ───────────────────────────────────────────────────────────

class _ChartTheme {
  final Color surface;
  final Color ink;
  final Color inkSoft;
  final Color muted;
  final Color grid;
  final Color baseline;
  final Color tooltipBg;
  final Color tooltipText;
  final Color errorBg;
  final Color errorBorder;
  final Color errorText;
  final List<Color> palette;
  final Duration anim;
  final String? uiFamily;

  const _ChartTheme({
    required this.surface,
    required this.ink,
    required this.inkSoft,
    required this.muted,
    required this.grid,
    required this.baseline,
    required this.tooltipBg,
    required this.tooltipText,
    required this.errorBg,
    required this.errorBorder,
    required this.errorText,
    required this.palette,
    this.anim = const Duration(milliseconds: 380),
    this.uiFamily,
  });

  static const List<Color> _lightPalette = [
    Color(0xFFC15F3C), // clay
    Color(0xFF58789B), // river
    Color(0xFFD9A441), // ochre
    Color(0xFF7D8A4E), // moss
    Color(0xFF96587A), // mulberry
    Color(0xFF47857A), // teal earth
    Color(0xFF6E7B8A), // slate
    Color(0xFFA04428), // rust
  ];

  static const List<Color> _darkPalette = [
    Color(0xFFE08A63),
    Color(0xFF7FA3C7),
    Color(0xFFE5B95C),
    Color(0xFFA3B36B),
    Color(0xFFC084A6),
    Color(0xFF6FAF9F),
    Color(0xFF93A1B0),
    Color(0xFFC96F4A),
  ];

  static const _ChartTheme light = _ChartTheme(
    surface: Color(0xFFFFFBF2),
    ink: Color(0xFF2D241C),
    inkSoft: Color(0xFF5F4C3A),
    muted: Color(0xFF8B7355),
    grid: Color(0xFFE7D8C4),
    baseline: Color(0xFF2D241C),
    tooltipBg: Color(0xFF2D241C),
    tooltipText: Color(0xFFFFFBF2),
    errorBg: Color(0xFFFAEDE7),
    errorBorder: Color(0xFFDCA893),
    errorText: Color(0xFF8C4A32),
    palette: _lightPalette,
  );

  static const _ChartTheme dark = _ChartTheme(
    surface: Color(0xFF1C1712),
    ink: Color(0xFFF0E7DA),
    inkSoft: Color(0xFFD9C9B2),
    muted: Color(0xFFA08B72),
    grid: Color(0xFF3A3128),
    baseline: Color(0xFFF0E7DA),
    tooltipBg: Color(0xFFF0E7DA),
    tooltipText: Color(0xFF1C1712),
    errorBg: Color(0xFF2A1B15),
    errorBorder: Color(0xFF6E4434),
    errorText: Color(0xFFE0A08C),
    palette: _darkPalette,
  );

  static _ChartTheme of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduce = MediaQuery.of(context).disableAnimations;
    final base = isDark ? _ChartTheme.dark : _ChartTheme.light;
    return base.copyWith(
      anim: reduce ? Duration.zero : const Duration(milliseconds: 380),
      uiFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
    );
  }

  _ChartTheme copyWith({Duration? anim, String? uiFamily}) => _ChartTheme(
        surface: surface,
        ink: ink,
        inkSoft: inkSoft,
        muted: muted,
        grid: grid,
        baseline: baseline,
        tooltipBg: tooltipBg,
        tooltipText: tooltipText,
        errorBg: errorBg,
        errorBorder: errorBorder,
        errorText: errorText,
        palette: palette,
        anim: anim ?? this.anim,
        uiFamily: uiFamily ?? this.uiFamily,
      );

  Color series(int i) => palette[i % palette.length];

  Color textOn(Color c) =>
      c.computeLuminance() > 0.45 ? const Color(0xFF2D241C) : const Color(0xFFFFFBF2);

  TextStyle eyebrow() => TextStyle(
        fontFamily: _kMono,
        fontSize: 9,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.4,
        color: muted,
      );

  TextStyle title() => TextStyle(
        fontFamily: uiFamily,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: ink,
      );

  TextStyle tick() => TextStyle(fontFamily: _kMono, fontSize: 9.5, color: muted);

  TextStyle cat() => TextStyle(fontFamily: uiFamily, fontSize: 10, color: muted);

  TextStyle value() => TextStyle(
        fontFamily: _kMono,
        fontSize: 9.5,
        fontWeight: FontWeight.w500,
        color: inkSoft,
      );

  TextStyle legend() => TextStyle(
        fontFamily: uiFamily,
        fontSize: 10.5,
        fontWeight: FontWeight.w500,
        color: muted,
      );

  TextStyle stat() => TextStyle(fontFamily: _kMono, fontSize: 9.5, color: muted);

  TextStyle tooltipStyle() => TextStyle(
        fontFamily: _kMono,
        fontSize: 10.5,
        fontWeight: FontWeight.w500,
        color: tooltipText,
      );
}

// ── Formatting ──────────────────────────────────────────────────────────────

String _fmt(double v) {
  final a = v.abs();
  String s;
  if (a >= 1e6) {
    s = '${(v / 1e6).toStringAsFixed(1)}M';
  } else if (a >= 1000) {
    s = '${(v / 1000).toStringAsFixed(1)}k';
  } else if (v == v.truncateToDouble()) {
    s = v.toInt().toString();
  } else {
    s = v.toStringAsFixed(1);
  }
  return s.replaceAll('.0k', 'k').replaceAll('.0M', 'M');
}

// ── Data models ─────────────────────────────────────────────────────────────

class _ChartData {
  final String type;
  final String title;
  final double? rangeMin;
  final double? rangeMax;
  final List<_Series> series;
  final List<String> labels;
  final List<String> xLabels;
  final List<String> yLabels;
  final List<List<double>> matrix;
  final List<_GanttItem> ganttItems;
  final double gaugeValue;
  final double gaugeMax;
  final String gaugeLabel;
  final List<_Node> nodes;
  final List<_Edge> edges;

  _ChartData({
    required this.type,
    this.title = '',
    this.rangeMin,
    this.rangeMax,
    this.series = const [],
    this.labels = const [],
    this.xLabels = const [],
    this.yLabels = const [],
    this.matrix = const [],
    this.ganttItems = const [],
    this.gaugeValue = 0,
    this.gaugeMax = 100,
    this.gaugeLabel = '',
    this.nodes = const [],
    this.edges = const [],
  });
}

class _Series {
  final String name;
  final List<double> values;
  final Color color;

  _Series({required this.name, required this.values, required this.color});
}

class _GanttItem {
  final String label;
  final double start;
  final double end;
  final Color color;

  _GanttItem({required this.label, required this.start, required this.end, required this.color});
}

class _Node {
  final String id;
  final String label;
  _Node({required this.id, required this.label});
}

class _Edge {
  final String from;
  final String to;
  _Edge({required this.from, required this.to});
}

// ── Helper functions ────────────────────────────────────────────────────────

List<double>? _parseRange(String value) {
  final s = value.trim();
  final dashIdx = s.indexOf(RegExp(r'[-–—]'), s.startsWith('-') ? 1 : 0);
  if (dashIdx == -1) return null;
  final minStr = s.substring(0, dashIdx).trim();
  final maxStr = s.substring(dashIdx + 1).trim();
  final minVal = double.tryParse(minStr);
  final maxVal = double.tryParse(maxStr);
  if (minVal != null && maxVal != null) return [minVal, maxVal];
  return null;
}

List<String> _splitLabels(String value) {
  final result = <String>[];
  final buffer = StringBuffer();
  bool inQuotes = false;
  for (int i = 0; i < value.length; i++) {
    final char = value[i];
    if (char == '"' || char == "'") {
      inQuotes = !inQuotes;
    } else if (char == ',' && !inQuotes) {
      final trimmed = buffer.toString().trim();
      if (trimmed.isNotEmpty) result.add(trimmed);
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  final trimmed = buffer.toString().trim();
  if (trimmed.isNotEmpty) result.add(trimmed);
  return result;
}

Color _paletteColor(int i) => _ChartTheme._lightPalette[i % _ChartTheme._lightPalette.length];

// ── Parser (format contract with the prompts — unchanged) ──────────────────

_ChartData _parseChartBlock(String raw) {
  final trimmed = raw.trim();

  if (trimmed.startsWith('{')) {
    try {
      final json = jsonDecode(trimmed);
      final type = (json['type']?.toString().toLowerCase() ?? 'bar');
      final title = json['title']?.toString() ?? '';
      final List items = (json['data'] as List?) ?? [];
      if (items.isNotEmpty) {
        final labels = items.map((e) => (e as Map)['label']?.toString() ?? '').toList();
        final values = items.map((e) {
          final v = e['value'];
          if (v is num) return v.toDouble();
          if (v is String) return double.tryParse(v) ?? 0.0;
          return 0.0;
        }).toList();
        return _ChartData(
          type: type,
          title: title,
          labels: labels,
          series: [_Series(name: 'Data', values: values, color: _paletteColor(0))],
        );
      }
    } catch (_) {}
  }

  final lines = trimmed.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  String type = 'bar';
  String title = '';
  double? rangeMin;
  double? rangeMax;
  List<String> labels = [];
  List<_Series> series = [];
  List<String> xLabels = [];
  List<String> yLabels = [];
  List<List<double>> matrix = [];
  List<_GanttItem> ganttItems = [];
  double gaugeValue = 0;
  double gaugeMax = 100;
  String gaugeLabel = '';
  List<_Node> nodes = [];
  List<_Edge> edges = [];

  final shorthandEntries = <String, double>{};
  final shorthandPairs = <String, (double, double)>{};
  int seriesColorIndex = 0;

  for (final line in lines) {
    final colonIdx = line.indexOf(':');
    if (colonIdx < 0) continue;
    final key = line.substring(0, colonIdx).trim().toLowerCase();
    final value = line.substring(colonIdx + 1).trim();

    if (key == 'type') {
      type = value.toLowerCase().replaceAll(' ', '').replaceAll('-', '').replaceAll('_', '');
    } else if (key == 'title') {
      title = value;
    } else if (key == 'range') {
      final rangeParts = _parseRange(value);
      if (rangeParts != null) {
        rangeMin = rangeParts[0];
        rangeMax = rangeParts[1];
      }
    } else if (key == 'labels') {
      labels = _splitLabels(value);
    } else if (key == 'xlabels') {
      xLabels = value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    } else if (key == 'ylabels') {
      yLabels = value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    } else if (key == 'row') {
      matrix.add(value.split(',').map((s) => double.tryParse(s.trim()) ?? 0).toList());
    } else if (key == 'series') {
      final eqIdx = value.indexOf('=');
      if (eqIdx > 0) {
        final name = value.substring(0, eqIdx).trim();
        final vals = value.substring(eqIdx + 1).split(',').map((s) => double.tryParse(s.trim()) ?? 0).toList();
        series.add(_Series(name: name, values: vals, color: _paletteColor(seriesColorIndex++)));
      }
    } else if (key == 'gantt' || key == 'task') {
      final eqIdx = value.indexOf('=');
      if (eqIdx > 0) {
        final label = value.substring(0, eqIdx).trim();
        final vals = value.substring(eqIdx + 1).split(',').map((s) => double.tryParse(s.trim()) ?? 0).toList();
        if (vals.length >= 2) {
          ganttItems.add(_GanttItem(label: label, start: vals[0], end: vals[1], color: _paletteColor(ganttItems.length)));
        }
      }
    } else if (key == 'value' && type.contains('gauge')) {
      gaugeValue = double.tryParse(value) ?? 0;
    } else if (key == 'max' && type.contains('gauge')) {
      gaugeMax = double.tryParse(value) ?? 100;
    } else if (key == 'label' && type.contains('gauge')) {
      gaugeLabel = value;
    } else if (key == 'node') {
      final eqIdx = value.indexOf('=');
      if (eqIdx > 0) {
        nodes.add(_Node(id: value.substring(0, eqIdx).trim(), label: value.substring(eqIdx + 1).trim()));
      } else {
        nodes.add(_Node(id: value, label: value));
      }
    } else if (key == 'edge' || key == 'link') {
      final arrowIdx = value.indexOf('->');
      if (arrowIdx > 0) {
        edges.add(_Edge(from: value.substring(0, arrowIdx).trim(), to: value.substring(arrowIdx + 2).trim()));
      }
    } else if (!['type', 'title', 'range', 'labels', 'series', 'row', 'xlabels', 'ylabels', 'gantt', 'task', 'value', 'max', 'label', 'node', 'edge', 'link'].contains(key)) {
      final parts = value.split(',').map((s) => s.trim()).toList();
      if (parts.length == 1) {
        final numVal = double.tryParse(parts[0]);
        if (numVal != null) {
          final originalKey = line.substring(0, colonIdx).trim();
          shorthandEntries[originalKey] = numVal;
        }
      } else if (parts.length == 2) {
        final xVal = double.tryParse(parts[0]);
        final yVal = double.tryParse(parts[1]);
        if (xVal != null && yVal != null) {
          final originalKey = line.substring(0, colonIdx).trim();
          shorthandPairs[originalKey] = (xVal, yVal);
        }
      }
    }
  }

  if (series.isEmpty && ganttItems.isEmpty) {
    if (shorthandEntries.isNotEmpty && shorthandPairs.isEmpty) {
      labels = shorthandEntries.keys.toList();
      series = [
        _Series(name: 'Data', values: shorthandEntries.values.toList(), color: _paletteColor(0)),
      ];
    } else if (shorthandPairs.isNotEmpty) {
      if (type.contains('scatter') || type.contains('bubble')) {
        labels = shorthandPairs.keys.toList();
        series = [
          _Series(name: 'X', values: shorthandPairs.values.map((p) => p.$1).toList(), color: _paletteColor(0)),
          _Series(name: 'Y', values: shorthandPairs.values.map((p) => p.$2).toList(), color: _paletteColor(1)),
        ];
      } else if (type.contains('cartesian') || type.contains('geometry')) {
        final flatValues = <double>[];
        for (final pair in shorthandPairs.values) {
          flatValues.add(pair.$1);
          flatValues.add(pair.$2);
        }
        series = [_Series(name: 'Data', values: flatValues, color: _paletteColor(0))];
      } else {
        labels = shorthandPairs.keys.toList();
        series = [
          _Series(name: 'Data', values: shorthandPairs.values.map((p) => p.$2).toList(), color: _paletteColor(0)),
        ];
      }
    }
  }

  return _ChartData(
    type: type,
    title: title,
    rangeMin: rangeMin,
    rangeMax: rangeMax,
    series: series,
    labels: labels,
    xLabels: xLabels,
    yLabels: yLabels,
    matrix: matrix,
    ganttItems: ganttItems,
    gaugeValue: gaugeValue,
    gaugeMax: gaugeMax,
    gaugeLabel: gaugeLabel,
    nodes: nodes,
    edges: edges,
  );
}

// ── Main widget ─────────────────────────────────────────────────────────────

class NexonChartWidget extends StatelessWidget {
  final String chartBlock;
  const NexonChartWidget({super.key, required this.chartBlock});

  @override
  Widget build(BuildContext context) {
    final t = _ChartTheme.of(context);
    try {
      final data = _parseChartBlock(chartBlock);
      if (data.series.isEmpty &&
          data.ganttItems.isEmpty &&
          data.matrix.isEmpty &&
          data.nodes.isEmpty &&
          !data.type.contains('gauge')) {
        return Container(
          height: 80,
          alignment: Alignment.center,
          child: Text(
            'Chart data is empty',
            style: TextStyle(fontSize: 13, color: t.secondary),
          ),
        );
      }

      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => _FullScreenChartViewer(chartBlock: chartBlock)),
          );
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: t.grid),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(t, data),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: SizedBox(
                  height: 260,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final pointCount = math.max(
                        data.labels.length,
                        data.series.isNotEmpty ? data.series.first.values.length : 0,
                      );
                      final minWidth = pointCount * 56.0;
                      final avail = constraints.maxWidth.isFinite ? constraints.maxWidth : minWidth;
                      final width = math.max(avail, minWidth);
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: width,
                          height: 260,
                          child: _buildChart(data, t),
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (_hasRuler(data.type))
                Padding(
                  padding: const EdgeInsets.fromLTRB(48, 2, 12, 0),
                  child: SizedBox(
                    height: 7,
                    child: CustomPaint(painter: _RulerPainter(t: t, count: _rulerCount(data))),
                  ),
                ),
              _buildFooter(t, data),
            ],
          ),
        ),
      );
    } catch (e) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: t.errorBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: t.errorBorder),
        ),
        child: Text(
          'Chart could not be rendered — $e. A chart block needs a type: line plus data lines (labels: / series: or row:). Fix the block and resend.',
          style: TextStyle(fontFamily: _kMono, fontSize: 10, color: t.errorText),
        ),
      );
    }
  }

  Widget _buildHeader(_ChartTheme t, _ChartData data) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_eyebrowText(data), style: t.eyebrow()),
          if (data.title.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(data.title, style: t.title()),
          ],
          const SizedBox(height: 8),
          SizedBox(
            height: 3,
            child: Stack(
              children: [
                Positioned(left: 0, right: 0, top: 1, child: Container(height: 1, color: t.grid)),
                Positioned(left: 0, top: 0, child: Container(width: 16, height: 3, color: t.palette[0])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _eyebrowText(_ChartData d) {
    final type = d.type.toUpperCase();
    if (d.matrix.isNotEmpty) {
      return '$type · ${d.matrix.length * d.matrix.first.length} CELLS';
    }
    if (d.ganttItems.isNotEmpty) return '$type · ${d.ganttItems.length} TASKS';
    if (d.nodes.isNotEmpty) return '$type · ${d.nodes.length} NODES';
    if (d.type.contains('gauge')) {
      final pct = d.gaugeMax > 0 ? (d.gaugeValue / d.gaugeMax * 100).clamp(0, 100) : 0;
      return '$type · ${pct.toStringAsFixed(0)}%';
    }
    final n = math.max(d.labels.length, d.series.isNotEmpty ? d.series.first.values.length : 0);
    final noun = (d.type.contains('pie') || d.type.contains('donut')) ? 'SLICES' : 'PTS';
    return '$type · $n $noun';
  }

  Widget _buildFooter(_ChartTheme t, _ChartData data) {
    final chips = <Widget>[];
    final isPie = data.type.contains('pie') || data.type.contains('donut');
    if (isPie && data.series.isNotEmpty) {
      final vals = data.series.first.values;
      final total = vals.fold<double>(0, (s, v) => s + v);
      for (int i = 0; i < vals.length; i++) {
        final label = i < data.labels.length ? data.labels[i] : 'Item ${i + 1}';
        final pct = total > 0 ? (vals[i] / total * 100).toStringAsFixed(0) : '0';
        chips.add(_chip(t, t.series(i), '$label $pct%'));
      }
    } else if (data.series.length > 1) {
      for (int i = 0; i < data.series.length; i++) {
        chips.add(_chip(t, t.series(i), data.series[i].name));
      }
    } else if (data.series.length == 1 &&
        data.series.first.name.isNotEmpty &&
        data.series.first.name != 'Data') {
      chips.add(_chip(t, t.series(0), data.series.first.name));
    }
    final stats = _statsFor(data);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Wrap(
        spacing: 14,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ...chips,
          ...stats.map((s) => Text(s, style: t.stat())),
        ],
      ),
    );
  }

  Widget _chip(_ChartTheme t, Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 5),
        Text(label, style: t.legend()),
      ],
    );
  }

  static List<String> _statsFor(_ChartData d) {
    final out = <String>[];
    final t = d.type;
    double sumOf(List<double> v) => v.fold(0, (a, b) => a + b);

    if (d.matrix.isNotEmpty) {
      final flat = d.matrix.expand((r) => r).toList();
      if (flat.isEmpty) return out;
      final max = flat.reduce(math.max);
      final mean = sumOf(flat) / flat.length;
      String at = '';
      outer:
      for (int r = 0; r < d.matrix.length; r++) {
        for (int c = 0; c < d.matrix[r].length; c++) {
          if (d.matrix[r][c] == max) {
            final xl = c < d.xLabels.length ? d.xLabels[c] : '${c + 1}';
            final yl = r < d.yLabels.length ? d.yLabels[r] : '${r + 1}';
            at = ' @ $yl/$xl';
            break outer;
          }
        }
      }
      out.add('▲ ${_fmt(max)}$at');
      out.add('x̄ ${_fmt(mean)}');
      return out;
    }
    if (d.ganttItems.isNotEmpty) {
      final maxEnd = d.ganttItems.map((g) => g.end).reduce(math.max);
      var longest = d.ganttItems.first;
      for (final g in d.ganttItems) {
        if (g.end - g.start > longest.end - longest.start) longest = g;
      }
      out.add('SPAN 0–${_fmt(maxEnd)}');
      out.add('LONGEST ${longest.label} (${_fmt(longest.end - longest.start)})');
      return out;
    }
    if (d.nodes.isNotEmpty) {
      out.add('${d.nodes.length} NODES');
      out.add('${d.edges.length} LINKS');
      return out;
    }
    if (t.contains('gauge')) {
      final pct = d.gaugeMax > 0 ? (d.gaugeValue / d.gaugeMax * 100) : 0;
      out.add('${pct.toStringAsFixed(0)}% OF ${_fmt(d.gaugeMax)}');
      return out;
    }
    if (t.contains('scatter') || t.contains('bubble') || t.contains('cartesian') || t.contains('geometry') || t.contains('plane')) {
      final n = d.labels.isNotEmpty ? d.labels.length : (d.series.isNotEmpty ? d.series.first.values.length : 0);
      out.add('$n PTS');
      final ys = d.series.expand((s) => s.values).toList();
      if (ys.isNotEmpty) out.add('▲ ${_fmt(ys.reduce(math.max))}');
      return out;
    }
    if (t.contains('radar') || t.contains('spider')) {
      out.add('${d.labels.length} AXES');
      final vals = d.series.expand((s) => s.values).toList();
      if (vals.isNotEmpty) out.add('▲ ${_fmt(vals.reduce(math.max))}');
      return out;
    }
    final vals = d.series.expand((s) => s.values).toList();
    if (vals.isEmpty) return out;
    final max = vals.reduce(math.max);
    final min = vals.reduce(math.min);
    final sum = sumOf(vals);
    if (t.contains('pie') || t.contains('donut')) {
      final idx = vals.indexOf(max);
      final label = idx < d.labels.length ? d.labels[idx] : '#${idx + 1}';
      final pct = sum > 0 ? (max / sum * 100).toStringAsFixed(0) : '0';
      out.add('Σ ${_fmt(sum)}');
      out.add('▲ $label $pct%');
      return out;
    }
    out.add('Σ ${_fmt(sum)}');
    out.add('x̄ ${_fmt(sum / vals.length)}');
    out.add('▲ ${_fmt(max)}');
    out.add('▼ ${_fmt(min)}');
    return out;
  }

  static bool _hasRuler(String type) =>
      type.contains('bar') ||
      type.contains('stacked') ||
      type.contains('grouped') ||
      type.contains('line') ||
      type.contains('curve') ||
      type.contains('area') ||
      type.contains('histogram') ||
      type.contains('scatter') ||
      type.contains('bubble');

  static int _rulerCount(_ChartData d) => math.max(
        2,
        math.max(d.labels.length, d.series.isNotEmpty ? d.series.first.values.length : 0),
      );

  static Widget _buildChart(_ChartData data, _ChartTheme t) {
    switch (data.type) {
      case 'bar':
      case 'bargrouped':
      case 'grouped':
        return _buildBarChart(data, t, grouped: data.series.length > 1);
      case 'barstacked':
      case 'stacked':
        return _buildStackedBarChart(data, t);
      case 'line':
      case 'linesingle':
      case 'linemulti':
      case 'curve':
      case 'curvegraph':
        return _buildLineChart(data, t);
      case 'area':
      case 'areachart':
        return _buildAreaChart(data, t);
      case 'pie':
        return _buildPieChart(data, t, donut: false);
      case 'donut':
        return _buildPieChart(data, t, donut: true);
      case 'scatter':
      case 'scatterplot':
        return _buildScatterChart(data, t);
      case 'radar':
      case 'spider':
        return _buildRadarChart(data, t);
      case 'histogram':
        return _buildHistogramChart(data, t);
      case 'heatmap':
        return _buildHeatmap(data, t);
      case 'bubble':
      case 'bubblechart':
        return _buildBubbleChart(data, t);
      case 'gantt':
      case 'timeline':
        return _buildGanttChart(data, t);
      case 'gauge':
      case 'progress':
        return _buildGaugeChart(data, t);
      case 'geometry':
      case 'geometrygraph':
      case 'cartesian':
      case 'cartesiangraph':
      case 'plane':
        return _buildCartesianChart(data, t);
      case 'mindmap':
      case 'tree':
        return _buildMindMapChart(data, t);
      default:
        return _buildBarChart(data, t, grouped: data.series.length > 1);
    }
  }

  // ── Bar (single & grouped) ──

  static Widget _buildBarChart(_ChartData data, _ChartTheme t, {bool grouped = false}) {
    final allVals = data.series.expand((s) => s.values).toList();
    if (allVals.isEmpty) return const SizedBox.shrink();
    final maxVal = allVals.reduce(math.max);
    final minVal = data.rangeMin ?? 0;
    final niceMax = data.rangeMax ?? (maxVal * 1.15 == 0 ? 10 : maxVal * 1.15);
    final labelCount = data.labels.length;
    final seriesCount = data.series.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          minY: minVal,
          maxY: niceMax,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipRoundedRadius: 6,
              tooltipBorder: BorderSide(color: t.grid),
              getTooltipColor: (group) => t.tooltipBg,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final label = groupIndex < labelCount ? data.labels[groupIndex] : '';
                final seriesName = rodIndex < seriesCount ? data.series[rodIndex].name : '';
                return BarTooltipItem(
                  seriesCount > 1 ? '$label\n$seriesName: ${_fmt(rod.toY)}' : '$label\n${_fmt(rod.toY)}',
                  t.tooltipStyle(),
                );
              },
            ),
          ),
          titlesData: _buildTitlesData(data, niceMax, minVal, t),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: _niceInterval(niceMax - minVal),
            getDrawingHorizontalLine: (v) => FlLine(color: t.grid, strokeWidth: 1, dashArray: [3, 3]),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(
            labelCount > 0 ? labelCount : (data.series.isNotEmpty ? data.series.first.values.length : 0),
            (i) {
              final rodWidth = grouped && seriesCount > 1
                  ? (labelCount > 6 ? 8.0 : 14.0)
                  : (labelCount > 8 ? 14.0 : 22.0);
              return BarChartGroupData(
                x: i,
                barRods: data.series.asMap().entries.map((entry) {
                  final val = i < entry.value.values.length ? entry.value.values[i] : 0.0;
                  return BarChartRodData(
                    toY: val,
                    color: t.series(entry.key),
                    width: rodWidth,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  );
                }).toList(),
              );
            },
          ),
        ),
        duration: t.anim,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  // ── Stacked bar ──

  static Widget _buildStackedBarChart(_ChartData data, _ChartTheme t) {
    final labelCount = data.labels.length;
    final seriesCount = data.series.length;
    double maxStacked = 0;
    for (int i = 0; i < (labelCount > 0 ? labelCount : (data.series.isNotEmpty ? data.series.first.values.length : 0)); i++) {
      double sum = 0;
      for (final s in data.series) {
        sum += i < s.values.length ? s.values[i] : 0;
      }
      if (sum > maxStacked) maxStacked = sum;
    }
    final minVal = data.rangeMin ?? 0;
    final niceMax = data.rangeMax ?? (maxStacked * 1.15 == 0 ? 10 : maxStacked * 1.15);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          minY: minVal,
          maxY: niceMax,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipRoundedRadius: 6,
              tooltipBorder: BorderSide(color: t.grid),
              getTooltipColor: (group) => t.tooltipBg,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final label = groupIndex < labelCount ? data.labels[groupIndex] : '';
                return BarTooltipItem('$label\nΣ ${_fmt(rod.toY)}', t.tooltipStyle());
              },
            ),
          ),
          titlesData: _buildTitlesData(data, niceMax, minVal, t),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: _niceInterval(niceMax - minVal),
            getDrawingHorizontalLine: (v) => FlLine(color: t.grid, strokeWidth: 1, dashArray: [3, 3]),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(
            labelCount > 0 ? labelCount : (data.series.isNotEmpty ? data.series.first.values.length : 0),
            (i) {
              final rodStackItems = <BarChartRodStackItem>[];
              double cumulative = 0;
              for (int si = 0; si < seriesCount; si++) {
                final val = i < data.series[si].values.length ? data.series[si].values[i] : 0.0;
                rodStackItems.add(BarChartRodStackItem(cumulative, cumulative + val, t.series(si)));
                cumulative += val;
              }
              return BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: cumulative,
                    rodStackItems: rodStackItems,
                    width: labelCount > 8 ? 14.0 : 22.0,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                    borderSide: BorderSide(color: t.surface, width: 1),
                  ),
                ],
              );
            },
          ),
        ),
        duration: t.anim,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  // ── Line ─

  static Widget _buildLineChart(_ChartData data, _ChartTheme t) {
    final allVals = data.series.expand((s) => s.values).toList();
    if (allVals.isEmpty) return const SizedBox.shrink();
    final maxVal = allVals.reduce(math.max);
    final computedMin = allVals.reduce(math.min);
    final minVal = data.rangeMin ?? (computedMin < 0 ? computedMin * 1.1 : 0);
    final niceMax = data.rangeMax ?? (maxVal * 1.15 == 0 ? 10 : maxVal * 1.15);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
      child: LineChart(
        LineChartData(
          minY: minVal,
          maxY: niceMax,
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              tooltipRoundedRadius: 6,
              tooltipBorder: BorderSide(color: t.grid),
              getTooltipColor: (spot) => t.tooltipBg,
              getTooltipItems: (spots) => spots.map((spot) {
                final sIdx = spot.barIndex;
                final name = sIdx < data.series.length ? data.series[sIdx].name : '';
                final label = spot.spotIndex < data.labels.length ? data.labels[spot.spotIndex] : '';
                return LineTooltipItem(
                  data.series.length > 1 ? '$label\n$name: ${_fmt(spot.y)}' : '$label\n${_fmt(spot.y)}',
                  t.tooltipStyle(),
                );
              }).toList(),
            ),
          ),
          titlesData: _buildTitlesData(data, niceMax, minVal, t),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: _niceInterval(niceMax - minVal),
            getDrawingHorizontalLine: (v) => FlLine(color: t.grid, strokeWidth: 1, dashArray: [3, 3]),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: data.series.asMap().entries.map((entry) {
            final s = entry.value;
            final c = t.series(entry.key);
            return LineChartBarData(
              spots: s.values.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
              isCurved: true,
              curveSmoothness: 0.3,
              color: c,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
                  radius: 2.5,
                  color: t.surface,
                  strokeWidth: 1.5,
                  strokeColor: c,
                ),
              ),
              belowBarData: BarAreaData(show: false),
            );
          }).toList(),
        ),
        duration: t.anim,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  // ── Area ─

  static Widget _buildAreaChart(_ChartData data, _ChartTheme t) {
    final allVals = data.series.expand((s) => s.values).toList();
    if (allVals.isEmpty) return const SizedBox.shrink();
    final maxVal = allVals.reduce(math.max);
    final computedMin = allVals.reduce(math.min);
    final minVal = data.rangeMin ?? (computedMin < 0 ? computedMin * 1.1 : 0);
    final niceMax = data.rangeMax ?? (maxVal * 1.15 == 0 ? 10 : maxVal * 1.15);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
      child: LineChart(
        LineChartData(
          minY: minVal,
          maxY: niceMax,
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              tooltipRoundedRadius: 6,
              tooltipBorder: BorderSide(color: t.grid),
              getTooltipColor: (spot) => t.tooltipBg,
              getTooltipItems: (spots) => spots.map((spot) {
                final label = spot.spotIndex < data.labels.length ? data.labels[spot.spotIndex] : '';
                return LineTooltipItem('$label\n${_fmt(spot.y)}', t.tooltipStyle());
              }).toList(),
            ),
          ),
          titlesData: _buildTitlesData(data, niceMax, minVal, t),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: _niceInterval(niceMax - minVal),
            getDrawingHorizontalLine: (v) => FlLine(color: t.grid, strokeWidth: 1, dashArray: [3, 3]),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: data.series.asMap().entries.map((entry) {
            final s = entry.value;
            final c = t.series(entry.key);
            return LineChartBarData(
              spots: s.values.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
              isCurved: true,
              curveSmoothness: 0.3,
              color: c,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [c.withValues(alpha: 0.22), c.withValues(alpha: 0.02)],
                ),
              ),
            );
          }).toList(),
        ),
        duration: t.anim,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  // ── Pie / donut ──

  static Widget _buildPieChart(_ChartData data, _ChartTheme t, {required bool donut}) {
    if (data.series.isEmpty || data.series.first.values.isEmpty) return const SizedBox.shrink();
    final values = data.series.first.values;
    final total = values.fold<double>(0, (s, v) => s + v);

    final pie = PieChart(
      PieChartData(
        sectionsSpace: 0,
        centerSpaceRadius: donut ? 46 : 0,
        centerSpaceColor: Colors.transparent,
        startDegreeOffset: -90,
        pieTouchData: PieTouchData(enabled: true),
        sections: values.asMap().entries.map((e) {
          final pctVal = total > 0 ? (e.value / total * 100) : 0.0;
          final c = t.series(e.key);
          final showTxt = pctVal > 7.0;
          return PieChartSectionData(
            color: c,
            value: e.value,
            title: showTxt ? '${pctVal.toStringAsFixed(0)}%' : '',
            showTitle: showTxt,
            radius: donut ? 40 : 84,
            borderColor: t.surface,
            borderWidth: 2,
            titleStyle: donut
                ? TextStyle(fontFamily: _kMono, fontSize: 9.5, fontWeight: FontWeight.w600, color: c)
                : TextStyle(fontFamily: _kMono, fontSize: 10, fontWeight: FontWeight.w600, color: t.textOn(c)),
            titlePositionPercentageOffset: donut ? 1.45 : 0.62,
          );
        }).toList(),
      ),
      duration: t.anim,
      curve: Curves.easeOutCubic,
    );

    if (!donut) return pie;
    return Stack(
      alignment: Alignment.center,
      children: [
        pie,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_fmt(total), style: TextStyle(fontFamily: _kMono, fontSize: 16, fontWeight: FontWeight.w600, color: t.ink)),
            const SizedBox(height: 2),
            Text('TOTAL', style: TextStyle(fontFamily: _kMono, fontSize: 7.5, letterSpacing: 1.2, color: t.muted)),
          ],
        ),
      ],
    );
  }

  // ── Scatter ─

  static Widget _buildScatterChart(_ChartData data, _ChartTheme t) {
    if (data.series.isEmpty) return const SizedBox.shrink();

    final hasExplicitXY = data.series.length == 2 &&
        data.series[0].name == 'X' &&
        data.series[1].name == 'Y' &&
        data.series[0].values.length == data.series[1].values.length;

    final spots = <ScatterSpot>[];

    if (hasExplicitXY) {
      final xSeries = data.series[0];
      final ySeries = data.series[1];
      for (int i = 0; i < xSeries.values.length; i++) {
        final c = t.series(i);
        spots.add(ScatterSpot(
          xSeries.values[i],
          ySeries.values[i],
          dotPainter: FlDotCirclePainter(radius: 4, color: t.surface, strokeWidth: 2, strokeColor: c),
        ));
      }
    } else {
      for (final entry in data.series.asMap().entries) {
        final c = t.series(entry.key);
        spots.addAll(entry.value.values.asMap().entries.map((e) => ScatterSpot(
              e.key.toDouble(),
              e.value,
              dotPainter: FlDotCirclePainter(radius: 4, color: t.surface, strokeWidth: 2, strokeColor: c),
            )));
      }
    }

    if (spots.isEmpty) return const SizedBox.shrink();

    final xValues = spots.map((s) => s.x).toList();
    final yValues = spots.map((s) => s.y).toList();
    final minX = (data.rangeMin ?? xValues.reduce(math.min)).toDouble();
    final maxX = (data.rangeMax ?? xValues.reduce(math.max)).toDouble();
    final minY = yValues.reduce(math.min).toDouble();
    final maxY = yValues.reduce(math.max).toDouble();
    final niceMaxX = maxX * 1.15 == 0 ? 10.0 : maxX * 1.15;
    final niceMaxY = maxY * 1.15 == 0 ? 10.0 : maxY * 1.15;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
      child: ScatterChart(
        ScatterChartData(
          minY: minY,
          maxY: niceMaxY,
          minX: minX,
          maxX: niceMaxX,
          scatterTouchData: ScatterTouchData(
            enabled: true,
            touchTooltipData: ScatterTouchTooltipData(
              tooltipRoundedRadius: 6,
              getTooltipColor: (spot) => t.tooltipBg,
              getTooltipItems: (spot) {
                final spotIndex = spots.indexWhere((s) => s.x == spot.x && s.y == spot.y);
                final label = spotIndex >= 0 && spotIndex < data.labels.length
                    ? data.labels[spotIndex]
                    : 'Point ${spotIndex >= 0 ? spotIndex + 1 : '?'}';
                return ScatterTooltipItem(
                  '$label\n(${spot.x.toStringAsFixed(1)}, ${spot.y.toStringAsFixed(1)})',
                  textStyle: t.tooltipStyle(),
                );
              },
            ),
          ),
          titlesData: _buildTitlesData(data, niceMaxY, minY, t),
          gridData: FlGridData(
            show: true,
            horizontalInterval: _niceInterval(niceMaxY - minY),
            getDrawingHorizontalLine: (v) => FlLine(color: t.grid, strokeWidth: 1, dashArray: [3, 3]),
            getDrawingVerticalLine: (v) => FlLine(color: t.grid.withValues(alpha: 0.5), strokeWidth: 1, dashArray: [3, 3]),
          ),
          borderData: FlBorderData(show: false),
          scatterSpots: spots,
        ),
      ),
    );
  }

  // ── Radar / spider ──

  static Widget _buildRadarChart(_ChartData data, _ChartTheme t) {
    if (data.series.isEmpty) return const SizedBox.shrink();

    return RadarChart(
      RadarChartData(
        radarShape: RadarShape.polygon,
        tickCount: 4,
        ticksTextStyle: t.tick(),
        tickBorderData: BorderSide(color: t.grid.withValues(alpha: 0.6)),
        gridBorderData: BorderSide(color: t.grid.withValues(alpha: 0.6)),
        radarBorderData: BorderSide(color: t.grid.withValues(alpha: 0.6)),
        titleTextStyle: t.cat(),
        getTitle: (index, angle) {
          if (index < data.labels.length) return RadarChartTitle(text: data.labels[index]);
          return const RadarChartTitle(text: '');
        },
        dataSets: data.series.asMap().entries.map((entry) {
          final c = t.series(entry.key);
          return RadarDataSet(
            dataEntries: entry.value.values.map((v) => RadarEntry(value: v)).toList(),
            borderColor: c,
            fillColor: c.withValues(alpha: 0.16),
            borderWidth: 2,
            entryRadius: 2.5,
          );
        }).toList(),
        titlePositionPercentageOffset: 0.15,
      ),
      duration: t.anim,
      curve: Curves.easeOutCubic,
    );
  }

  // ── Histogram ──

  static Widget _buildHistogramChart(_ChartData data, _ChartTheme t) {
    final allVals = data.series.expand((s) => s.values).toList();
    if (allVals.isEmpty) return const SizedBox.shrink();
    final maxVal = allVals.reduce(math.max);
    final minVal = data.rangeMin ?? 0;
    final niceMax = data.rangeMax ?? (maxVal * 1.15 == 0 ? 10 : maxVal * 1.15);
    final values = data.series.first.values;
    final c = t.series(0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.center,
          groupsSpace: 0,
          minY: minVal,
          maxY: niceMax,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipRoundedRadius: 6,
              tooltipBorder: BorderSide(color: t.grid),
              getTooltipColor: (group) => t.tooltipBg,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final label = groupIndex < data.labels.length ? data.labels[groupIndex] : '$groupIndex';
                return BarTooltipItem('$label\n${_fmt(rod.toY)}', t.tooltipStyle());
              },
            ),
          ),
          titlesData: _buildTitlesData(data, niceMax, minVal, t),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: _niceInterval(niceMax - minVal),
            getDrawingHorizontalLine: (v) => FlLine(color: t.grid, strokeWidth: 1, dashArray: [3, 3]),
          ),
          borderData: FlBorderData(show: false),
          barGroups: values.asMap().entries.map((e) {
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: e.value,
                  color: c.withValues(alpha: 0.85),
                  width: values.length > 15 ? 10 : 20,
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: t.surface, width: 1),
                ),
              ],
            );
          }).toList(),
        ),
        duration: t.anim,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  // ── Heatmap ──

  static Widget _buildHeatmap(_ChartData data, _ChartTheme t) {
    if (data.matrix.isEmpty) return const SizedBox.shrink();
    final allVals = data.matrix.expand((row) => row).toList();
    final maxVal = allVals.isEmpty ? 1 : allVals.reduce(math.max);
    final minVal = allVals.isEmpty ? 0 : allVals.reduce(math.min);
    final range = maxVal - minVal;
    final isDark = t == _ChartTheme.dark;
    final rampFrom = isDark ? const Color(0xFF2A221A) : const Color(0xFFF1E8D9);
    final rampTo = t.series(0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = data.matrix.first.length;
        final rows = data.matrix.length;
        if (cols == 0 || rows == 0) return const SizedBox.shrink();
        final cellW = (constraints.maxWidth - 60) / cols;
        final cellH = math.min(cellW, 240.0 / rows);

        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (data.xLabels.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 50),
                  child: Row(
                    children: data.xLabels.asMap().entries.map((e) => SizedBox(
                          width: cellW,
                          child: Text(e.value, textAlign: TextAlign.center, style: t.tick(), overflow: TextOverflow.ellipsis),
                        )).toList(),
                  ),
                ),
              const SizedBox(height: 4),
              ...data.matrix.asMap().entries.map((rowEntry) {
                return Row(
                  children: [
                    SizedBox(
                      width: 48,
                      child: Text(
                        rowEntry.key < data.yLabels.length ? data.yLabels[rowEntry.key] : '',
                        textAlign: TextAlign.right,
                        style: t.tick(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    ...rowEntry.value.asMap().entries.map((colEntry) {
                      final intensity = range > 0 ? ((colEntry.value - minVal) / range).clamp(0.0, 1.0) : 0.5;
                      final color = Color.lerp(rampFrom, rampTo, intensity)!;
                      return Tooltip(
                        message: colEntry.value.toStringAsFixed(1),
                        child: Container(
                          width: cellW - 2,
                          height: cellH - 2,
                          margin: const EdgeInsets.all(1),
                          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                          child: cellW > 28
                              ? Center(
                                  child: Text(
                                    colEntry.value.toStringAsFixed(0),
                                    style: TextStyle(fontFamily: _kMono, fontSize: 9, fontWeight: FontWeight.w500, color: t.textOn(color)),
                                  ),
                                )
                              : null,
                        ),
                      );
                    }),
                  ],
                );
              }),
            ],
          ),
        );
      },
    );
  }

  // ── Bubble ──

  static Widget _buildBubbleChart(_ChartData data, _ChartTheme t) {
    if (data.series.isEmpty) return const SizedBox.shrink();

    final hasExplicitXY = data.series.length == 2 &&
        data.series[0].name == 'X' &&
        data.series[1].name == 'Y' &&
        data.series[0].values.length == data.series[1].values.length;

    final spots = <ScatterSpot>[];
    double maxVal = 0;

    if (hasExplicitXY) {
      final xSeries = data.series[0];
      final ySeries = data.series[1];
      maxVal = ySeries.values.reduce(math.max);
      for (int i = 0; i < xSeries.values.length; i++) {
        final yVal = ySeries.values[i];
        final r = maxVal > 0 ? (yVal / maxVal * 18).clamp(4.0, 20.0) : 6.0;
        final c = t.series(i);
        spots.add(ScatterSpot(
          xSeries.values[i],
          yVal,
          dotPainter: FlDotCirclePainter(radius: r, color: c.withValues(alpha: 0.45), strokeWidth: 2, strokeColor: c),
        ));
      }
    } else {
      final allVals = data.series.expand((s) => s.values).toList();
      maxVal = allVals.reduce(math.max);
      for (final entry in data.series.asMap().entries) {
        final c = t.series(entry.key);
        spots.addAll(entry.value.values.asMap().entries.map((e) {
          final r = maxVal > 0 ? (e.value / maxVal * 18).clamp(4.0, 20.0) : 6.0;
          return ScatterSpot(
            e.key.toDouble(),
            e.value,
            dotPainter: FlDotCirclePainter(radius: r, color: c.withValues(alpha: 0.45), strokeWidth: 2, strokeColor: c),
          );
        }));
      }
    }

    if (spots.isEmpty) return const SizedBox.shrink();

    final xValues = spots.map((s) => s.x).toList();
    final yValues = spots.map((s) => s.y).toList();
    final minX = (data.rangeMin ?? xValues.reduce(math.min)).toDouble();
    final maxX = (data.rangeMax ?? xValues.reduce(math.max)).toDouble();
    final minY = yValues.reduce(math.min).toDouble();
    final maxY = yValues.reduce(math.max).toDouble();
    final niceMaxX = maxX * 1.15 == 0 ? 10.0 : maxX * 1.15;
    final niceMaxY = maxY * 1.15 == 0 ? 10.0 : maxY * 1.15;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
      child: ScatterChart(
        ScatterChartData(
          minY: minY,
          maxY: niceMaxY,
          minX: minX,
          maxX: niceMaxX,
          scatterTouchData: ScatterTouchData(
            enabled: true,
            touchTooltipData: ScatterTouchTooltipData(
              tooltipRoundedRadius: 6,
              getTooltipColor: (spot) => t.tooltipBg,
              getTooltipItems: (spot) {
                final spotIndex = spots.indexWhere((s) => s.x == spot.x && s.y == spot.y);
                final label = spotIndex >= 0 && spotIndex < data.labels.length
                    ? data.labels[spotIndex]
                    : 'Point ${spotIndex >= 0 ? spotIndex + 1 : '?'}';
                return ScatterTooltipItem(
                  '$label\n(${spot.x.toStringAsFixed(1)}, ${spot.y.toStringAsFixed(1)})',
                  textStyle: t.tooltipStyle(),
                );
              },
            ),
          ),
          titlesData: _buildTitlesData(data, niceMaxY, minY, t),
          gridData: FlGridData(
            show: true,
            horizontalInterval: _niceInterval(niceMaxY - minY),
            getDrawingHorizontalLine: (v) => FlLine(color: t.grid, strokeWidth: 1, dashArray: [3, 3]),
            getDrawingVerticalLine: (v) => FlLine(color: t.grid.withValues(alpha: 0.5), strokeWidth: 1, dashArray: [3, 3]),
          ),
          borderData: FlBorderData(show: false),
          scatterSpots: spots,
        ),
      ),
    );
  }

  // ── Gantt / timeline ──

  static Widget _buildGanttChart(_ChartData data, _ChartTheme t) {
    if (data.ganttItems.isEmpty) return const SizedBox.shrink();
    final maxEnd = data.ganttItems.map((g) => g.end).reduce(math.max);
    final niceMax = data.rangeMax ?? (maxEnd * 1.1 == 0 ? 10 : maxEnd * 1.1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final chartWidth = constraints.maxWidth - 120;
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...data.ganttItems.asMap().entries.map((e) {
                final item = e.value;
                final c = t.series(e.key);
                final leftPct = niceMax > 0 ? item.start / niceMax : 0;
                final widthPct = niceMax > 0 ? (item.end - item.start) / niceMax : 0;
                final barWide = widthPct * chartWidth > 52;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          item.label,
                          style: TextStyle(fontFamily: t.uiFamily, fontSize: 10.5, color: t.ink, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 24,
                          decoration: BoxDecoration(
                            color: t.grid.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: 1.0,
                            child: Padding(
                              padding: EdgeInsets.only(left: leftPct * chartWidth),
                              child: Container(
                                width: widthPct * chartWidth,
                                decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
                                alignment: Alignment.center,
                                child: barWide
                                    ? Text(
                                        '${item.start.toInt()}-${item.end.toInt()}',
                                        style: TextStyle(fontFamily: _kMono, fontSize: 8.5, fontWeight: FontWeight.w600, color: t.textOn(c)),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              Padding(
                padding: const EdgeInsets.only(left: 118, top: 2),
                child: SizedBox(height: 7, child: CustomPaint(painter: _RulerPainter(t: t, count: 5))),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 118),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(5, (i) => Text(_fmt(niceMax * i / 4), style: t.tick())),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Gauge ──

  static Widget _buildGaugeChart(_ChartData data, _ChartTheme t) {
    final pct = data.gaugeMax > 0 ? (data.gaugeValue / data.gaugeMax).clamp(0.0, 1.0) : 0.0;
    final isDark = t == _ChartTheme.dark;
    final gaugeColor = pct < 0.3
        ? (isDark ? const Color(0xFFE07856) : const Color(0xFFB3402E))
        : pct < 0.7
            ? (isDark ? const Color(0xFFE5B95C) : const Color(0xFFC08A2D))
            : (isDark ? const Color(0xFFA3B36B) : const Color(0xFF5F8A4E));

    return Center(
      child: SizedBox(
        width: 190,
        height: 190,
        child: CustomPaint(
          painter: _GaugePainter(value: pct, color: gaugeColor, t: t),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  data.gaugeValue.toStringAsFixed(data.gaugeValue == data.gaugeValue.truncateToDouble() ? 0 : 1),
                  style: TextStyle(fontFamily: _kMono, fontSize: 26, fontWeight: FontWeight.w600, color: t.ink),
                ),
                if (data.gaugeLabel.isNotEmpty) Text(data.gaugeLabel, style: t.cat()),
                Text('/ ${_fmt(data.gaugeMax)}', style: t.tick()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Cartesian plane ──

  static Widget _buildCartesianChart(_ChartData data, _ChartTheme t) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ClipRect(
        child: CustomPaint(
          painter: _CartesianPainter(data: data, t: t),
          size: const Size(double.infinity, double.infinity),
        ),
      ),
    );
  }

  // ── Mind map ──

  static Widget _buildMindMapChart(_ChartData data, _ChartTheme t) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ClipRect(
        child: CustomPaint(
          painter: _MindMapPainter(data, t),
          size: const Size(double.infinity, double.infinity),
        ),
      ),
    );
  }

  // ── Shared axis titles ──

  static FlTitlesData _buildTitlesData(_ChartData data, double maxY, double minY, _ChartTheme t) {
    return FlTitlesData(
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: data.labels.isNotEmpty,
          reservedSize: 26,
          interval: data.labels.length > 10 ? 2 : 1,
          getTitlesWidget: (value, meta) {
            final i = value.toInt();
            if (i < 0 || i >= data.labels.length) return const SizedBox.shrink();
            final label = data.labels[i];
            final maxLen = data.labels.length > 8 ? 6 : 10;
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                label.length > maxLen ? '${label.substring(0, maxLen - 1)}…' : label,
                style: t.cat(),
                textAlign: TextAlign.center,
              ),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          interval: _niceInterval(maxY - minY),
          getTitlesWidget: (value, meta) {
            if (value == meta.max) return const SizedBox.shrink();
            return Text(_fmt(value), style: t.tick());
          },
        ),
      ),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
  }

  static double _niceInterval(double range) {
    if (range <= 0) return 1;
    final rough = range / 5;
    final magnitude = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
    final residual = rough / magnitude;
    if (residual <= 1.5) return magnitude;
    if (residual <= 3) return 2 * magnitude;
    if (residual <= 7) return 5 * magnitude;
    return 10 * magnitude;
  }
}

// ── Baseline ruler painter (signature) ─────────────────────────────────────

class _RulerPainter extends CustomPainter {
  final _ChartTheme t;
  final int count;

  _RulerPainter({required this.t, required this.count});

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = t.baseline
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, 0.75), Offset(size.width, 0.75), line);
    final n = count.clamp(2, 60);
    final tick = Paint()
      ..color = t.baseline.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (int i = 0; i < n; i++) {
      final x = size.width * i / (n - 1);
      final major = i == 0 || i == n - 1;
      canvas.drawLine(Offset(x, 0.75), Offset(x, major ? 6 : 4), tick);
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) => old.count != count;
}

// ── Gauge painter ───────────────────────────────────────────────────────────

class _GaugePainter extends CustomPainter {
  final double value;
  final Color color;
  final _ChartTheme t;

  _GaugePainter({required this.value, required this.color, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 16;
    const startAngle = 2.3;
    const sweepAngle = 4.6;

    final bgPaint = Paint()
      ..color = t.grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle, false, bgPaint);

    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle * value, false, valuePaint);

    final tickPaint = Paint()
      ..color = t.muted
      ..strokeWidth = 1;
    for (int k = 0; k <= 4; k++) {
      final angle = startAngle + sweepAngle * k / 4;
      final inner = Offset(center.dx + math.cos(angle) * (radius + 8), center.dy + math.sin(angle) * (radius + 8));
      final outer = Offset(center.dx + math.cos(angle) * (radius + 12), center.dy + math.sin(angle) * (radius + 12));
      canvas.drawLine(inner, outer, tickPaint);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value || old.color != color;
}

// ── Cartesian / geometry painter ────────────────────────────────────────────

class _CartesianPainter extends CustomPainter {
  final _ChartData data;
  final _ChartTheme t;

  _CartesianPainter({required this.data, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    double minX = data.rangeMin ?? -10.0;
    double maxX = data.rangeMax ?? 10.0;
    double minY = data.rangeMin ?? -10.0;
    double maxY = data.rangeMax ?? 10.0;

    for (final s in data.series) {
      for (int i = 0; i < s.values.length - 1; i += 2) {
        if (s.values[i] < minX) minX = s.values[i];
        if (s.values[i] > maxX) maxX = s.values[i];
        if (s.values[i + 1] < minY) minY = s.values[i + 1];
        if (s.values[i + 1] > maxY) maxY = s.values[i + 1];
      }
    }

    minX -= 1;
    maxX += 1;
    minY -= 1;
    maxY += 1;

    final rangeX = maxX - minX;
    final rangeY = maxY - minY;

    Offset toOffset(double x, double y) {
      return Offset((x - minX) / rangeX * size.width, size.height - ((y - minY) / rangeY * size.height));
    }

    final gridPaint = Paint()
      ..color = t.grid.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = t.baseline.withValues(alpha: 0.8)
      ..strokeWidth = 1.5;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (int i = minX.floor(); i <= maxX.ceil(); i++) {
      final px = toOffset(i.toDouble(), 0).dx;
      canvas.drawLine(Offset(px, 0), Offset(px, size.height), i == 0 ? axisPaint : gridPaint);
      if (i != 0 && i % 2 == 0) {
        textPainter.text = TextSpan(text: '$i', style: t.tick());
        textPainter.layout();
        textPainter.paint(canvas, Offset(px + 2, toOffset(0, 0).dy + 2));
      }
    }
    for (int i = minY.floor(); i <= maxY.ceil(); i++) {
      final py = toOffset(0, i.toDouble()).dy;
      canvas.drawLine(Offset(0, py), Offset(size.width, py), i == 0 ? axisPaint : gridPaint);
      if (i != 0 && i % 2 == 0) {
        textPainter.text = TextSpan(text: '$i', style: t.tick());
        textPainter.layout();
        textPainter.paint(canvas, Offset(toOffset(0, 0).dx + 2, py - 12));
      }
    }

    int sIdx = 0;
    for (final s in data.series) {
      final c = t.series(sIdx++);
      if (s.values.isEmpty) continue;

      final shapePaint = Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round;

      final fillPaint = Paint()
        ..color = c.withValues(alpha: 0.18)
        ..style = PaintingStyle.fill;

      final path = Path();
      final List<Offset> points = [];

      for (int i = 0; i < s.values.length - 1; i += 2) {
        points.add(toOffset(s.values[i], s.values[i + 1]));
      }

      if (points.isEmpty) continue;

      if (points.length == 1) {
        canvas.drawCircle(points.first, 4, shapePaint..style = PaintingStyle.fill);
      } else {
        path.moveTo(points.first.dx, points.first.dy);
        for (int i = 1; i < points.length; i++) {
          path.lineTo(points[i].dx, points[i].dy);
        }
        canvas.drawPath(path, shapePaint);

        if (points.length > 2 && (points.first - points.last).distance < 0.1) {
          canvas.drawPath(path, fillPaint);
        }

        for (final p in points) {
          canvas.drawCircle(p, 3, Paint()..color = t.surface..style = PaintingStyle.fill);
          canvas.drawCircle(p, 3, Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = 1.5);
        }

        if (points.length <= 12) {
          for (int i = 0; i < points.length; i++) {
            textPainter.text = TextSpan(
              text: '${_fmt(s.values[i * 2])},${_fmt(s.values[i * 2 + 1])}',
              style: TextStyle(fontFamily: _kMono, fontSize: 8.5, color: t.muted),
            );
            textPainter.layout();
            textPainter.paint(canvas, points[i] + const Offset(5, -10));
          }
        }
      }

      if (s.name.isNotEmpty && s.name != 'Data') {
        textPainter.text = TextSpan(
          text: s.name,
          style: TextStyle(
            fontFamily: t.uiFamily,
            color: c,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            backgroundColor: t.surface.withValues(alpha: 0.85),
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, points.first + const Offset(5, -15));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CartesianPainter old) => true;
}

// ── Mind map painter ────────────────────────────────────────────────────────

class _MindMapPainter extends CustomPainter {
  final _ChartData data;
  final _ChartTheme t;
  _MindMapPainter(this.data, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.nodes.isEmpty) return;

    final inDegree = <String, int>{};
    final outEdges = <String, List<String>>{};
    for (final n in data.nodes) {
      inDegree[n.id] = 0;
      outEdges[n.id] = [];
    }
    for (final e in data.edges) {
      if (outEdges.containsKey(e.from)) {
        outEdges[e.from]!.add(e.to);
        inDegree[e.to] = (inDegree[e.to] ?? 0) + 1;
      }
    }

    final levels = <String, int>{};
    int maxLevel = 0;
    var queue = <String>[];
    for (final n in data.nodes) {
      if (inDegree[n.id] == 0) {
        levels[n.id] = 0;
        queue.add(n.id);
      }
    }
    if (queue.isEmpty) {
      levels[data.nodes.first.id] = 0;
      queue.add(data.nodes.first.id);
    }

    while (queue.isNotEmpty) {
      final curr = queue.removeAt(0);
      final currLvl = levels[curr]!;
      if (currLvl > maxLevel) maxLevel = currLvl;
      for (final child in (outEdges[curr] ?? <String>[])) {
        if (!levels.containsKey(child)) {
          levels[child] = currLvl + 1;
          queue.add(child);
        }
      }
    }

    for (final n in data.nodes) {
      if (!levels.containsKey(n.id)) levels[n.id] = 0;
    }

    final levelGroups = <int, List<_Node>>{};
    for (final n in data.nodes) {
      levelGroups.putIfAbsent(levels[n.id]!, () => []).add(n);
    }

    final positions = <String, Offset>{};
    const nodeHeight = 34.0;
    const nodeWidth = 92.0;
    final yStep = size.height / (maxLevel + 1);

    levelGroups.forEach((lvl, nodes) {
      final xStep = size.width / (nodes.length + 1);
      for (int i = 0; i < nodes.length; i++) {
        positions[nodes[i].id] = Offset(xStep * (i + 1), (yStep * lvl) + (yStep / 2));
      }
    });

    final edgePaint = Paint()
      ..color = t.muted.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final e in data.edges) {
      final p1 = positions[e.from];
      final p2 = positions[e.to];
      if (p1 != null && p2 != null) {
        final path = Path();
        path.moveTo(p1.dx, p1.dy + nodeHeight / 2);
        path.cubicTo(
          p1.dx, p1.dy + nodeHeight / 2 + 30,
          p2.dx, p2.dy - nodeHeight / 2 - 30,
          p2.dx, p2.dy - nodeHeight / 2,
        );
        canvas.drawPath(path, edgePaint);
      }
    }

    final textPainter = TextPainter(textDirection: TextDirection.ltr, textAlign: TextAlign.center);
    for (final n in data.nodes) {
      final p = positions[n.id]!;
      final isRoot = levels[n.id] == 0;
      final fill = isRoot ? t.series(0) : t.surface;
      final bgPaint = Paint()
        ..color = fill
        ..style = PaintingStyle.fill;
      final borderPaint = Paint()
        ..color = isRoot ? fill : t.muted.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;

      final rect = Rect.fromCenter(center: p, width: nodeWidth, height: nodeHeight);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      canvas.drawRRect(rrect, bgPaint);
      canvas.drawRRect(rrect, borderPaint);

      textPainter.text = TextSpan(
        text: n.label,
        style: TextStyle(
          fontFamily: t.uiFamily,
          color: isRoot ? t.textOn(fill) : t.ink,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
        ),
      );
      textPainter.layout(maxWidth: nodeWidth - 8);
      textPainter.paint(canvas, Offset(p.dx - textPainter.width / 2, p.dy - textPainter.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _MindMapPainter old) => true;
}

// ── Full-screen chart viewer ────────────────────────────────────────────────

class _FullScreenChartViewer extends StatelessWidget {
  final String chartBlock;
  const _FullScreenChartViewer({required this.chartBlock});

  @override
  Widget build(BuildContext context) {
    final t = _ChartTheme.of(context);
    final data = _parseChartBlock(chartBlock);

    return Scaffold(
      backgroundColor: t.surface,
      appBar: AppBar(
        backgroundColor: t.surface,
        foregroundColor: t.ink,
        elevation: 0,
        title: Text(data.title.isEmpty ? 'Chart' : data.title, style: t.title()),
        actions: [
          IconButton(
            icon: Icon(Icons.copy, size: 20, color: t.muted),
            tooltip: 'Copy chart data',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: chartBlock));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Chart data copied')),
              );
            },
          ),
        ],
      ),
      body: InteractiveViewer(
        panEnabled: true,
        scaleEnabled: true,
        minScale: 0.5,
        maxScale: 5.0,
        constrained: false,
        child: Container(
          padding: const EdgeInsets.all(20),
          width: math.max(
            MediaQuery.of(context).size.width,
            math.max(data.labels.length, data.series.isNotEmpty ? data.series.first.values.length : 0) * 60.0,
          ),
          height: MediaQuery.of(context).size.height * 0.7,
          child: NexonChartWidget._buildChart(data, t),
        ),
      ),
    );
  }
}
