import re

with open('lib/main.dart', 'r') as f:
    content = f.read()

widget_code = """class ChartDiagramWidget extends StatelessWidget {
  final String jsonString;
  const ChartDiagramWidget({super.key, required this.jsonString});

  // Curated professional palette
  static const _palette = [
    Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFFEC4899),
    Color(0xFF06B6D4), Color(0xFF10B981), Color(0xFFF59E0B),
    Color(0xFFEF4444), Color(0xFF3B82F6), Color(0xFFF97316),
    Color(0xFF84CC16),
  ];


  Color _color(String? hex, int i) {
    if (hex != null && hex.isNotEmpty) {
      try {
        final h = hex.replaceAll('#', '');
        if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
        if (h.length == 8) return Color(int.parse(h, radix: 16));
      } catch (_) {}
    }
    return _palette[i % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    try {
      final data = jsonDecode(jsonString);
      final type = data['type']?.toString().toLowerCase() ?? 'bar';
      final title = data['title']?.toString();
      final List items = data['data'] ?? [];
      if (items.isEmpty) return const SizedBox.shrink();

      Widget chart;

      final titlesData = FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            getTitlesWidget: (value, meta) {
              final i = value.toInt();
              if (i < 0 || i >= items.length) return const SizedBox.shrink();
              final label = (items[i] as Map)['label']?.toString() ?? '';
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  label.length > 10 ? '${label.substring(0, 9)}…' : label,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8), fontWeight: FontWeight.w400),
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
            getTitlesWidget: (value, meta) {
              if (value == meta.max || value == 0) return const SizedBox.shrink();
              final s = value >= 1000 ? '${(value / 1000).toStringAsFixed(1)}k' : value.toInt().toString();
              return Text(s, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w400));
            },
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      );

      if (type == 'pie' || type == 'donut') {
        final centerRadius = type == 'donut' ? 55.0 : 0.0;
        chart = PieChart(
          PieChartData(
            sectionsSpace: 3,
            centerSpaceRadius: centerRadius,
            startDegreeOffset: -90,
            sections: items.asMap().entries.map((e) {
              final item = e.value as Map;
              final c = _color(item['color']?.toString(), e.key);
              final v = (item['value'] as num).toDouble();
              final total = items.fold<double>(0, (s, x) => s + (x['value'] as num).toDouble());
              final pct = total > 0 ? (v / total * 100).toStringAsFixed(1) : '0';
              return PieChartSectionData(
                color: c,
                value: v,
                title: '${item['label'] ?? ''}\\n$pct%',
                radius: 80,
                titleStyle: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500,
                  color: Colors.white, shadows: [Shadow(blurRadius: 2)],
                ),
              );
            }).toList(),
          ),
          swapAnimationDuration: const Duration(milliseconds: 300),
          swapAnimationCurve: Curves.easeOutCubic,
        );
      } else if (type == 'line') {
        final maxY = items.map((e) => (e['value'] as num).toDouble()).reduce((a, b) => a > b ? a : b);
        final niceMax = maxY * 1.15;
        chart = LineChart(
          LineChartData(
            maxY: niceMax,
            lineTouchData: LineTouchData(
              enabled: true,
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (touchedSpots) {
                  return touchedSpots.map((spot) {
                    final item = items[spot.spotIndex] as Map;
                    return LineTooltipItem(
                      '${item['label']}\\n',
                      const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace'),
                      children: [
                        TextSpan(
                          text: spot.y.toStringAsFixed(spot.y == spot.y.truncateToDouble() ? 0 : 1),
                          style: TextStyle(color: _color(item['color']?.toString(), spot.spotIndex), fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                      ],
                    );
                  }).toList();
                },
              ),
            ),
            titlesData: titlesData,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: niceMax / 5,
              getDrawingHorizontalLine: (v) => FlLine(color: Colors.white.withOpacity(0.5), strokeWidth: 0.5),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: items.asMap().entries.map((e) => FlSpot(e.key.toDouble(), (e.value['value'] as num).toDouble())).toList(),
                isCurved: true,
                color: _color(items.first['color']?.toString(), 0),
                barWidth: 2,
                isStrokeCapRound: true,
                isStrokeJoinRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                    radius: 3.5,
                    color: barData.color ?? Colors.blue,
                    strokeWidth: 1,
                    strokeColor: Colors.white,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: (_color(items.first['color']?.toString(), 0)).withOpacity(0.08),
                ),
              ),
            ],
          ),
          swapAnimationDuration: const Duration(milliseconds: 300),
          swapAnimationCurve: Curves.easeOutCubic,
        );
      } else {
        // Bar chart
        final maxY = items.map((e) => (e['value'] as num).toDouble()).reduce((a, b) => a > b ? a : b);
        final niceMax = maxY * 1.15;
        chart = BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: niceMax,
            barTouchData: BarTouchData(
              enabled: true,
              touchTooltipData: BarTouchTooltipData(
                getTooltipItems: (group, groupIndex, rod, rodIndex) {
                  final item = items[groupIndex] as Map;
                  return BarTooltipItem(
                    '${item['label']}\\n',
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace'),
                    children: [
                      TextSpan(
                        text: rod.toY.toStringAsFixed(rod.toY == rod.toY.truncateToDouble() ? 0 : 1),
                        style: TextStyle(color: _color(item['color']?.toString(), groupIndex), fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                    ],
                  );
                },
              ),
            ),
            titlesData: titlesData,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: niceMax / 5,
              getDrawingHorizontalLine: (v) => const FlLine(color: Color(0xFF1E293B), strokeWidth: 0.5),
            ),
            borderData: FlBorderData(show: false),
            barGroups: items.asMap().entries.map((e) {
              final item = e.value as Map;
              final c = _color(item['color']?.toString(), e.key);
              return BarChartGroupData(
                x: e.key,
                barRods: [
                  BarChartRodData(
                    toY: (item['value'] as num).toDouble(),
                    gradient: LinearGradient(
                      colors: [c.withOpacity(0.7), c],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                    width: items.length > 8 ? 12 : 20,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    backDrawRodData: BackgroundBarChartRodData(
                      show: true,
                      toY: niceMax,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
          swapAnimationDuration: const Duration(milliseconds: 300),
          swapAnimationCurve: Curves.easeOutCubic,
        );
      }

      return RepaintBoundary(
        child: Container(
          constraints: const BoxConstraints(minHeight: 320, maxHeight: 600),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1120),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(40, 12, 16, 32),
                  child: chart,
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
          color: const Color(0xFF1A0A0A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade800),
        ),
        child: Text('Chart error: $e',
            style: TextStyle(color: Colors.red.shade400, fontSize: 12, fontFamily: 'monospace')),
      );
    }
  }
}"""

pattern = r'class ChartDiagramWidget extends StatelessWidget \{.*?Widget build\(BuildContext context\) \{.*?return Container\(.*?\}\n\}'

content = re.sub(pattern, widget_code, content, flags=re.DOTALL)

with open('lib/main.dart', 'w') as f:
    f.write(content)

