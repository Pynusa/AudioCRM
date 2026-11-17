import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/amo_service.dart';
import '../services/app_state.dart';
import '../services/audio_io.dart';
import '../services/call_bridge.dart';
import 'amo_settings_screen.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String fmtDate(DateTime d) =>
    '${_two(d.day)}.${_two(d.month)} ${_two(d.hour)}:${_two(d.minute)}';

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> with WidgetsBindingObserver {
  AmoSettings _amo = AmoSettings();
  bool _granted = false;
  List<CallEntry> _calls = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<void> _init() async {
    _amo = await AmoSettings.load();
    await _reload();
  }

  Future<void> _reload() async {
    try {
      _granted = await CallBridge.hasPermissions();
      if (_granted) _calls = await CallBridge.recentCalls(50);
      _error = null;
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() {});
  }

  Future<void> _openSettings() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => AmoSettingsScreen(settings: _amo)));
    if (mounted) setState(() {});
  }

  Future<void> _open(CallEntry c) async {
    if (!_amo.ready) {
      await _openSettings();
      return;
    }
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => CallResultScreen(call: c, settings: _amo)));
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (!_granted) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Нужен доступ к журналу звонков, записям и уведомлениям.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  await CallBridge.requestPermissions();
                  await _reload();
                },
                child: const Text('Разрешить'),
              ),
            ],
          ),
        ),
      );
    } else if (_error != null) {
      body = Center(child: Text(_error!));
    } else {
      body = RefreshIndicator(
        onRefresh: _reload,
        child: ListView.separated(
          itemCount: _calls.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final c = _calls[i];
            return ListTile(
              leading: Icon(switch (c.type) {
                2 => Icons.call_made,
                3 || 5 => Icons.call_missed,
                _ => Icons.call_received,
              }),
              title: Text(c.name.isEmpty ? c.number : '${c.name} · ${c.number}'),
              subtitle: Text(
                  '${c.typeLabel} · ${fmtDate(c.date)} · ${formatDuration(Duration(seconds: c.duration))}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(c),
            );
          },
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Звонки'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
          IconButton(
              onPressed: _openSettings, icon: const Icon(Icons.settings_outlined)),
        ],
      ),
      body: body,
    );
  }
}

class CallResultScreen extends StatefulWidget {
  final CallEntry call;
  final AmoSettings settings;
  const CallResultScreen({super.key, required this.call, required this.settings});

  @override
  State<CallResultScreen> createState() => _CallResultScreenState();
}

class _CallResultScreenState extends State<CallResultScreen> {
  late final AmoService _amo = AmoService(widget.settings);
  final _text = TextEditingController();
  final _leadName = TextEditingController();
  final _contactName = TextEditingController();
  final _taskText = TextEditingController(text: 'Связаться с клиентом');

  AmoLookup? _found;
  bool _loading = true;
  String? _error;
  bool _newLead = false;
  int? _leadId;
  List<AmoTask> _tasks = [];
  int? _closeTaskId;
  bool _addTask = true;
  late DateTime _due;
  String _transcript = '';
  bool _attach = true;
  String _busy = '';
  final _done = <String>{};
  int? _createdLeadId;

  List<AmoLead> get _openLeads =>
      _found?.leads.where((l) => !l.closed).toList() ?? [];

  @override
  void initState() {
    super.initState();
    final t = DateTime.now().add(const Duration(days: 1));
    _due = DateTime(t.year, t.month, t.day, 10);
    _lookup();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _lookup() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final f = await _amo.findByPhone(widget.call.number);
      _found = f;
      _leadName.text = 'Звонок ${widget.call.number}';
      if (f == null) _contactName.text = widget.call.name;
      if (_openLeads.isEmpty) {
        _newLead = true;
      } else {
        _leadId = _openLeads.first.id;
        await _loadTasks();
      }
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadTasks() async {
    final id = _leadId;
    if (id == null) return;
    _tasks = await _amo.openTasks(id);
    _closeTaskId = _tasks.isEmpty ? null : _tasks.first.id;
  }

  Future<void> _selectLead(int id) async {
    setState(() {
      _leadId = id;
      _tasks = [];
      _closeTaskId = null;
    });
    try {
      await _loadTasks();
    } catch (e) {
      if (mounted) _snack('$e');
    }
    if (mounted) setState(() {});
  }

  Future<RecordingEntry?> _pickRecording(List<RecordingEntry> recs) {
    return showModalBottomSheet<RecordingEntry>(
      context: context,
      builder: (ctx) => recs.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Записи не найдены. Проверьте папку записей в настройках amoCRM.'),
            )
          : ListView(
              children: [
                const ListTile(title: Text('Выберите запись звонка')),
                for (final r in recs.take(30))
                  ListTile(
                    title: Text(r.name),
                    subtitle: Text('${fmtDate(r.date)} · ${formatBytes(r.size)}'),
                    onTap: () => Navigator.pop(ctx, r),
                  ),
              ],
            ),
    );
  }

