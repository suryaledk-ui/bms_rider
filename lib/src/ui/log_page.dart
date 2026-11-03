import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../controller.dart';
import 'theme.dart';
import 'widgets.dart';

class LogPage extends StatelessWidget {
  const LogPage({super.key});

  @override
  Widget build(BuildContext context) {
    final logger = context.watch<AppController>().scanLog;
    final lineCount = logger.isEmpty ? 0 : logger.text.split('\n').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Copy all logs',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: logger.text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Logs copied — paste them anywhere'),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Clear logs',
            onPressed: () => logger.clear(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: VoltTokens.voltCyan.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: VoltTokens.voltCyan.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.support_agent_rounded,
                    size: 18,
                    color: VoltTokens.voltCyan,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'If a BMS does not show up, open this screen, tap copy, '
                      'and send the text for support.',
                      style: VoltType.caption.copyWith(
                        fontSize: 12.5,
                        color: VoltTokens.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: VoltTokens.bgInteractive,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: VoltTokens.borderSubtle),
                    ),
                    child: Text(
                      '$lineCount lines',
                      style: VoltType.labelMicro.copyWith(fontSize: 9.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: logger.isEmpty
                ? Center(
                    child: VoltEmptyState(
                      icon: Icons.terminal_rounded,
                      eyebrow: 'Terminal empty',
                      title: 'No logs yet',
                      message:
                          'Logs appear here the moment you scan or connect '
                          '— including every BLE discovery and handshake.',
                      accent: VoltTokens.voltCyan,
                    ),
                  )
                : Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: VoltTokens.bgCanvas,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: VoltTokens.borderSubtle),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        logger.text,
                        style: VoltType.mono.copyWith(fontSize: 11.5),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
