import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/provider_catalog.dart';
import '../services/proxy.dart';

class ProxyScreen extends StatefulWidget {
  const ProxyScreen({super.key});

  @override
  State<ProxyScreen> createState() => _ProxyScreenState();
}

class _ProxyScreenState extends State<ProxyScreen> {
  late final AppState _s;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _user;
  late final TextEditingController _pass;
  late bool _enabled;
  late Set<String> _hosts;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _s = context.read<AppState>();
    final p = _s.proxy.settings;
    _enabled = p.enabled;
    _hosts = {...p.hosts};
    _host = TextEditingController(text: p.host);
    _port = TextEditingController(text: p.port > 0 ? '${p.port}' : '');
    _user = TextEditingController(text: p.user);
    _pass = TextEditingController(text: p.pass);
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  /// Адрес API → названия ключей, которые к нему обращаются.
  Map<String, String> _targets() {
    final out = <String, String>{};
    for (final k in _s.keys) {
      final base = (k.baseUrl?.trim().isNotEmpty ?? false)
          ? k.baseUrl!.trim()
          : ProviderCatalog.of(k.provider).defaultBaseUrl;
      final h = (Uri.tryParse(base)?.host ?? '').toLowerCase();
      if (h.isEmpty) continue;
      out[h] = out.containsKey(h) ? '${out[h]}, ${k.label}' : k.label;
    }
    return out;
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() => _s.proxy.update(ProxySettings(
        enabled: _enabled,
        host: _host.text.trim(),
        port: int.tryParse(_port.text.trim()) ?? 0,
        user: _user.text.trim(),
        pass: _pass.text,
        hosts: _hosts,
      ));

  Future<void> _test() async {
    setState(() => _busy = true);
    await _save();
    String msg;
    try {
      msg = await _s.proxy.test();
    } catch (e) {
      msg = 'Прокси не отвечает: $e';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(msg);
  }

  @override
  Widget build(BuildContext context) {
    final targets = _targets();
    return Scaffold(
      appBar: AppBar(title: const Text('Прокси-сервер')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Использовать прокси'),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          TextField(
            controller: _host,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
                labelText: 'Адрес прокси', hintText: '123.45.67.89'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _port,
            keyboardType: TextInputType.number,
            decoration:
                const InputDecoration(labelText: 'Порт', hintText: '8080'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _user,
            autocorrect: false,
            decoration:
                const InputDecoration(labelText: 'Логин (если требуется)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: true,
            decoration:
                const InputDecoration(labelText: 'Пароль (если требуется)'),
          ),
          const SizedBox(height: 20),
          const Text('Отправлять через прокси:',
              style: TextStyle(fontWeight: FontWeight.w700)),
          if (targets.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Сначала добавьте API-ключи.'),
            ),
          for (final e in targets.entries)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _hosts.contains(e.key),
              title: Text(e.value),
              subtitle: Text(e.key),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _hosts.add(e.key);
                } else {
                  _hosts.remove(e.key);
                }
              }),
            ),
          const SizedBox(height: 16),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _test,
            child: const Text('Сохранить и проверить прокси'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    final nav = Navigator.of(context);
                    await _save();
                    nav.pop();
                  },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
}
