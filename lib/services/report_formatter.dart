import '../models/models.dart';

/// Port of clipboardService.ts / exportService.ts from the original web app.
class ReportFormatter {
  static String _date() {
    final n = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(n.day)}.${p(n.month)}.${n.year}, ${p(n.hour)}:${p(n.minute)}';
  }

  static String _name(TranscriptionResult r, int i) =>
      r.fileName.isNotEmpty ? r.fileName : 'Файл ${i + 1}';

  static String fullTranscript(List<TranscriptionResult> results) {
    return results.asMap().entries.map((e) {
      final r = e.value;
      final dialogue = r.segments
          .map((s) => '[${s.timestamp}] ${s.speaker}: ${s.content}')
          .join('\n');
      return results.length > 1
          ? '=== ${_name(r, e.key)} ===\n\n$dialogue'
          : dialogue;
    }).join('\n\n${'—' * 40}\n\n');
  }

  static String singleTranscript(TranscriptionResult r) => r.segments
      .map((s) => '[${s.timestamp}] ${s.speaker}: ${s.content}')
      .join('\n');

  static String fullReport(List<TranscriptionResult> results) {
    final p = <String>[];
    p.add('КОНСОЛИДИРОВАННЫЙ ОТЧЁТ ПО ПЕРЕГОВОРАМ (${results.length} файл(ов))');
    p.add('=' * 50);
    p.add('\n### 1. ОБЩЕЕ РЕЗЮМЕ ПЕРЕГОВОРОВ');
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      p.add('\n[${_name(r, i)}]');
      if (r.summary.isNotEmpty) p.add(r.summary);
      final c = r.crmReport;
      if (c != null && c.summary.isNotEmpty && c.summary != r.summary) {
        p.add('CRM-резюме: ${c.summary}');
      }
      if (c != null && c.sentiment.isNotEmpty) {
        p.add('Настроение клиента: ${c.sentiment}');
      }
    }
    void section(String title, List<String> Function(CrmReport) f, String bullet) {
      p.add('\n\n$title');
      for (var i = 0; i < results.length; i++) {
        final c = results[i].crmReport;
        if (c == null || f(c).isEmpty) continue;
        p.add('\n[${_name(results[i], i)}]');
        for (final x in f(c)) {
          p.add('$bullet $x');
        }
      }
    }

    section('### 2. КЛЮЧЕВЫЕ МОМЕНТЫ', (c) => c.keyPoints, '•');
    section('### 3. ПОТРЕБНОСТИ И БОЛИ КЛИЕНТОВ', (c) => c.clientNeeds, '→');
    section('### 4. СЛЕДУЮЩИЕ ШАГИ И ЗАДАЧИ', (c) => c.nextSteps, '✓');
    p.add('\n\n### 5. ПОЛНАЯ РАСШИФРОВКА РЕПЛИК');
    p.add('=' * 50);
    for (var i = 0; i < results.length; i++) {
      p.add('\n[${_name(results[i], i)}]');
      for (final s in results[i].segments) {
        p.add('[${s.timestamp}] ${s.speaker}: ${s.content}');
      }
    }
    return p.join('\n');
  }

  static String markdown(List<TranscriptionResult> results, {bool onlyDialogue = false}) {
    final l = <String>[];
    if (onlyDialogue) {
      l.add('# Расшифровка переговоров');
      l.add('*Дата экспорта: ${_date()}* | *Всего файлов: ${results.length}*\n');
      for (var i = 0; i < results.length; i++) {
        l.add('## ${_name(results[i], i)}\n');
        for (final s in results[i].segments) {
          l.add('- **`${s.timestamp}` ${s.speaker}:** ${s.content}');
        }
        l.add('');
      }
      return l.join('\n');
    }
    l.add('# Консолидированный отчёт по переговорам');
    l.add('*Дата экспорта: ${_date()}* | *Всего файлов: ${results.length}*\n');
    l.add('## 1. Общее резюме переговоров');
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      l.add('### 📄 ${_name(r, i)}');
      if (r.summary.isNotEmpty) l.add('> ${r.summary}\n');
      final c = r.crmReport;
      if (c != null && c.summary.isNotEmpty && c.summary != r.summary) {
        l.add('**Резюме для CRM:** ${c.summary}\n');
      }
      if (c != null && c.sentiment.isNotEmpty) {
        l.add('**Настроение клиента:** ${c.sentiment}\n');
      }
    }
    void sec(String title, List<String> Function(CrmReport) f, String prefix) {
      l.add(title);
      for (var i = 0; i < results.length; i++) {
        final c = results[i].crmReport;
        if (c == null || f(c).isEmpty) continue;
        l.add('### 📄 ${_name(results[i], i)}');
        for (final x in f(c)) {
          l.add('$prefix$x');
        }
        l.add('');
      }
    }

    sec('## 2. Ключевые моменты', (c) => c.keyPoints, '- ');
    sec('## 3. Потребности и боли клиентов', (c) => c.clientNeeds, '- ⚠️ ');
    sec('## 4. Рекомендуемые следующие шаги', (c) => c.nextSteps, '- [ ] ');
    l.add('## 5. Полная расшифровка диалогов');
    for (var i = 0; i < results.length; i++) {
      l.add('### 📄 ${_name(results[i], i)}');
      l.add('*Всего реплик: ${results[i].segments.length}*\n');
      for (final s in results[i].segments) {
        l.add('- **`${s.timestamp}` ${s.speaker}:** ${s.content}');
      }
      l.add('');
    }
    return l.join('\n');
  }

  static String plainText(List<TranscriptionResult> results, {bool onlyDialogue = false}) {
    if (onlyDialogue) {
      return 'РАСШИФРОВКА ПЕРЕГОВОРОВ\nДата экспорта: ${_date()}\nВсего файлов: ${results.length}\n${'=' * 60}\n\n${fullTranscript(results)}';
    }
    return 'Дата экспорта: ${_date()}\n\n${fullReport(results)}';
  }

  static String fileBaseName(List<TranscriptionResult> results) {
    if (results.length == 1 && results.first.fileName.isNotEmpty) {
      return results.first.fileName.replaceAll(RegExp(r'\.[^/.]+$'), '');
    }
    return 'echoscript_combined';
  }
}
