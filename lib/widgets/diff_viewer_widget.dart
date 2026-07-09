import 'package:flutter/material.dart';

class DiffViewerWidget extends StatelessWidget {
  final String content;

  const DiffViewerWidget({Key? key, required this.content}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final lines = content.split('\n');
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: lines.length,
        itemBuilder: (context, index) {
          final line = lines[index];
          Color bgColor = Colors.transparent;
          Color textColor = const Color(0xFFD4D4D4);

          if (line.startsWith('+')) {
            bgColor = const Color(0xFF2EA043).withOpacity(0.15);
            textColor = const Color(0xFF2EA043);
          } else if (line.startsWith('-')) {
            bgColor = const Color(0xFFF85149).withOpacity(0.15);
            textColor = const Color(0xFFF85149);
          } else if (line.startsWith('@@')) {
            bgColor = const Color(0xFF388BFD).withOpacity(0.15);
            textColor = const Color(0xFF388BFD);
          }

          return Container(
            color: bgColor,
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2.0),
            child: Text(
              line,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.0,
                color: textColor,
              ),
            ),
          );
        },
      ),
    );
  }
}
