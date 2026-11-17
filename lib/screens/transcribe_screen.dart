import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/app_state.dart';
import '../services/audio_io.dart';
import '../services/platform_services.dart';
import '../services/provider_catalog.dart';
import '../widgets/model_picker.dart';
import '../widgets/recorder_panel.dart';
import 'report_view.dart';

class TranscribeScreen extends StatefulWidget {
  final VoidCallback onOpenSettings;
  const TranscribeScreen({super.key, required this.onOpenSettings});

  @override
  State<TranscribeScreen> createState() => _TranscribeScreenState();
}

class _TranscribeScreenState extends State<TranscribeScreen> {
  int _mode = 1; // 0 = record, 1 = upload

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset('assets/logo.png', width: 36, height: 36),
            ),
            const SizedBox(width: 10),
            ShaderMask(
              shaderCallback: (r) => const LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
              ).createShader(r),
              child: const Text('EchoScript AI',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      fontSize: 21)),
            ),
          ],
        ),
        actions: [
          if (s.status == AppStatus.success)
            IconButton(
              tooltip: 'Начать заново',
              onPressed: s.reset,
              icon: const Icon(Icons.restart_alt),
            ),
        ],
      ),
      body: SafeArea(
        child: s.status == AppStatus.success && s.results.isNotEmpty
            ? ReportView(results: s.results, onReset: s.reset)
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  _ModelBar(onOpenSettings: widget.onOpenSettings),
                  const SizedBox(height: 16),
                  if (s.status == AppStatus.error && s.error != null) ...[
                    _ErrorCard(
                      message: s.error!,
                      canRetry: s.queue.isNotEmpty,
                      onRetry: s.transcribeAll,
                      onSettings: widget.onOpenSettings,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (s.status == AppStatus.processing)
                    const _ProcessingCard()
                  else ...[
                    if (s.keys.isEmpty)
                      _NoKeysCard(onOpenSettings: widget.onOpenSettings)
                    else ...[
                      Text('Превратите аудио в точный текст',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(
                        'Разделение по спикерам, таймкоды, определение языка и CRM-отчёт по переговорам.',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(
                              value: 0,
                              icon: Icon(Icons.mic_none),
                              label: Text('Записать')),
                          ButtonSegment(
                              value: 1,
                              icon: Icon(Icons.upload_file),
                              label: Text('Файлы')),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (v) =>
                            setState(() => _mode = v.first),
                        style: const ButtonStyle(
                            visualDensity: VisualDensity.comfortable),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: _mode == 0
                              ? RecorderPanel(
                                  onRecorded: (a) => s.addAudio([a]))
                              : _UploadPanel(onPick: () async {
                                  final items = await FileServices.pickAudio();
                                  if (items.isNotEmpty) s.addAudio(items);
                                }),
                        ),
                      ),
                    ],
                    if (s.queue.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _QueueList(),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: s.isReady ? s.transcribeAll : null,
                        icon: const Icon(Icons.auto_awesome),
                        label: Text(
                            'Сгенерировать расшифровку (${s.queue.length})'),
                      ),
                      if (!s.isReady)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('Добавьте API-ключ во вкладке «Ключи и модели»',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: cs.error)),
                        ),
                    ],
                  ],
                ],
              ),
      ),
    );
  }
}

