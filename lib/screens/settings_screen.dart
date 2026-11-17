import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/app_state.dart';
import '../services/platform_services.dart';
import '../services/provider_catalog.dart';
import '../widgets/model_picker.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final st = s.settings;
    final tk = s.transcribeKey;
    final tInfo = tk == null ? null : ProviderCatalog.of(tk.provider);
    final ak = s.analysisKey;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ключи и модели',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'import_file') {
                final text = await FileServices.pickTextFile();
                if (text != null && context.mounted) {
                  final n = await s.importKeys(text);
                  if (context.mounted) _snack(context, 'Импортировано ключей: $n');
                }
              } else if (v == 'export') {
                await FileServices.shareText(
                    s.exportKeysJson(), 'echoscript_keys.json',
                    mime: 'application/json');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'import_file',
                  child: ListTile(
                      leading: Icon(Icons.file_open_outlined),
                      title: Text('Импорт ключей из файла'),
                      subtitle: Text('.env, .txt или .json'))),
              PopupMenuItem(
                  value: 'export',
                  child: ListTile(
                      leading: Icon(Icons.backup_outlined),
                      title: Text('Резервная копия ключей'))),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // ─────────── Keys ───────────
          _Header('API-ключи', trailing: '${s.keys.length}'),
          if (s.keys.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Ключей пока нет. Добавьте один или несколько — приложение может автоматически переключаться между ключами одного провайдера при исчерпании квоты.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            ),
          for (final k in s.keys) _KeyTile(entry: k),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => showKeyEditor(context),
                icon: const Icon(Icons.add),
                label: const Text('Добавить ключ'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _bulkImport(context),
                icon: const Icon(Icons.playlist_add),
                label: const Text('Вставить список'),
              ),
            ),
          ]),

          // ─────────── Models ───────────
          if (tk != null) ...[
            const _Header('Расшифровка'),
            Card(
              child: Column(children: [
                ListTile(
                  leading: Icon(tInfo!.icon, color: tInfo.color),
                  title: const Text('Ключ'),
                  subtitle: Text('${tInfo.name} · ${tk.label}'),
                  trailing: const Icon(Icons.expand_more),
                  onTap: () => _pickKey(context, s.keys, tk.id, s.selectTranscribeKey),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.memory),
                  title: const Text('Модель'),
                  subtitle: Text(st.transcribeModel),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showModelPickerSheet(context,
                      keyEntry: tk,
                      title: 'Модель для расшифровки',
                      options: tInfo.transcribeModels,
                      selected: st.transcribeModel,
                      onSelected: (m) =>
                          s.updateSettings(st.copyWith(transcribeModel: m))),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Резервная модель'),
                  subtitle: Text(st.fallbackModel.isEmpty
                      ? 'Не используется'
                      : '${st.fallbackModel} — при перегрузке или таймауте'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showModelPickerSheet(context,
                      keyEntry: tk,
                      title: 'Резервная модель',
                      options: tInfo.transcribeModels,
                      selected: st.fallbackModel,
                      allowNone: true,
                      onSelected: (m) =>
                          s.updateSettings(st.copyWith(fallbackModel: m))),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.autorenew),
                  title: const Text('Ротация ключей'),
                  subtitle: Text(
                      'При ошибке квоты (429) пробовать другие ключи ${tInfo.shortName}'),
                  value: st.rotateKeys,
                  onChanged: (v) => s.updateSettings(st.copyWith(rotateKeys: v)),
                ),
              ]),
            ),
            if (s.needsAnalysisStep) ...[
              const _Header('Анализ текста (спикеры, резюме, CRM)'),
              Card(
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: Text(
                      '${tInfo.shortName} распознаёт речь, а вторая модель размечает спикеров и составляет отчёт.',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    ),
                  ),
                  ListTile(
                    leading: Icon(
                        ak == null ? Icons.key_off : ProviderCatalog.of(ak.provider).icon,
                        color: ak == null ? cs.outline : ProviderCatalog.of(ak.provider).color),
                    title: const Text('Ключ для анализа'),
                    subtitle: Text(ak == null
                        ? 'Не выбран — будет только сырой текст'
                        : '${ProviderCatalog.of(ak.provider).name} · ${ak.label}'),
                    trailing: const Icon(Icons.expand_more),
                    onTap: () => _pickKey(
                      context,
                      s.keys
                          .where((k) => ProviderCatalog.of(k.provider).canAnalyzeText)
                          .toList(),
                      ak?.id,
                      (k) => s.updateSettings(st.copyWith(
                        analysisKeyId: k.id,
                        analysisModel: ProviderCatalog.of(k.provider).chatModels.isNotEmpty
                            ? ProviderCatalog.of(k.provider).chatModels.first.id
                            : st.analysisModel,
                      )),
                    ),
                  ),
                  if (ak != null) ...[
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.psychology_outlined),
                      title: const Text('Модель анализа'),
                      subtitle: Text(st.analysisModel.isEmpty ? 'Не выбрана' : st.analysisModel),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showModelPickerSheet(context,
                          keyEntry: ak,
                          title: 'Модель анализа',
                          options: ProviderCatalog.of(ak.provider).chatModels,
                          selected: st.analysisModel,
                          onSelected: (m) =>
                              s.updateSettings(st.copyWith(analysisModel: m))),
                    ),
                  ],
                ]),
              ),
            ],
          ],

          // ─────────── Output ───────────
          const _Header('Отчёт'),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.translate),
                title: const Text('Язык отчёта'),
                subtitle: Text(st.outputLanguage),
                trailing: const Icon(Icons.expand_more),
                onTap: () async {
                  const langs = ['русский', 'English', 'українська', 'Deutsch', 'español', 'français', 'қазақ тілі'];
                  final v = await showModalBottomSheet<String>(
                    context: context,
                    showDragHandle: true,
                    builder: (c) => SafeArea(
                      child: ListView(shrinkWrap: true, children: [
                        for (final l in langs)
                          ListTile(
                            title: Text(l),
                            trailing: l == st.outputLanguage
                                ? Icon(Icons.check, color: cs.primary)
                                : null,
                            onTap: () => Navigator.pop(c, l),
                          ),
                      ]),
                    ),
                  );
                  if (v != null) s.updateSettings(st.copyWith(outputLanguage: v));
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.business_center_outlined),
                title: const Text('CRM-отчёт по переговорам'),
                subtitle: const Text('Ключевые моменты, боли клиента, следующие шаги'),
                value: st.enableCrm,
                onChanged: (v) => s.updateSettings(st.copyWith(enableCrm: v)),
              ),
              ListTile(
                leading: const Icon(Icons.people_outline),
                title: const Text('Подсказка о спикерах'),
                subtitle: Text(st.speakerHint.isEmpty
                    ? 'Напр.: «Менеджер Анна и клиент Сергей»'
                    : st.speakerHint),
                onTap: () async {
                  final v = await _editText(context, 'Подсказка о спикерах',
                      st.speakerHint, 'Менеджер Анна и клиент Сергей');
                  if (v != null) s.updateSettings(st.copyWith(speakerHint: v));
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: const Text('Дополнительные инструкции'),
                subtitle: Text(st.customInstructions.isEmpty
                    ? 'Свои требования к анализу'
                    : st.customInstructions,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () async {
                  final v = await _editText(context, 'Дополнительные инструкции',
                      st.customInstructions,
                      'Например: выдели упомянутые цены и сроки', maxLines: 5);
                  if (v != null) s.updateSettings(st.copyWith(customInstructions: v));
                },
              ),
            ]),
          ),

          const _Header('Оформление'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'system', label: Text('Авто'), icon: Icon(Icons.brightness_auto)),
                  ButtonSegment(value: 'light', label: Text('Светлая'), icon: Icon(Icons.light_mode)),
                  ButtonSegment(value: 'dark', label: Text('Тёмная'), icon: Icon(Icons.dark_mode)),
                ],
                selected: {st.themeMode},
                onSelectionChanged: (v) =>
                    s.updateSettings(st.copyWith(themeMode: v.first)),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Ключи хранятся только на этом устройстве и отправляются напрямую провайдеру ИИ. Используя приложение, вы подтверждаете, что обладаете правами на загружаемые записи.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: cs.outline),
          ),
        ],
      ),
    );
  }

  static void _snack(BuildContext c, String t) =>
      ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(t)));

  static Future<String?> _editText(
      BuildContext context, String title, String initial, String hint,
      {int maxLines = 2}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          maxLines: maxLines,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Сохранить')),
        ],
      ),
    );
  }

  static Future<void> _pickKey(BuildContext context, List<ApiKeyEntry> keys,
      String? selected, ValueChanged<ApiKeyEntry> onPick) async {
    if (keys.isEmpty) {
      _snack(context, 'Нет подходящих ключей. Добавьте ключ Gemini, OpenAI, Groq или OpenRouter.');
      return;
    }
    final cs = Theme.of(context).colorScheme;
    final v = await showModalBottomSheet<ApiKeyEntry>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final k in keys)
            ListTile(
              leading: Icon(ProviderCatalog.of(k.provider).icon,
                  color: ProviderCatalog.of(k.provider).color),
              title: Text(k.label),
              subtitle: Text('${ProviderCatalog.of(k.provider).name} · ${k.maskedKey}'),
              trailing: k.id == selected ? Icon(Icons.check_circle, color: cs.primary) : null,
              onTap: () => Navigator.pop(c, k),
            ),
        ]),
      ),
    );
    if (v != null) onPick(v);
  }

  static Future<void> _bulkImport(BuildContext context) async {
    final c = TextEditingController();
    final s = context.read<AppState>();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Вставить ключи списком'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'Вставьте один или несколько ключей (по строке), содержимое .env или JSON-резервную копию. Провайдер определяется автоматически по префиксу (AIza…, sk-…, gsk_…, sk-or-…).',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            maxLines: 6,
            minLines: 4,
            decoration: const InputDecoration(
                hintText: 'GEMINI_API_KEY=AIza...\ngsk_...\nsk-...'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Импорт')),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    final n = await s.importKeys(text);
    if (context.mounted) {
      _snack(context, n == 0 ? 'Ключи не найдены или уже добавлены' : 'Добавлено ключей: $n');
    }
  }
}

