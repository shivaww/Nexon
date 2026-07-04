// ============================================================================
// NexonChart — Template-based chart rendering system
// LLMs emit a simple line-based format; the app renders beautiful charts.
// ============================================================================

import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';

// ── Palette ──────────────────────────────────────────────────────────────────

final _kChartPalette = [
  Color(0xFF6366F1), // indigo
  Color(0xFF8B5CF6), // violet
  Color(0xFFEC4899), // pink
  Color(0xFF06B6D4), // cyan
  Color(0xFF10B981), // emerald
  Color(0xFFF59E0B), // amber
  Color(0xFFEF4444), // red
  Color(0xFF3B82F6), // blue
  Color(0xFFF97316), // orange
  Color(0xFF84CC16), // lime
  Color(0xFF14B8A6), // teal
  Color(0xFFE879F9), // fuchsia
];

Color _paletteColor(int i) => _kChartPalette[i % _kChartPalette.length];

Color _parseColor(String? hex, int fallbackIndex) {
  if (hex != null && hex.isNotEmpty) {
    try {
      final h = hex.replaceAll('#', '');
      if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
      if (h.length == 8) return Color(int.parse(h, radix: 16));
    } catch (_) {}
  }
  return _paletteColor(fallbackIndex);
}

// ── Theme constants ─────────────────────────────────────────────────────────

final _kCardBg = const Color(0xFFFFFBF2);
final _kBorderColor = const Color(0xFFE7D8C4);
final _kTitleColor = const Color(0xFF2D241C);
final _kSubtitleColor = const Color(0xFF8B7355);
final _kGridColor = const Color(0xFFE7D8C4);
final _kAxisLabelColor = const Color(0xFF8B7355);
final _kTooltipBg = const Color(0xFF2D241C);

// ── Data Models ─────────────────────────────────────────────────────────────

class _ChartData {
  final String type;
  final String title;
  final double? rangeMin;
  final double? rangeMax;
  final List<_Series> series;
  final List<String> labels;
  // For heatmap
  final List<String> xLabels;
  final List<String> yLabels;
  final List<List<double>> matrix;
  // For gantt
  final List<_GanttItem> ganttItems;
  // For gauge
  final double gaugeValue;
  final double gaugeMax;
  final String gaugeLabel;

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

// ── Parser ───────────────────────────────────────────────────────────────────
//
// Simple line-based format:
//
// type: bar
// title: Revenue by Quarter
// range: 0-100
// labels: Q1, Q2, Q3, Q4
// series: Revenue = 45, 67, 89, 52
// series: Costs = 30, 45, 60, 40
//
// For single series shorthand:
// type: pie
// title: Market Share
// Android: 45
// iOS: 30
// Web: 25
//

_ChartData _parseChartBlock(String raw) {
  final trimmed = raw.trim();

  // ── Backward compat: old JSON format {"type":"bar","data":[...]} ──────
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

  // Collect lines that are simple key:value (for shorthand single-series)
  final shorthandEntries = <String, double>{};
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
      final parts = value.split(RegExp(r'[-–—]')).map((s) => s.trim()).toList();
      if (parts.length == 2) {
        rangeMin = double.tryParse(parts[0]);
        rangeMax = double.tryParse(parts[1]);
      }
    } else if (key == 'labels') {
      labels = value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    } else if (key == 'xlabels') {
      xLabels = value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    } else if (key == 'ylabels') {
      yLabels = value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    } else if (key == 'row') {
      matrix.add(value.split(',').map((s) => double.tryParse(s.trim()) ?? 0).toList());
    } else if (key == 'series') {
      // series: Revenue = 45, 67, 89, 52
      final eqIdx = value.indexOf('=');
      if (eqIdx > 0) {
        final name = value.substring(0, eqIdx).trim();
        final vals = value.substring(eqIdx + 1).split(',').map((s) => double.tryParse(s.trim()) ?? 0).toList();
        series.add(_Series(name: name, values: vals, color: _paletteColor(seriesColorIndex++)));
      }
    } else if (key == 'gantt' || key == 'task') {
      // gantt: Design = 0, 3
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
    } else if (!['type', 'title', 'range', 'labels', 'series', 'row', 'xlabels', 'ylabels', 'gantt', 'task', 'value', 'max', 'label'].contains(key)) {
      // Shorthand: "Android: 45" or "Android: 45, 30" (for scatter x,y)
      final numVal = double.tryParse(value.split(',').first.trim());
      if (numVal != null) {
        // Use the ORIGINAL key from the line (preserve casing)
        final originalKey = line.substring(0, colonIdx).trim();
        shorthandEntries[originalKey] = numVal;
      }
    }
  }

  // If no explicit series but have shorthand entries, build a single series
  if (series.isEmpty && shorthandEntries.isNotEmpty && ganttItems.isEmpty) {
    labels = shorthandEntries.keys.toList();
    series = [
      _Series(
        name: 'Data',
        values: shorthandEntries.values.toList(),
        color: _paletteColor(0),
      ),
    ];
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
  );
}

