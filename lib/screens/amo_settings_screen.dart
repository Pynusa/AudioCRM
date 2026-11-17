import 'package:flutter/material.dart';
import '../services/call_bridge.dart';
import '../services/amo_service.dart';

class AmoSettingsScreen extends StatefulWidget {
  final AmoSettings settings;
  const AmoSettingsScreen({super.key, required this.settings});

  @override
  State<AmoSettingsScreen> createState() => _AmoSettingsScreenState();
}

class _AmoSettingsScreenState extends State<AmoSettingsScreen> {
  AmoSettings get s => widget.settings;
  late final _domain = TextEditingController(text: s.domain);
  late final _token = TextEditingController(text: s.token);
  late final _folder = TextEditingController(text: s.recFolder);
  bool _busy = false;

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<T?> _run<T>(Future<T> Function() f) async {
    setState(() => _busy = true);
    try {
      return await f();
    } catch (e) {
      if (mounted) _snack('$e');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<T?> _pick<T>(String title, List<(T, String)> items) =>
      showDialog<T>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(title),
          children: [
            for (final i in items)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, i.$1),
                child: Text(i.$2),
              ),
          ],
        ),
      );

  Future<void> _apply() async {
    s.domain = _domain.text.trim();
    s.token = _token.text.trim();
    s.recFolder = _folder.text.trim();
    await s.save();
  }

  Future<void> _connect() async {
    await _apply();
    final users = await _run(() => AmoService(s).users());
    if (users == null || !mounted) return;
    final id = await _pick<int>('Кто вы?', users);
    if (id == null) return;
    s.userId = id;
    s.userName = users.firstWhere((u) => u.$1 == id).$2;
    await s.save();
    if (mounted) setState(() {});
  }

  Future<void> _pickStage() async {
    await _apply();
    final pipes = await _run(() => AmoService(s).pipelines());
    if (pipes == null || !mounted) return;
    final items = <((int, int), String)>[];
    for (final p in pipes) {
      for (final st
          in (p['_embedded']?['statuses'] as List? ?? const []).whereType<Map>()) {
        if (st['id'] == 142 || st['id'] == 143 || st['type'] == 1) continue;
        items.add(((p['id'] as int, st['id'] as int), '${p['name']} → ${st['name']}'));
      }
    }
    final v = await _pick<(int, int)>('Этап для новых сделок', items);
    if (v == null) return;
    s.pipelineId = v.$1;
    s.statusId = v.$2;
    s.stageName = items.firstWhere((i) => i.$1 == v).$2;
    await s.save();
    if (mounted) setState(() {});
  }

  Future<void> _pickFields(String entity, List<int> target) async {
    await _apply();
    final all = await _run(() => AmoService(s).customFields(entity));
    if (all == null || !mounted) return;
    final sel = {...target};
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Показывать поля'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final f in all)
                  CheckboxListTile(
                    value: sel.contains(f.$1),
                    title: Text(f.$2),
                    onChanged: (v) => setD(() {
                      if (v == true) {
                        sel.add(f.$1);
                      } else {
                        sel.remove(f.$1);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Готово')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    target
      ..clear()
      ..addAll(sel);
    await s.save();
    if (mounted) setState(() {});
  }

  String _count(List<int> l) => l.isEmpty ? 'Все заполненные' : 'Выбрано: ${l.length}';

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (_, __) => _apply(),
      child: Scaffold(
        appBar: AppBar(title: const Text('amoCRM')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_busy) const LinearProgressIndicator(),
            TextField(
              controller: _domain,
              decoration: const InputDecoration(
                  labelText: 'Адрес аккаунта', hintText: 'mycompany.amocrm.ru'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _token,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Долгосрочный токен'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _connect,
              child: const Text('Подключить и выбрать себя'),
            ),
            ListTile(
              title: const Text('Менеджер'),
              subtitle: Text(s.userName.isEmpty ? 'Не выбран' : s.userName),
            ),
            ListTile(
              title: const Text('Этап для новых сделок'),
              subtitle: Text(
                  s.stageName.isEmpty ? 'Первый этап основной воронки' : s.stageName),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : _pickStage,
            ),
            ListTile(
              title: const Text('Поля контакта при звонке'),
              subtitle: Text(_count(s.contactFields)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : () => _pickFields('contacts', s.contactFields),
            ),
            ListTile(
              title: const Text('Поля сделки при звонке'),
              subtitle: Text(_count(s.leadFields)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : () => _pickFields('leads', s.leadFields),
            ),
            ListTile(
              title: const Text('Поля компании на плашке звонка'),
              subtitle: Text(s.companyFields.isEmpty
                  ? 'Только название компании'
                  : 'Выбрано: ${s.companyFields.length}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : () => _pickFields('companies', s.companyFields),
            ),
            ListTile(
              title: const Text('Плашка при входящем звонке'),
              subtitle: const Text('Разрешить показ поверх других приложений'),
              trailing: const Icon(Icons.open_in_new),
              onTap: CallBridge.requestOverlay,
            ),

            TextField(
              controller: _folder,
              decoration: const InputDecoration(
                labelText: 'Папка записей звонков',
                helperText: 'Часть пути, по умолчанию Recordings/Call',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
