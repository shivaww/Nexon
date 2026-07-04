import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexon/main.dart'; // or whatever the package name is
import 'package:nexon/widgets/nexon_chart.dart';
import 'dart:convert';

void main() {
  testWidgets('Test NexonChartWidget with line chart', (WidgetTester tester) async {
    const jsonString = '''
    {
      "type": "line",
      "title": "Test",
      "data": [{"label": "A", "value": 10}, {"label": "B", "value": 20}]
    }
    ''';
    
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: NexonChartWidget(chartBlock: jsonString),
      ),
    ));

    expect(find.byType(NexonChartWidget), findsOneWidget);
    expect(find.textContaining('Chart error:'), findsNothing);
  });
}