// ── Main Widget ─────────────────────────────────────────────────────────────

class NexonChartWidget extends StatelessWidget {
  final String chartBlock;
  const NexonChartWidget({super.key, required this.chartBlock});

  @override
  Widget build(BuildContext context) {
    try {
      final data = _parseChartBlock(chartBlock);
      if (data.series.isEmpty && data.ganttItems.isEmpty && data.matrix.isEmpty && !data.type.contains('gauge')) {
        return const SizedBox.shrink();
      }

      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _FullScreenChartViewer(chartBlock: chartBlock),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: _kCardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (data.title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Text(
                    data.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _kTitleColor,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                child: SizedBox(
                  height: 280,
                  child: _buildChart(data),
                ),
              ),
              // Legend
              if (data.series.length > 1 && !data.type.contains('pie') && !data.type.contains('donut'))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: data.series.map((s) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10, height: 10,
                          decoration: BoxDecoration(
                            color: s.color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(s.name, style: TextStyle(fontSize: 12, color: _kSubtitleColor)),
                      ],
                    )).toList(),
                  ),
                ),
            ],
          ),
        ),
      );
    } catch (e) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF5F5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE7A0A0)),
        ),
        child: Text('Chart error: $e',
            style: const TextStyle(color: Color(0xFF9B4D39), fontSize: 12, fontFamily: 'monospace')),
      );
    }
  }

  static Widget _buildChart(_ChartData data) {
    switch (data.type) {
      case 'bar':
      case 'bargrouped':
      case 'grouped':
        return _buildBarChart(data, grouped: data.series.length > 1);
      case 'barstacked':
      case 'stacked':
        return _buildStackedBarChart(data);
      case 'line':
      case 'linesingle':
      case 'linemulti':
      case 'curve':
      case 'curvegraph':
        return _buildLineChart(data);
      case 'area':
      case 'areachart':
        return _buildAreaChart(data);
      case 'pie':
        return _buildPieChart(data, donut: false);
      case 'donut':
        return _buildPieChart(data, donut: true);
      case 'scatter':
      case 'scatterplot':
        return _buildScatterChart(data);
      case 'radar':
      case 'spider':
        return _buildRadarChart(data);
      case 'histogram':
        return _buildHistogramChart(data);
      case 'heatmap':
        return _buildHeatmap(data);
      case 'bubble':
      case 'bubblechart':
        return _buildBubbleChart(data);
      case 'gantt':
      case 'timeline':
        return _buildGanttChart(data);
      case 'gauge':
      case 'progress':
        return _buildGaugeChart(data);
      case 'geometry':
      case 'geometrygraph':
        return _buildLineChart(data); // geometry graphs render as line/curve
      default:
        return _buildBarChart(data, grouped: data.series.length > 1);
    }
  }

  // ── Bar Chart (single & grouped) ────────────────────────────────────────

  static Widget _buildBarChart(_ChartData data, {bool grouped = false}) {
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
              tooltipBorder: BorderSide(color: _kBorderColor),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final label = groupIndex < labelCount ? data.labels[groupIndex] : '';
                final seriesName = rodIndex < seriesCount ? data.series[rodIndex].name : '';
                final valStr = rod.toY.toStringAsFixed(rod.toY == rod.toY.truncateToDouble() ? 0 : 1);
                return BarTooltipItem(
                  seriesCount > 1 ? '$label\n$seriesName: $valStr' : '$label\n$valStr',
                  const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                );
              },
            ),
          ),
          titlesData: _buildTitlesData(data, niceMax, minVal),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: _niceInterval(niceMax - minVal),
            getDrawingHorizontalLine: (v) => FlLine(color: _kGridColor, strokeWidth: 0.5),
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
                  final c = entry.value.color;
                  return BarChartRodData(
                    toY: val,
                    color: c,
                    width: rodWidth,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  );
                }).toList(),
              );
            },
          ),
        ),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  // ── Stacked Bar Chart ───────────────────────────────────────────────────

  static Widget _buildStackedBarChart(_ChartData data) {
    final labelCount = data.labels.length;
    final seriesCount = data.series.length;
    // Compute max stacked value
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
              tooltipBorder: BorderSide(color: _kBorderColor),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final label = groupIndex < labelCount ? data.labels[groupIndex] : '';
                // For stacked, rodIndex is always 0; show total
                return BarTooltipItem(
                  '$label\n${rod.toY.toStringAsFixed(0)}',
                  const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                );
              },
            ),
          ),
          titlesData: _buildTitlesData(data, niceMax, minVal),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: _niceInterval(niceMax - minVal),
            getDrawingHorizontalLine: (v) => FlLine(color: _kGridColor, strokeWidth: 0.5),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(
            labelCount > 0 ? labelCount : (data.series.isNotEmpty ? data.series.first.values.length : 0),
            (i) {
              // Build stacked rod segments
              final rodStackItems = <BarChartRodStackItem>[];
              double cumulative = 0;
              for (int si = 0; si < seriesCount; si++) {
                final val = i < data.series[si].values.length ? data.series[si].values[i] : 0.0;
                rodStackItems.add(BarChartRodStackItem(cumulative, cumulative + val, data.series[si].color));
                cumulative += val;
              }
              return BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: cumulative,
                    rodStackItems: rodStackItems,
                    width: labelCount > 8 ? 14.0 : 22.0,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ],
              );
            },
          ),
        ),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  // ── Line Chart ──────────────────────────────────────────────────────────

  static Widget _buildLineChart(_ChartData data) {
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
              tooltipBorder: BorderSide(color: _kBorderColor),
              getTooltipItems: (spots) => spots.map((spot) {
                final sIdx = spot.barIndex;
                final name = sIdx < data.series.length ? data.series[sIdx].name : '';
                final label = spot.spotIndex < data.labels.length ? data.labels[spot.spotIndex] : '';
                final valStr = spot.y.toStringAsFixed(spot.y == spot.y.truncateToDouble() ? 0 : 1);
                return LineTooltipItem(
                  data.series.length > 1 ? '$label\n$name: $valStr' : '$label\n$valStr',
                  TextStyle(color: data.series[sIdx].color, fontSize: 12, fontWeight: FontWeight.w600),
                );
              }).toList(),
            ),
          ),
          titlesData: _buildTitlesData(data, niceMax, minVal),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: _niceInterval(niceMax - minVal),
            getDrawingHorizontalLine: (v) => FlLine(color: _kGridColor, strokeWidth: 0.5),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: data.series.map((s) {
            return LineChartBarData(
              spots: s.values.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
              isCurved: true,
              curveSmoothness: 0.3,
              color: s.color,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
                  radius: 3,
                  color: bar.color ?? s.color,
                  strokeWidth: 1.5,
                  strokeColor: _kCardBg,
                ),
              ),
              belowBarData: BarAreaData(show: false),
            );
          }).toList(),
        ),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  // ── Area Chart ──────────────────────────────────────────────────────────

  static Widget _buildAreaChart(_ChartData data) {
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
              tooltipBorder: BorderSide(color: _kBorderColor),
              getTooltipItems: (spots) => spots.map((spot) {
                final sIdx = spot.barIndex;
                final valStr = spot.y.toStringAsFixed(spot.y == spot.y.truncateToDouble() ? 0 : 1);
                final label = spot.spotIndex < data.labels.length ? data.labels[spot.spotIndex] : '';
                return LineTooltipItem(
                  '$label\n$valStr',
                  TextStyle(color: data.series[sIdx].color, fontSize: 12, fontWeight: FontWeight.w600),
                );
              }).toList(),
            ),
          ),
          titlesData: _buildTitlesData(data, niceMax, minVal),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: _niceInterval(niceMax - minVal),
            getDrawingHorizontalLine: (v) => FlLine(color: _kGridColor, strokeWidth: 0.5),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: data.series.map((s) {
            return LineChartBarData(
              spots: s.values.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
              isCurved: true,
              curveSmoothness: 0.3,
              color: s.color,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: s.color.withOpacity(0.15),
              ),
            );
          }).toList(),
        ),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  // ── Pie / Donut ─────────────────────────────────────────────────────────

  static Widget _buildPieChart(_ChartData data, {required bool donut}) {
    if (data.series.isEmpty || data.series.first.values.isEmpty) return const SizedBox.shrink();
    final values = data.series.first.values;
    final total = values.fold<double>(0, (s, v) => s + v);

    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: donut ? 50 : 0,
        startDegreeOffset: -90,
        pieTouchData: PieTouchData(enabled: true),
        sections: values.asMap().entries.map((e) {
          final label = e.key < data.labels.length ? data.labels[e.key] : '';
          final pct = total > 0 ? (e.value / total * 100).toStringAsFixed(1) : '0';
          final c = _paletteColor(e.key);
          return PieChartSectionData(
            color: c,
            value: e.value,
            title: '$label\n$pct%',
            radius: donut ? 40 : 80,
            titleStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
            ),
            titlePositionPercentageOffset: donut ? 1.6 : 0.6,
          );
        }).toList(),
      ),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  // ── Scatter Chart ───────────────────────────────────────────────────────

  static Widget _buildScatterChart(_ChartData data) {
    // For scatter: each series has pairs. If only one series, pair labels (x indices) with values.
    final allVals = data.series.expand((s) => s.values).toList();
    if (allVals.isEmpty) return const SizedBox.shrink();
    final maxVal = allVals.reduce(math.max);
    final minVal = data.rangeMin ?? 0;
    final niceMax = data.rangeMax ?? (maxVal * 1.15 == 0 ? 10 : maxVal * 1.15);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
      child: ScatterChart(
        ScatterChartData(
          minY: minVal,
          maxY: niceMax,
          minX: -0.5,
          maxX: (data.series.isNotEmpty ? data.series.first.values.length.toDouble() : 10) - 0.5,
          scatterTouchData: ScatterTouchData(
            enabled: true,
            touchTooltipData: ScatterTouchTooltipData(
              getTooltipItems: (spot) {
                return ScatterTooltipItem(
                  '(${spot.x.toStringAsFixed(1)}, ${spot.y.toStringAsFixed(1)})',
                  textStyle: const TextStyle(color: Colors.white, fontSize: 11),
                );
              },
            ),
          ),
          titlesData: _buildTitlesData(data, niceMax, minVal),
          gridData: FlGridData(
            show: true,
            horizontalInterval: _niceInterval(niceMax - minVal),
            getDrawingHorizontalLine: (v) => FlLine(color: _kGridColor, strokeWidth: 0.5),
            getDrawingVerticalLine: (v) => FlLine(color: _kGridColor, strokeWidth: 0.5),
          ),
          borderData: FlBorderData(show: false),
          scatterSpots: data.series.expand((s) {
            return s.values.asMap().entries.map((e) => ScatterSpot(
              e.key.toDouble(), e.value,
              dotPainter: FlDotCirclePainter(
                radius: 5,
                color: s.color.withOpacity(0.7),
                strokeWidth: 1.5,
                strokeColor: s.color,
              ),
            ));
          }).toList(),
        ),
      ),
    );
  }

  // ── Radar / Spider Chart ────────────────────────────────────────────────

  static Widget _buildRadarChart(_ChartData data) {
    if (data.series.isEmpty) return const SizedBox.shrink();
    final allVals = data.series.expand((s) => s.values).toList();
    final maxVal = allVals.isEmpty ? 10 : allVals.reduce(math.max);
    final tickCount = 4;

    return RadarChart(
      RadarChartData(
        radarShape: RadarShape.polygon,
        tickCount: tickCount,
        ticksTextStyle: TextStyle(color: _kAxisLabelColor, fontSize: 10),
        tickBorderData: BorderSide(color: _kGridColor.withOpacity(0.5)),
        gridBorderData: BorderSide(color: _kGridColor.withOpacity(0.5)),
        radarBorderData: BorderSide(color: _kGridColor.withOpacity(0.5)),
        titleTextStyle: TextStyle(color: _kTitleColor, fontSize: 11, fontWeight: FontWeight.w500),
        getTitle: (index, angle) {
          if (index < data.labels.length) {
            return RadarChartTitle(text: data.labels[index]);
          }
          return const RadarChartTitle(text: '');
        },
        dataSets: data.series.map((s) {
          return RadarDataSet(
            dataEntries: s.values.map((v) => RadarEntry(value: v)).toList(),
            borderColor: s.color,
            fillColor: s.color.withOpacity(0.15),
            borderWidth: 2,
            entryRadius: 3,
          );
        }).toList(),
        titlePositionPercentageOffset: 0.15,
      ),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  // ── Histogram ───────────────────────────────────────────────────────────

  static Widget _buildHistogramChart(_ChartData data) {
    // Render as bar chart with no gaps
    final allVals = data.series.expand((s) => s.values).toList();
    if (allVals.isEmpty) return const SizedBox.shrink();
    final maxVal = allVals.reduce(math.max);
    final minVal = data.rangeMin ?? 0;
    final niceMax = data.rangeMax ?? (maxVal * 1.15 == 0 ? 10 : maxVal * 1.15);
    final values = data.series.first.values;

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
              tooltipBorder: BorderSide(color: _kBorderColor),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final label = groupIndex < data.labels.length ? data.labels[groupIndex] : '${groupIndex}';
                return BarTooltipItem(
                  '$label\n${rod.toY.toStringAsFixed(0)}',
                  const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                );
              },
            ),
          ),
          titlesData: _buildTitlesData(data, niceMax, minVal),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: _niceInterval(niceMax - minVal),
            getDrawingHorizontalLine: (v) => FlLine(color: _kGridColor, strokeWidth: 0.5),
          ),
          borderData: FlBorderData(show: false),
          barGroups: values.asMap().entries.map((e) {
            final c = _paletteColor(0);
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: e.value,
                  color: c.withOpacity(0.85),
                  width: values.length > 15 ? 10 : 20,
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: c, width: 0.5),
                ),
              ],
            );
          }).toList(),
        ),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  // ── Heatmap ─────────────────────────────────────────────────────────────

  static Widget _buildHeatmap(_ChartData data) {
    if (data.matrix.isEmpty) return const SizedBox.shrink();
    final allVals = data.matrix.expand((row) => row).toList();
    final maxVal = allVals.isEmpty ? 1 : allVals.reduce(math.max);
    final minVal = allVals.isEmpty ? 0 : allVals.reduce(math.min);
    final range = maxVal - minVal;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = data.matrix.isNotEmpty ? data.matrix.first.length : 0;
        final rows = data.matrix.length;
        if (cols == 0 || rows == 0) return const SizedBox.shrink();
        final cellW = (constraints.maxWidth - 60) / cols;
        final cellH = math.min(cellW, 240.0 / rows);

        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // X labels
              if (data.xLabels.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 50),
                  child: Row(
                    children: data.xLabels.asMap().entries.map((e) => SizedBox(
                      width: cellW,
                      child: Text(
                        e.value,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10, color: _kAxisLabelColor),
                        overflow: TextOverflow.ellipsis,
                      ),
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
                        style: TextStyle(fontSize: 10, color: _kAxisLabelColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    ...rowEntry.value.asMap().entries.map((colEntry) {
                      final intensity = range > 0 ? ((colEntry.value - minVal) / range).clamp(0.0, 1.0) : 0.5;
                      final color = Color.lerp(
                        const Color(0xFFE8DEF8),
                        const Color(0xFF6366F1),
                        intensity,
                      )!;
                      return Tooltip(
                        message: colEntry.value.toStringAsFixed(1),
                        child: Container(
                          width: cellW - 2,
                          height: cellH - 2,
                          margin: const EdgeInsets.all(1),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: cellW > 28
                              ? Center(
                                  child: Text(
                                    colEntry.value.toStringAsFixed(0),
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w500,
                                      color: intensity > 0.5 ? Colors.white : _kTitleColor,
                                    ),
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

  // ── Bubble Chart ────────────────────────────────────────────────────────

  static Widget _buildBubbleChart(_ChartData data) {
    // Uses scatter chart with varying dot sizes
    // For bubble, series values are treated as: value = y, index = x, magnitude = size
    final allVals = data.series.expand((s) => s.values).toList();
    if (allVals.isEmpty) return const SizedBox.shrink();
    final maxVal = allVals.reduce(math.max);
    final minVal = data.rangeMin ?? 0;
    final niceMax = data.rangeMax ?? (maxVal * 1.15 == 0 ? 10 : maxVal * 1.15);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
      child: ScatterChart(
        ScatterChartData(
          minY: minVal,
          maxY: niceMax,
          minX: -0.5,
          maxX: (data.series.isNotEmpty ? data.series.first.values.length.toDouble() : 10) - 0.5,
          scatterTouchData: ScatterTouchData(
            enabled: true,
            touchTooltipData: ScatterTouchTooltipData(
              getTooltipItems: (spot) {
                return ScatterTooltipItem(
                  '${spot.y.toStringAsFixed(1)}',
                  textStyle: const TextStyle(color: Colors.white, fontSize: 11),
                );
              },
            ),
          ),
          titlesData: _buildTitlesData(data, niceMax, minVal),
          gridData: FlGridData(
            show: true,
            horizontalInterval: _niceInterval(niceMax - minVal),
            getDrawingHorizontalLine: (v) => FlLine(color: _kGridColor, strokeWidth: 0.5),
            getDrawingVerticalLine: (v) => FlLine(color: _kGridColor, strokeWidth: 0.5),
          ),
          borderData: FlBorderData(show: false),
          scatterSpots: data.series.expand((s) {
            return s.values.asMap().entries.map((e) {
              final bubbleRadius = maxVal > 0 ? (e.value / maxVal * 18).clamp(4.0, 22.0) : 6.0;
              return ScatterSpot(
                e.key.toDouble(), e.value,
                dotPainter: FlDotCirclePainter(
                  radius: bubbleRadius,
                  color: s.color.withOpacity(0.5),
                  strokeWidth: 2,
                  strokeColor: s.color,
                ),
              );
            });
          }).toList(),
        ),
      ),
    );
  }

  // ── Gantt / Timeline ────────────────────────────────────────────────────

  static Widget _buildGanttChart(_ChartData data) {
    if (data.ganttItems.isEmpty) return const SizedBox.shrink();
    final maxEnd = data.ganttItems.map((g) => g.end).reduce(math.max);
    final niceMax = data.rangeMax ?? (maxEnd * 1.1 == 0 ? 10 : maxEnd * 1.1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final chartWidth = constraints.maxWidth - 120;
        final itemHeight = 28.0;
        final spacing = 6.0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: data.ganttItems.asMap().entries.map((e) {
                final item = e.value;
                final leftPct = niceMax > 0 ? item.start / niceMax : 0;
                final widthPct = niceMax > 0 ? (item.end - item.start) / niceMax : 0;
                return Padding(
                  padding: EdgeInsets.only(bottom: spacing),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          item.label,
                          style: TextStyle(fontSize: 11, color: _kTitleColor, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: itemHeight,
                          decoration: BoxDecoration(
                            color: _kGridColor.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: 1.0,
                            child: Padding(
                              padding: EdgeInsets.only(left: leftPct * chartWidth),
                              child: Container(
                                width: widthPct * chartWidth,
                                decoration: BoxDecoration(
                                  color: item.color,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${item.start.toInt()}-${item.end.toInt()}',
                                  style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  // ── Gauge / Progress ────────────────────────────────────────────────────

  static Widget _buildGaugeChart(_ChartData data) {
    final pct = data.gaugeMax > 0 ? (data.gaugeValue / data.gaugeMax).clamp(0.0, 1.0) : 0.0;
    final gaugeColor = pct < 0.3 ? const Color(0xFFEF4444) : pct < 0.7 ? const Color(0xFFF59E0B) : const Color(0xFF10B981);

    return Center(
      child: SizedBox(
        width: 180,
        height: 180,
        child: CustomPaint(
          painter: _GaugePainter(value: pct, color: gaugeColor),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  data.gaugeValue.toStringAsFixed(data.gaugeValue == data.gaugeValue.truncateToDouble() ? 0 : 1),
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: _kTitleColor),
                ),
                if (data.gaugeLabel.isNotEmpty)
                  Text(
                    data.gaugeLabel,
                    style: TextStyle(fontSize: 12, color: _kSubtitleColor),
                  ),
                Text(
                  '/ ${data.gaugeMax.toStringAsFixed(0)}',
                  style: TextStyle(fontSize: 11, color: _kSubtitleColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Shared Helpers ──────────────────────────────────────────────────────

  static FlTitlesData _buildTitlesData(_ChartData data, double maxY, double minY) {
    return FlTitlesData(
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: data.labels.isNotEmpty,
          reservedSize: 30,
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
                style: TextStyle(fontSize: 11, color: _kAxisLabelColor, fontWeight: FontWeight.w400),
                textAlign: TextAlign.center,
              ),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 42,
          interval: _niceInterval(maxY - minY),
          getTitlesWidget: (value, meta) {
            if (value == meta.max) return const SizedBox.shrink();
            final s = value.abs() >= 1000
                ? '${(value / 1000).toStringAsFixed(1)}k'
                : value == value.truncateToDouble()
                    ? value.toInt().toString()
                    : value.toStringAsFixed(1);
            return Text(s, style: TextStyle(fontSize: 10, color: _kAxisLabelColor));
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

// ── Gauge Painter ───────────────────────────────────────────────────────────

class _GaugePainter extends CustomPainter {
  final double value; // 0.0 – 1.0
  final Color color;

  _GaugePainter({required this.value, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 12;
    const startAngle = 2.3; // ~132 degrees
    const sweepAngle = 4.6; // ~264 degrees arc

    // Background arc
    final bgPaint = Paint()
      ..color = _kGridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // Value arc
    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle * value,
      false,
      valuePaint,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value || old.color != color;
}

// ── Full Screen Chart Viewer ────────────────────────────────────────────────

class _FullScreenChartViewer extends StatelessWidget {
  final String chartBlock;
  const _FullScreenChartViewer({required this.chartBlock});

  @override
  Widget build(BuildContext context) {
    final data = _parseChartBlock(chartBlock);

    return Scaffold(
      backgroundColor: _kCardBg,
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F2E8),
        foregroundColor: _kTitleColor,
        title: Text(data.title.isEmpty ? 'Chart' : data.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
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
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              height: MediaQuery.of(context).size.height * 0.7,
              child: NexonChartWidget._buildChart(data),
            ),
          ),
        ),
      ),
    );
  }
}