/// Compact selector: active key + model, switchable right from the main screen.
class _ModelBar extends StatelessWidget {
  final VoidCallback onOpenSettings;
  const _ModelBar({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final key = s.transcribeKey;
    final info = key == null ? null : ProviderCatalog.of(key.provider);
    final busy = s.status == AppStatus.processing;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: (info?.color ?? cs.outline).withValues(alpha: 0.15),
              child: Icon(info?.icon ?? Icons.key_off,
                  color: info?.color ?? cs.outline, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: busy || key == null
                    ? null
                    : () => showModelPickerSheet(
                          context,
                          keyEntry: key,
                          title: 'Модель для расшифровки',
                          options: info!.transcribeModels,
                          selected: s.settings.transcribeModel,
                          onSelected: (m) => s.updateSettings(
                              s.settings.copyWith(transcribeModel: m)),
                        ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      key == null ? 'Нет API-ключа' : '${info!.shortName} · ${key.label}',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            key == null ? 'Добавьте ключ' : s.settings.transcribeModel,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (key != null)
                          Icon(Icons.arrow_drop_down, color: cs.onSurfaceVariant),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (s.keys.length > 1)
              PopupMenuButton<ApiKeyEntry>(
                enabled: !busy,
                tooltip: 'Сменить ключ',
                icon: const Icon(Icons.swap_horiz),
                onSelected: s.selectTranscribeKey,
                itemBuilder: (_) => [
                  for (final k in s.keys)
                    PopupMenuItem(
                      value: k,
                      child: Row(children: [
                        Icon(ProviderCatalog.of(k.provider).icon,
                            size: 18, color: ProviderCatalog.of(k.provider).color),
                        const SizedBox(width: 10),
                        Expanded(child: Text('${k.label}  (${k.maskedKey})')),
                        if (k.id == key?.id)
                          Icon(Icons.check, size: 18, color: cs.primary),
                      ]),
                    ),
                ],
              ),
            IconButton(
              tooltip: 'Настройки',
              onPressed: onOpenSettings,
              icon: const Icon(Icons.tune),
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadPanel extends StatelessWidget {
  final VoidCallback onPick;
  const _UploadPanel({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = context.watch<AppState>();
    final note = s.transcribeKey == null
        ? null
        : ProviderCatalog.of(s.transcribeKey!.provider).maxFileNote;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: cs.primary.withValues(alpha: 0.35), width: 1.5),
          color: cs.primary.withValues(alpha: 0.04),
        ),
        child: Column(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: cs.primaryContainer,
              child: Icon(Icons.cloud_upload_outlined,
                  size: 30, color: cs.onPrimaryContainer),
            ),
            const SizedBox(height: 14),
            const Text('Выберите аудиофайлы',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            Text(
              'MP3, M4A, WAV, OGG, OPUS, AAC, FLAC, WEBM, MP4\nМожно выбрать несколько файлов',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Text(
              'Совет: в «Диктофоне» Samsung или Telegram нажмите «Поделиться» → EchoScript AI',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.primary, fontSize: 12),
            ),
            if (note != null) ...[
              const SizedBox(height: 6),
              Text(note,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }
}

class _QueueList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < s.queue.length; i++)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.secondaryContainer,
                child: Icon(Icons.audio_file, color: cs.onSecondaryContainer),
              ),
              title: Text(s.queue[i].name,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text([
                formatBytes(s.queue[i].size),
                if (s.queue[i].duration != null)
                  formatDuration(s.queue[i].duration!),
              ].join(' · ')),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => s.removeAudio(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProcessingCard extends StatelessWidget {
  const _ProcessingCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final total = s.queue.length;
    final idx = s.processingIndex < 0 ? 0 : s.processingIndex;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            SizedBox(
              width: 86,
              height: 86,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 86,
                    height: 86,
                    child: CircularProgressIndicator(
                        strokeWidth: 5,
                        backgroundColor: cs.primaryContainer),
                  ),
                  Icon(Icons.auto_awesome, color: cs.primary, size: 30),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text(
              total > 1 ? 'Анализ файла ${idx + 1} из $total...' : 'Анализ аудио...',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(idx < total ? s.queue[idx].name : '',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 10),
            Text(s.progressStep,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: cs.primary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: total == 0 ? null : (idx + 0.5) / total,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 14),
            Text(
                'Прошло времени: ${formatDuration(Duration(seconds: s.elapsed))}',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              'Экран не погаснет до завершения. Длинные записи могут обрабатываться несколько минут.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: s.cancel, child: const Text('Отменить')),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final bool canRetry;
  final VoidCallback onRetry;
  final VoidCallback onSettings;
  const _ErrorCard(
      {required this.message,
      required this.canRetry,
      required this.onRetry,
      required this.onSettings});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF451A03) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: dark ? const Color(0xFF92400E) : const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706)),
              const SizedBox(width: 10),
              Expanded(
                child: SelectableText(message,
                    style: TextStyle(
                        color: dark
                            ? const Color(0xFFFDE68A)
                            : const Color(0xFF78350F))),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                  onPressed: onSettings,
                  child: const Text('Сменить ключ / модель')),
              if (canRetry)
                FilledButton.tonal(
                    onPressed: onRetry, child: const Text('Повторить')),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoKeysCard extends StatelessWidget {
  final VoidCallback onOpenSettings;
  const _NoKeysCard({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.vpn_key_outlined, size: 48, color: cs.primary),
            const SizedBox(height: 14),
            Text('Добавьте API-ключ',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Приложение работает напрямую с нейросетями — без сервера. Подойдёт ключ Google Gemini (бесплатный), OpenAI, Groq, OpenRouter или любой OpenAI-совместимый.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.add),
              label: const Text('Добавить ключ'),
            ),
          ],
        ),
      ),
    );
  }
}