class _Header extends StatelessWidget {
  final String text;
  final String? trailing;
  const _Header(this.text, {this.trailing});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(children: [
        Expanded(
          child: Text(text.toUpperCase(),
              style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w800,
                  color: cs.primary)),
        ),
        if (trailing != null)
          Text(trailing!, style: TextStyle(color: cs.outline, fontSize: 12)),
      ]),
    );
  }
}

class _KeyTile extends StatelessWidget {
  final ApiKeyEntry entry;
  const _KeyTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final info = ProviderCatalog.of(entry.provider);
    final cs = Theme.of(context).colorScheme;
    final active = s.settings.transcribeKeyId == entry.id;
    final usedForAnalysis = s.needsAnalysisStep && s.settings.analysisKeyId == entry.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
              color: active ? cs.primary : cs.outlineVariant.withValues(alpha: 0.6),
              width: active ? 1.6 : 1),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
          leading: CircleAvatar(
            backgroundColor: info.color.withValues(alpha: 0.14),
            child: Icon(info.icon, color: info.color),
          ),
          title: Text(entry.label, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${info.name} · ${entry.maskedKey}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              if (active || usedForAnalysis)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(spacing: 6, children: [
                    if (active) _chip(context, 'Расшифровка'),
                    if (usedForAnalysis) _chip(context, 'Анализ'),
                  ]),
                ),
            ],
          ),
          onTap: () => s.selectTranscribeKey(entry),
          trailing: PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'use':
                  s.selectTranscribeKey(entry);
                  break;
                case 'test':
                  final m = ScaffoldMessenger.of(context);
                  m.showSnackBar(const SnackBar(content: Text('Проверка ключа...')));
                  try {
                    final r = await s.ai.testKey(entry);
                    await s.fetchModels(entry);
                    m
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(content: Text('✅ $r')));
                  } catch (e) {
                    m
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(
                          content: Text('❌ $e'), duration: const Duration(seconds: 6)));
                  }
                  break;
                case 'edit':
                  showKeyEditor(context, existing: entry);
                  break;
                case 'delete':
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Удалить ключ?'),
                      content: Text(entry.label),
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
                  if (ok == true) s.removeKey(entry.id);
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'use', child: Text('Использовать для расшифровки')),
              PopupMenuItem(value: 'test', child: Text('Проверить ключ')),
              PopupMenuItem(value: 'edit', child: Text('Изменить')),
              PopupMenuItem(value: 'delete', child: Text('Удалить')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String t) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: cs.primaryContainer, borderRadius: BorderRadius.circular(8)),
      child: Text(t, style: TextStyle(fontSize: 11, color: cs.onPrimaryContainer)),
    );
  }
}

