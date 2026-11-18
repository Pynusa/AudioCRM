import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProxySettings {
  static const _k = 'proxy_v1';

  bool enabled;
  String host;
  int port;
  String user;
  String pass;

  /// Адреса API, запросы к которым идут через прокси.
  Set<String> hosts;

  ProxySettings({
    this.enabled = false,
    this.host = '',
    this.port = 0,
    this.user = '',
    this.pass = '',
    Set<String>? hosts,
  }) : hosts = hosts ?? {};

  bool get valid => host.trim().isNotEmpty && port > 0;

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'host': host,
        'port': port,
        'user': user,
        'pass': pass,
        'hosts': hosts.toList(),
      };

  static Future<ProxySettings> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_k);
    if (raw == null) return ProxySettings();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return ProxySettings(
        enabled: j['enabled'] as bool? ?? false,
        host: j['host'] as String? ?? '',
        port: (j['port'] as num?)?.toInt() ?? 0,
        user: j['user'] as String? ?? '',
        pass: j['pass'] as String? ?? '',
        hosts: (j['hosts'] as List? ?? const []).map((e) => '$e').toSet(),
      );
    } catch (_) {
      return ProxySettings();
    }
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_k, jsonEncode(toJson()));
  }
}

/// Отправляет запросы к выбранным адресам через прокси, остальные — напрямую.
class ProxyRouter extends http.BaseClient {
  final http.Client _direct = http.Client();
  http.Client? _proxied;
  ProxySettings settings = ProxySettings();

  Future<void> load() async {
    settings = await ProxySettings.load();
    _rebuild();
  }

  Future<void> update(ProxySettings s) async {
    settings = s;
    await s.save();
    _rebuild();
  }

  void _rebuild() {
    _proxied?.close();
    _proxied = null;
    final s = settings;
    if (kIsWeb || !s.enabled || !s.valid) return;
    final auth = s.user.trim().isEmpty ? '' : '${s.user.trim()}:${s.pass}@';
    final target = 'PROXY $auth${s.host.trim()}:${s.port}';
    final hc = HttpClient()
      ..findProxy = ((_) => target)
      ..connectionTimeout = const Duration(seconds: 30);
    _proxied = IOClient(hc);
  }

  bool usesProxy(String host) =>
      _proxied != null && settings.hosts.contains(host.toLowerCase());

  Future<String> test() async {
    final c = _proxied;
    if (c == null) return 'Включите прокси и заполните адрес и порт.';
    final r = await c
        .get(Uri.parse('https://www.google.com/generate_204'))
        .timeout(const Duration(seconds: 20));
    return 'Прокси работает (ответ ${r.statusCode}).';
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!usesProxy(request.url.host)) return _direct.send(request);
    try {
      return await _proxied!.send(request);
    } catch (e) {
      throw http.ClientException('Ошибка прокси-соединения: $e', request.url);
    }
  }
}
