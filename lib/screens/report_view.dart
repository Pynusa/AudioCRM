import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/platform_services.dart';
import '../services/report_formatter.dart';

/// Consolidated report — port of CombinedReport.tsx.
class ReportView extends StatelessWidget {
  final List<TranscriptionResult> results;
  final VoidCallback? onReset;
  final bool showHeaderActions;
  const ReportView(
      {super.key,
      required this.results,
      this.onReset,
      this.showHeaderActions = true});

  static void _snack(BuildContext c, String t) => ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(t)));

  static Future<void> copy(BuildContext c, String text, String msg) async {
    await FileServices.copy(text);
    if (c.mounted) _snack(c, msg);
  }

  static void showExportSheet(BuildContext context, List<TranscriptionResult> results) {
    final base = ReportFormatter.fileBaseName(results);
    final date = DateTime.now().toIso8601String().substring(0, 10);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        Future<void> run(String content, String ext, String mime, bool save) async {
          Navigator.pop(ctx);
          final name = '${base}_$date.$ext';
          try {
            if (save) {
              final ok = await FileServices.saveText(content, name);
              if (ok && context.mounted) _snack(context, 'Файл сохранён: $name');
            } else {
              await FileServices.shareText(content, name, mime: mime);
            }
          } catch (e) {
            if (context.mounted) _snack(context, 'Ошибка: $e');
          }
        }

        Widget item(IconData icon, String title, String sub, String content,
                String ext, String mime) =>
            ListTile(
              leading: Icon(icon),
              title: Text(title),
              subtitle: Text(sub),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Сохранить в файлы',
                  icon: const Icon(Icons.save_alt),
                  onPressed: () => run(content, ext, mime, true),
                ),
                IconButton(
                  tooltip: 'Поделиться',
                  icon: const Icon(Icons.share),
                  onPressed: () => run(content, ext, mime, false),
                ),
              ]),
            );

        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Экспорт',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            item(Icons.description_outlined, 'Полный отчёт · Markdown',
                'Резюме, CRM и расшифровка (.md)',
                ReportFormatter.markdown(results), 'md', 'text/markdown'),
            item(Icons.article_outlined, 'Полный отчёт · TXT',
                'Для Блокнота, Telegram, почты',
                ReportFormatter.plainText(results), 'txt', 'text/plain'),
            item(Icons.forum_outlined, 'Только диалог · TXT',
                'Реплики с таймкодами',
                ReportFormatter.plainText(results, onlyDialogue: true),
                'txt', 'text/plain'),
            item(Icons.forum, 'Только диалог · Markdown', 'Реплики (.md)',
                ReportFormatter.markdown(results, onlyDialogue: true),
                'md', 'text/markdown'),
            const SizedBox(height: 12),
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasCrm = results.any((r) => r.crmReport != null);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        // Header banner
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.description, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Консолидированный отчёт (${results.length} ${results.length == 1 ? 'файл' : 'файла(ов)'})',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 17),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Text(
                results.map((r) => r.model).toSet().where((m) => m.isNotEmpty).isEmpty
                    ? 'Вся информация объединена в один документ.'
                    : 'Модель: ${results.map((r) => r.model).toSet().join(', ')}',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _BannerButton(
                    icon: Icons.copy,
                    label: 'Текст',
                    primary: true,
                    onTap: () => copy(context,
                        ReportFormatter.fullTranscript(results), 'Расшифровка скопирована'),
                  ),
                  _BannerButton(
                    icon: Icons.copy_all,
                    label: 'Весь отчёт',
                    onTap: () => copy(context, ReportFormatter.fullReport(results),
                        'Отчёт скопирован'),
                  ),
                  _BannerButton(
                    icon: Icons.ios_share,
                    label: 'Экспорт',
                    onTap: () => showExportSheet(context, results),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        _SectionTitle(Icons.auto_awesome, 'Общее резюме переговоров'),
        for (final r in results)
          _Box(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FileLabel(r.fileName),
                Container(
                  padding: const EdgeInsets.only(left: 12),
                  decoration: BoxDecoration(
                    border: Border(
                        left: BorderSide(color: cs.primary.withValues(alpha: 0.4), width: 3)),
                  ),
                  child: SelectableText(r.summary,
                      style: const TextStyle(
                          fontStyle: FontStyle.italic, height: 1.5)),
                ),
                if (r.crmReport != null && r.crmReport!.summary.isNotEmpty) ...[
                  const Divider(height: 28),
                  const Text('Детальное резюме (CRM):',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  SelectableText(r.crmReport!.summary,
                      style: TextStyle(color: cs.onSurfaceVariant, height: 1.5)),
                ],
                if (r.crmReport != null && r.crmReport!.sentiment.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: cs.tertiaryContainer.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      Icon(Icons.mood, size: 18, color: cs.onTertiaryContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Настроение клиента: ${r.crmReport!.sentiment}',
                            style: TextStyle(color: cs.onTertiaryContainer, fontSize: 13)),
                      ),
                    ]),
                  ),
                ],
              ],
            ),
          ),

        if (hasCrm) ...[
          _ListSection(
            icon: Icons.check_circle_outline,
            title: 'Ключевые моменты',
            results: results,
            pick: (c) => c.keyPoints,
            bullet: '•',
            color: cs.primary,
          ),
          _ListSection(
            icon: Icons.track_changes,
            title: 'Потребности и боли клиента',
            results: results,
            pick: (c) => c.clientNeeds,
            bullet: '→',
            color: const Color(0xFFF59E0B),
          ),
          _ListSection(
            icon: Icons.arrow_circle_right_outlined,
            title: 'Рекомендуемые следующие шаги',
            results: results,
            pick: (c) => c.nextSteps,
            bullet: '✓',
            color: const Color(0xFF10B981),
          ),
        ],

        _SectionTitle(Icons.forum_outlined, 'Полная расшифровка'),
        for (final r in results) _TranscriptBox(result: r),
        if (onReset != null) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Начать заново')),
        ],
      ],
    );
  }
}