/// Add / edit key dialog.
Future<void> showKeyEditor(BuildContext context, {ApiKeyEntry? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _KeyEditor(existing: existing),
  );
}

class _KeyEditor extends StatefulWidget {
  final ApiKeyEntry? existing;
  const _KeyEditor({this.existing});
  @override
  State<_KeyEditor> createState() => _KeyEditorState();
}

class _KeyEditorState extends State<_KeyEditor> {
  late ProviderType _provider = widget.existing?.provider ?? ProviderType.gemini;
  late final _key = TextEditingController(text: widget.existing?.key ?? '');
  late final _label = TextEditingController(text: widget.existing?.label ?? '');
  late final _url = TextEditingController(text: widget.existing?.baseUrl ?? '');
  late final _fid = TextEditingController(text: widget.existing?.functionId ?? '');
  bool _obscure = true;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void dispose() {
    _key.dispose();
    _label.dispose();
    _url.dispose();
    _fid.dispose();
    super.dispose();
  }

  ApiKeyEntry _draft() => ApiKeyEntry(
        id: widget.existing?.id ?? 'draft',
        provider: _provider,
        label: _label.text.trim(),
        key: _key.text.trim(),
        baseUrl: _url.text.trim().isEmpty ? null : _url.text.trim(),
        functionId: _fid.text.trim().isEmpty ? null : _fid.text.trim(),
      );

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final r = await context.read<AppState>().ai.testKey(_draft());
      _testOk = true;
      _testResult = r;
    } catch (e) {
      _testOk = false;
      _testResult = e.toString();
    }
    if (mounted) setState(() => _testing = false);
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    if (_key.text.trim().isEmpty) return;
    if (_provider == ProviderType.custom && _url.text.trim().length < 10) {
      setState(() {
        _testOk = false;
        _testResult = 'Укажите Base URL, например https://api.example.com/v1';
      });
      return;
    }
    if (widget.existing != null) {
      await s.updateKey(widget.existing!.copyWith(
        provider: _provider,
        key: _key.text.trim(),
        label: _label.text.trim().isEmpty ? widget.existing!.label : _label.text.trim(),
        baseUrl: _url.text.trim(),
        functionId: _fid.text.trim(),
      ));
    } else {
      final e = await s.addKey(
        provider: _provider,
        key: _key.text,
        label: _label.text,
        baseUrl: _url.text,
        functionId: _fid.text,
      );
      if (s.keys.length == 1) await s.selectTranscribeKey(e);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final info = ProviderCatalog.of(_provider);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'Новый API-ключ' : 'Изменить ключ',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in ProviderCatalog.all)
                  ChoiceChip(
                    avatar: Icon(p.icon, size: 18, color: p.color),
                    label: Text(p.shortName),
                    selected: _provider == p.type,
                    onSelected: (_) => setState(() {
                      _provider = p.type;
                      _testResult = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _key,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (v) {
                final d = ProviderCatalog.detect(v);
                if (d != null && d != _provider && widget.existing == null) {
                  setState(() => _provider = d);
                }
              },
              decoration: InputDecoration(
                labelText: 'API-ключ',
                hintText: info.keyHint,
                prefixIcon: const Icon(Icons.key),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _label,
              decoration: const InputDecoration(
                labelText: 'Название (необязательно)',
                hintText: 'Рабочий, Личный, Резервный...',
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            if (_provider == ProviderType.custom ||
                _provider == ProviderType.openai) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: _provider == ProviderType.custom
                      ? 'Base URL (OpenAI-совместимый)'
                      : 'Base URL (необязательно, прокси)',
                  hintText: _provider == ProviderType.custom
                      ? 'https://api.example.com/v1'
                      : info.defaultBaseUrl,
                  prefixIcon: const Icon(Icons.link),
                ),
              ),
            ],
            if (_provider == ProviderType.nvidia) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _fid,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Function ID Whisper (необязательно)',
                  hintText: ProviderCatalog.nvidiaWhisperFunctionId,
                  prefixIcon: Icon(Icons.fingerprint),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF76B900).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Как получить ключ: откройте build.nvidia.com/openai/whisper-large-v3 → войдите → «Get API Key» → скопируйте ключ nvapi-… и вставьте сюда. '
                  'Whisper распознаёт речь, а модель анализа (DeepSeek, Kimi, Nemotron — тем же ключом) делает резюме и CRM-отчёт. '
                  'Function ID менять не нужно, если NVIDIA его не обновит.',
                  style: TextStyle(fontSize: 12.5, height: 1.4),
                ),
              ),
            ],
            if (info.keyUrl.isNotEmpty) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => launchUrl(Uri.parse(info.keyUrl),
                      mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text('Получить ключ ${info.shortName}'),
                ),
              ),
            ],
            if (_testResult != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _testOk
                      ? const Color(0xFF10B981).withValues(alpha: 0.12)
                      : cs.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_testResult!,
                    style: TextStyle(
                        color: _testOk ? const Color(0xFF047857) : cs.onErrorContainer)),
              ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing || _key.text.trim().isEmpty ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering),
                  label: const Text('Проверить'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check),
                  label: const Text('Сохранить'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
