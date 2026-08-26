// Extracted from main.dart lines 20124-20367
// Extracted on: 2026-08-26T18:20:45.684617

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexon/main.dart';
import 'package:nexon/screens/kaggle_scripts.dart';

class KaggleSetupScreen extends StatefulWidget {
  const KaggleSetupScreen({super.key});

  @override
  State<KaggleSetupScreen> createState() => _KaggleSetupScreenState();
}

class _KaggleSetupScreenState extends State<KaggleSetupScreen> {
  int _currentStep = 0;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final step = KaggleScripts.steps[_currentStep];
    final isLast = _currentStep == KaggleScripts.steps.length - 1;

    return Scaffold(
      backgroundColor: const Color(0xFFFBF6EC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFBF6EC),
        elevation: 0,
        title: const Text(
          'Kaggle Free GPU Setup',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2D241C)),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF7B4E2E)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: (_currentStep + 1) / KaggleScripts.steps.length,
            backgroundColor: const Color(0xFFE5DDD3),
            color: const Color(0xFF7C3AED),
            minHeight: 4,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_currentStep == 0) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF9F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE7D8C4)),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Before you start:',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF2D241C)),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '1. Create a free account at kaggle.com\n'
                            '2. Create a new notebook: Create → New Notebook\n'
                            '3. In the right settings panel, set Accelerator → GPU T4 x2\n'
                            '4. Each step below goes in its own code cell',
                            style: TextStyle(fontSize: 12, color: Color(0xFF6C5946), height: 1.6),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Color(0xFF7C3AED),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${step.number}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          step.title,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D241C)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    step.description,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF6C5946)),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Copy this script and paste it into a new code cell in your Kaggle notebook:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF7B4E2E)),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 48, 12),
                          child: SelectableText(
                            step.script,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              height: 1.4,
                              color: Color(0xFFD4D4D4),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IconButton(
                            icon: Icon(
                              _copied ? Icons.check : Icons.copy,
                              size: 18,
                              color: _copied ? Colors.green : Colors.white70,
                            ),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: step.script));
                              setState(() => _copied = true);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Script copied! Paste it into a Kaggle code cell.'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                              Future.delayed(const Duration(seconds: 2), () {
                                if (mounted) setState(() => _copied = false);
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isLast) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'After running this cell:',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF166534)),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'When the script finishes, you\'ll see:\n\n'
                            '  Base URL : https://xxxx-xxxx.trycloudflare.com/v1\n'
                            '  API key  : a1b2c3...\n\n'
                            'Copy both of those into this app\'s provider settings.\n\n'
                            'To keep it running without your phone:\n'
                            '• Click Save Version → Save & Run All (Commit)\n'
                            '• This runs on Kaggle\'s servers even if you close your browser\n'
                            '• Check the Output tab later for your URL and key',
                            style: TextStyle(fontSize: 12, color: Color(0xFF15803D), height: 1.6),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_currentStep > 0)
                  TextButton.icon(
                    onPressed: () => setState(() => _currentStep--),
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Previous'),
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFF7B4E2E)),
                  )
                else
                  const SizedBox(width: 80),
                Text(
                  'Step ${_currentStep + 1} of ${KaggleScripts.steps.length}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF9B8B7A)),
                ),
                if (!isLast)
                  FilledButton.icon(
                    onPressed: () => setState(() => _currentStep++),
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('Next'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      foregroundColor: Colors.white,
                    ),
                  )
                else
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Done! Enter your Base URL and API key in provider settings.'),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    },
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Done'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
