import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/app_state.dart';
import 'report_view.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  String _date(DateTime d) {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(d.day)}.${p(d.month)}.${d.year}  ${p(d.hour)}:${p(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('История', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (s.history.isNotEmpty)
            IconButton(
              tooltip: 'Очистить историю',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Очистить историю?'),
                    content: const Text('Все сохранённые расшифровки будут удалены.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Отмена')),
                      FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Удалить')),
                    ],
                  ),
                );
                if (ok == true) s.clearHistory();
              },
            ),
        ],
      ),
      body: s.history.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.history, size: 56, color: cs.outlineVariant),
                  const SizedBox(height: 12),
                  Text('Здесь появятся ваши расшифровки',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ]),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: s.history.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final h = s.history[i];
                final first = h.results.first;
                return Dismissible(
                  key: ValueKey(h.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    decoration: BoxDecoration(
                        color: cs.errorContainer,
                        borderRadius: BorderRadius.circular(20)),
                    child: Icon(Icons.delete, color: cs.onErrorContainer),
                  ),
                  onDismissed: (_) => s.deleteHistory(h.id),
                  child: Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => _HistoryDetail(session: h))),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.audio_file, color: cs.primary, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(h.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700, fontSize: 15)),
                              ),
                            ]),
                            const SizedBox(height: 8),
                            Text(first.summary,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
                            const SizedBox(height: 10),
                            Row(children: [
                              Text(_date(h.createdAt),
                                  style: TextStyle(fontSize: 12, color: cs.outline)),
                              const Spacer(),
                              if (first.model.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: cs.primaryContainer.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(first.model,
                                      style: TextStyle(
                                          fontSize: 11, color: cs.onPrimaryContainer)),
                                ),
                            ]),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _HistoryDetail extends StatelessWidget {
  final HistorySession session;
  const _HistoryDetail({required this.session});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(session.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            onPressed: () => ReportView.showExportSheet(context, session.results),
          ),
        ],
      ),
      body: SafeArea(child: ReportView(results: session.results)),
    );
  }
}