  Future<void> _transcribe() async {
    final st = context.read<AppState>();
    final key = st.transcribeKey;
    if (key == null) {
      _snack('Добавьте API-ключ на вкладке «Ключи и модели».');
      return;
    }
    setState(() => _busy = 'Поиск записи…');
    try {
      final c = widget.call;
      final recs = await CallBridge.recordings(
          c.date.subtract(const Duration(hours: 12)));
      final folder = widget.settings.recFolder.trim().toLowerCase();
      final inFolder = recs
          .where((r) => folder.isEmpty || r.folder.toLowerCase().contains(folder))
          .toList();
      final from = c.date.subtract(const Duration(seconds: 30));
      final to = c.end.add(const Duration(minutes: 3));
      RecordingEntry? rec;
      for (final r in inFolder) {
        if (!r.date.isBefore(from) && !r.date.isAfter(to)) {
          rec = r;
          break;
        }
      }
      if (rec == null) {
        if (!mounted) return;
        setState(() => _busy = '');
        rec = await _pickRecording(inFolder.isEmpty ? recs : inFolder);
        if (rec == null || !mounted) return;
      }
      setState(() => _busy = 'Подготовка записи…');
      final f = await CallBridge.importRecording(rec.uri);
      final audio = AudioItem(
        name: f.name,
        path: f.path,
        mimeType: f.mime.isEmpty ? mimeFromName(f.name) : f.mime,
        size: await fileLength(f.path),
      );
      final r = await st.ai.transcribe(
        audio: audio,
        key: key,
        rotationKeys: st.keys,
        settings: st.settings,
        analysisKey: st.needsAnalysisStep ? st.analysisKey : null,
        onProgress: (s) {
          if (mounted) setState(() => _busy = s);
        },
        isCanceled: () => !mounted,
      );
      if (!mounted) return;
      final b = StringBuffer();
      final crm = r.crmReport;
      if (crm == null) {
        b.writeln(r.summary);
      } else {
        b.writeln(crm.summary);
        void block(String title, List<String> items) {
          if (items.isEmpty) return;
          b.writeln('\n$title:');
          for (final i in items) {
            b.writeln('• $i');
          }
        }

        block('Ключевые моменты', crm.keyPoints);
        block('Потребности клиента', crm.clientNeeds);
        if (crm.sentiment.isNotEmpty) b.writeln('\nНастроение: ${crm.sentiment}');
        block('Следующие шаги', crm.nextSteps);
      }
      _text.text = b.toString().trim();
      _transcript = r.segments
          .map((s) => '[${s.timestamp}] ${s.speaker}: ${s.content}')
          .join('\n');
      setState(() => _busy = '');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = '');
      _snack('$e');
    }
  }

  Future<void> _pickDue() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_due));
    if (t == null) return;
    setState(() => _due = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      _snack('Введите результат звонка или сделайте транскрибацию.');
      return;
    }
    if (_newLead && _leadName.text.trim().isEmpty) {
      _snack('Введите название сделки.');
      return;
    }
    setState(() => _busy = 'Сохранение в amoCRM…');
    final c = widget.call;
    try {
      var leadId = _newLead ? _createdLeadId : _leadId;
      if (leadId == null) {
        leadId = await _amo.createLead(
          name: _leadName.text.trim(),
          contactId: _found?.contactId,
          contactName: _contactName.text.trim(),
          phone: c.number,
        );
        _createdLeadId = leadId;
      }
      await _amo.saveResult(
        leadId: leadId,
        incoming: c.incoming,
        phone: c.number,
        duration: c.duration,
        at: c.date,
        text: text,
        transcript: _attach ? _transcript : '',
        closeTaskId: _newLead ? null : _closeTaskId,
        taskText: _addTask ? _taskText.text.trim() : '',
        due: _due,
        done: _done,
      );
      if (!mounted) return;
      _snack('Сохранено в amoCRM');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = '');
      _snack('$e');
    }
  }

  Widget _radio(bool on) =>
      Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked);

  Widget _fieldsView(List<AmoField> fields) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final f in fields)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${f.name}: ${f.value}'),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final c = widget.call;
    final theme = Theme.of(context);
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(c.number)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(c.number)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _lookup, child: const Text('Повторить')),
            ]),
          ),
        ),
      );
    }
    final f = _found;
    final open = _openLeads;
    final busy = _busy.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(f?.contactName ?? c.number)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${c.typeLabel} · ${fmtDate(c.date)} · ${formatDuration(Duration(seconds: c.duration))}'),
                  const SizedBox(height: 4),
                  Text(f == null ? 'Номера нет в amoCRM' : f.contactName,
                      style: theme.textTheme.titleMedium),
                  if (f != null) _fieldsView(f.fields),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 12,
            decoration: const InputDecoration(labelText: 'Результат звонка'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: busy ? null : _transcribe,
            icon: const Icon(Icons.graphic_eq),
            label: const Text('Транскрибировать запись'),
          ),
          if (_transcript.isNotEmpty)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Приложить полную расшифровку примечанием'),
              value: _attach,
              onChanged: (v) => setState(() => _attach = v),
            ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            enabled: open.isNotEmpty,
            leading: _radio(!_newLead),
            title: const Text('Добавить в имеющуюся сделку'),
            onTap: open.isEmpty ? null : () => setState(() => _newLead = false),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _radio(_newLead),
            title: const Text('Создать новую сделку'),
            onTap: () => setState(() => _newLead = true),
          ),
          if (!_newLead) ...[
            for (final l in open)
              Card(
                child: ListTile(
                  leading: _radio(l.id == _leadId),
                  title: Text(l.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${l.stage}${l.price > 0 ? ' · ${l.price} ₽' : ''}'),
                      if (l.id == _leadId) _fieldsView(l.fields),
                    ],
                  ),
                  onTap: () => _selectLead(l.id),
                ),
              ),
            const SizedBox(height: 8),
            if (_tasks.isEmpty)
              const Text('Открытых задач нет — результат сохранится примечанием.')
            else ...[
              const Text('Закрыть задачу с этим результатом:'),
              for (final t in _tasks)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _radio(t.id == _closeTaskId),
                  title: Text(t.text.isEmpty ? 'Задача' : t.text),
                  subtitle: Text('до ${fmtDate(t.due)}'),
                  onTap: () => setState(() => _closeTaskId = t.id),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _radio(_closeTaskId == null),
                title: const Text('Не закрывать, сохранить примечанием'),
                onTap: () => setState(() => _closeTaskId = null),
              ),
            ],
          ] else ...[
            TextField(
              controller: _leadName,
              decoration: const InputDecoration(labelText: 'Название сделки'),
            ),
            if (f == null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _contactName,
                decoration: const InputDecoration(labelText: 'Имя клиента'),
              ),
            ],
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Поставить новую задачу'),
            value: _addTask,
            onChanged: (v) => setState(() => _addTask = v),
          ),
          if (_addTask) ...[
            TextField(
              controller: _taskText,
              decoration: const InputDecoration(labelText: 'Текст задачи'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text('Срок: ${fmtDate(_due)}'),
              onTap: _pickDue,
            ),
          ],
          const SizedBox(height: 16),
          if (busy) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(_busy),
            const SizedBox(height: 8),
          ],
          FilledButton(
            onPressed: busy ? null : _save,
            child: const Text('Сохранить в amoCRM'),
          ),
        ],
      ),
    );
  }
}