class _BannerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const _BannerButton(
      {required this.icon, required this.label, required this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? Colors.white : Colors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon,
                size: 18, color: primary ? const Color(0xFF4338CA) : Colors.white),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: primary ? const Color(0xFF4338CA) : Colors.white)),
          ]),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SectionTitle(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}

class _Box extends StatelessWidget {
  final Widget child;
  const _Box({required this.child});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
            child: Padding(padding: const EdgeInsets.all(16), child: child)),
      );
}

class _FileLabel extends StatelessWidget {
  final String name;
  const _FileLabel(this.name);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Icon(Icons.audio_file, size: 14, color: cs.outline),
        const SizedBox(width: 4),
        Expanded(
          child: Text(name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700,
                  color: cs.outline)),
        ),
      ]),
    );
  }
}

class _ListSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<TranscriptionResult> results;
  final List<String> Function(CrmReport) pick;
  final String bullet;
  final Color color;
  const _ListSection({
    required this.icon,
    required this.title,
    required this.results,
    required this.pick,
    required this.bullet,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = results
        .where((r) => r.crmReport != null && pick(r.crmReport!).isNotEmpty)
        .toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _SectionTitle(icon, title),
        _Box(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in items) ...[
                if (results.length > 1) _FileLabel(r.fileName),
                for (final p in pick(r.crmReport!))
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(bullet,
                            style: TextStyle(
                                color: color, fontWeight: FontWeight.w900)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: SelectableText(p,
                                style: const TextStyle(height: 1.4))),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TranscriptBox extends StatelessWidget {
  final TranscriptionResult result;
  const _TranscriptBox({required this.result});

  static const _palette = [
    Color(0xFF4F46E5),
    Color(0xFF0EA5E9),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
  ];

  static String _emoji(String e) {
    final l = e.toLowerCase();
    if (l.contains('happy')) return '😊';
    if (l.contains('sad')) return '😔';
    if (l.contains('angry')) return '😠';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final speakers = <String>[];
    for (final s in result.segments) {
      if (!speakers.contains(s.speaker)) speakers.add(s.speaker);
    }
    return _Box(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: _FileLabel(result.fileName)),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Скопировать диалог',
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () => ReportView.copy(context,
                  ReportFormatter.singleTranscript(result), 'Диалог скопирован'),
            ),
          ]),
          Text('Реплик: ${result.segments.length} · Спикеров: ${speakers.length}',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          for (final s in result.segments)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: _palette[speakers.indexOf(s.speaker) % _palette.length]
                        .withValues(alpha: 0.15),
                    child: Text(
                      s.speaker.isNotEmpty ? s.speaker.characters.first.toUpperCase() : '?',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _palette[speakers.indexOf(s.speaker) % _palette.length]),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          children: [
                            Text(s.speaker,
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: _palette[speakers.indexOf(s.speaker) %
                                        _palette.length])),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(s.timestamp,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontFeatures: [FontFeature.tabularFigures()])),
                            ),
                            if (s.language.isNotEmpty)
                              Text(s.language,
                                  style: TextStyle(fontSize: 11, color: cs.outline)),
                            if (_emoji(s.emotion).isNotEmpty) Text(_emoji(s.emotion)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SelectableText(s.content, style: const TextStyle(height: 1.45)),
                      ],
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
