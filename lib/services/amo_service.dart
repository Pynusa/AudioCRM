import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AmoException implements Exception {
  final String message;
  AmoException(this.message);
  @override
  String toString() => message;
}

class AmoSettings {
  static const _k = 'amo_settings_v1';

  String domain;
  String token;
  int? userId;
  String userName;
  int? pipelineId;
  int? statusId;
  String stageName;
  String recFolder;
  List<int> contactFields;
  List<int> leadFields;
  List<int> companyFields;

  AmoSettings({
    this.domain = '',
    this.token = '',
    this.userId,
    this.userName = '',
    this.pipelineId,
    this.statusId,
    this.stageName = '',
    this.recFolder = 'Recordings/Call',
    List<int>? contactFields,
    List<int>? leadFields,
    List<int>? companyFields,
  })  : contactFields = contactFields ?? [],
        leadFields = leadFields ?? [],
        companyFields = companyFields ?? [];

  bool get ready => host.isNotEmpty && token.trim().isNotEmpty && userId != null;

  String get host {
    var d = domain.trim().replaceFirst(RegExp(r'^https?://'), '');
    d = d.split('/').first;
    if (d.isNotEmpty && !d.contains('.')) d = '$d.amocrm.ru';
    return d;
  }

  Map<String, dynamic> toJson() => {
        'domain': domain,
        'token': token,
        'userId': userId,
        'userName': userName,
        'pipelineId': pipelineId,
        'statusId': statusId,
        'stageName': stageName,
        'recFolder': recFolder,
        'contactFields': contactFields,
        'leadFields': leadFields,
        'companyFields': companyFields,
      };

  static Future<AmoSettings> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_k);
    if (raw == null) return AmoSettings();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return AmoSettings(
        domain: j['domain'] as String? ?? '',
        token: j['token'] as String? ?? '',
        userId: j['userId'] as int?,
        userName: j['userName'] as String? ?? '',
        pipelineId: j['pipelineId'] as int?,
        statusId: j['statusId'] as int?,
        stageName: j['stageName'] as String? ?? '',
        recFolder: j['recFolder'] as String? ?? 'Recordings/Call',
        contactFields: List<int>.from(j['contactFields'] as List? ?? const []),
        leadFields: List<int>.from(j['leadFields'] as List? ?? const []),
        companyFields: List<int>.from(j['companyFields'] as List? ?? const []),
      );
    } catch (_) {
      return AmoSettings();
    }
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_k, jsonEncode(toJson()));
  }
}

class AmoField {
  final String name;
  final String value;
  AmoField(this.name, this.value);
}

class AmoLead {
  final int id;
  final String name;
  final String stage;
  final int price;
  final bool closed;
  final List<AmoField> fields;
  AmoLead(this.id, this.name, this.stage, this.price, this.closed, this.fields);
}

class AmoTask {
  final int id;
  final String text;
  final DateTime due;
  AmoTask(this.id, this.text, this.due);
}

class AmoLookup {
  final int contactId;
  final String contactName;
  final List<AmoField> fields;
  final List<AmoLead> leads;
  AmoLookup(this.contactId, this.contactName, this.fields, this.leads);
}

class AmoService {
  final AmoSettings s;
  final http.Client _client = http.Client();
  List<Map> _pipes = [];

  AmoService(this.s);

  static String digits10(String phone) {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    return d.length > 10 ? d.substring(d.length - 10) : d;
  }

  String _q(Map<String, Object> p) => p.entries
      .map((e) =>
          '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent('${e.value}')}')
      .join('&');

  Future<dynamic> _req(String method, String path, [Object? body]) async {
    if (s.host.isEmpty || s.token.trim().isEmpty) {
      throw AmoException('Не заполнены адрес и токен amoCRM.');
    }
    final req = http.Request(method, Uri.parse('https://${s.host}$path'));
    req.headers['Authorization'] = 'Bearer ${s.token.trim()}';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.bodyBytes = utf8.encode(jsonEncode(body));
    }
    final res = await http.Response.fromStream(
        await _client.send(req).timeout(const Duration(seconds: 30)));
    final text = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (res.statusCode == 204 || (res.statusCode < 300 && text.trim().isEmpty)) {
      return null;
    }
    dynamic data;
    try {
      data = jsonDecode(text);
    } catch (_) {}
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    if (res.statusCode == 401) {
      throw AmoException('amoCRM: токен недействителен или истёк (401).');
    }
    var msg = '';
    if (data is Map) {
      msg = '${data['title'] ?? ''} ${data['detail'] ?? ''}'.trim();
      if (data['validation-errors'] != null) {
        msg = '$msg ${jsonEncode(data['validation-errors'])}';
      }
    }
    throw AmoException('amoCRM: ошибка ${res.statusCode}. $msg');
  }

  List<AmoField> _fields(dynamic raw, List<int> only) {
    final out = <AmoField>[];
    for (final f in (raw as List? ?? const []).whereType<Map>()) {
      if (only.isNotEmpty && !only.contains(f['field_id'])) continue;
      final v = (f['values'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => '${e['value'] ?? ''}')
          .where((e) => e.isNotEmpty)
          .join(', ');
      if (v.isNotEmpty) out.add(AmoField('${f['field_name'] ?? ''}', v));
    }
    return out;
  }

  Future<List<(int, String)>> users() async {
    final r = await _req('GET', '/api/v4/users?limit=250');
    return (r?['_embedded']?['users'] as List? ?? const [])
        .whereType<Map>()
        .map((u) => (u['id'] as int, '${u['name'] ?? u['email'] ?? u['id']}'))
        .toList();
  }

  Future<List<Map>> pipelines() async {
    if (_pipes.isEmpty) {
      final r = await _req('GET', '/api/v4/leads/pipelines');
      _pipes = (r?['_embedded']?['pipelines'] as List? ?? const [])
          .whereType<Map>()
          .toList();
    }
    return _pipes;
  }

  String stageName(dynamic pipelineId, dynamic statusId) {
    for (final p in _pipes) {
      if (p['id'] != pipelineId) continue;
      for (final st
          in (p['_embedded']?['statuses'] as List? ?? const []).whereType<Map>()) {
        if (st['id'] == statusId) return '${p['name']} → ${st['name']}';
      }
    }
    return '';
  }

  Future<List<(int, String)>> customFields(String entity) async {
    final r = await _req('GET', '/api/v4/$entity/custom_fields?limit=250');
    return (r?['_embedded']?['custom_fields'] as List? ?? const [])
        .whereType<Map>()
        .map((f) => (f['id'] as int, '${f['name'] ?? f['id']}'))
        .toList();
  }

  Future<AmoLookup?> findByPhone(String phone) async {
    final d = digits10(phone);
    if (d.length < 6) return null;
    final r = await _req('GET',
        '/api/v4/contacts?${_q({'query': d, 'with': 'leads', 'limit': 10})}');
    Map? c;
    for (final x
        in (r?['_embedded']?['contacts'] as List? ?? const []).whereType<Map>()) {
      final has = (x['custom_fields_values'] as List? ?? const [])
          .whereType<Map>()
          .any((f) =>
              f['field_code'] == 'PHONE' &&
              (f['values'] as List? ?? const [])
                  .whereType<Map>()
                  .any((v) => digits10('${v['value']}') == d));
      if (has) {
        c = x;
        break;
      }
    }
    if (c == null) return null;

    final ids = (c['_embedded']?['leads'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => e['id'])
        .toList();
    final leads = <AmoLead>[];
    if (ids.isNotEmpty) {
      await pipelines();
      final q = [
        for (var i = 0; i < ids.length && i < 50; i++)
          '${Uri.encodeQueryComponent('filter[id][$i]')}=${ids[i]}'
      ].join('&');
      final lr = await _req('GET', '/api/v4/leads?$q&limit=50');
      for (final l
          in (lr?['_embedded']?['leads'] as List? ?? const []).whereType<Map>()) {
        final st = l['status_id'];
        leads.add(AmoLead(
          l['id'] as int,
          '${l['name'] ?? 'Сделка ${l['id']}'}',
          stageName(l['pipeline_id'], st),
          (l['price'] as num?)?.toInt() ?? 0,
          st == 142 || st == 143,
          _fields(l['custom_fields_values'], s.leadFields),
        ));
      }
    }
    return AmoLookup(
      c['id'] as int,
      '${c['name'] ?? ''}',
      _fields(c['custom_fields_values'], s.contactFields),
      leads,
    );
  }

  Future<List<AmoTask>> openTasks(int leadId) async {
    final r = await _req(
        'GET',
        '/api/v4/tasks?${_q({
              'filter[is_completed]': 0,
              'filter[entity_type]': 'leads',
              'filter[entity_id][0]': leadId,
              'limit': 50,
            })}');
    final list = (r?['_embedded']?['tasks'] as List? ?? const [])
        .whereType<Map>()
        .map((t) => AmoTask(
              t['id'] as int,
              '${t['text'] ?? ''}',
              DateTime.fromMillisecondsSinceEpoch(
                  ((t['complete_till'] as num?)?.toInt() ?? 0) * 1000),
            ))
        .toList();
    list.sort((a, b) => a.due.compareTo(b.due));
    return list;
  }

  /// Создаёт сделку (и контакт, если contactId == null). Возвращает ID сделки.
  Future<int> createLead({
    required String name,
    int? contactId,
    required String contactName,
    required String phone,
  }) async {
    final uid = s.userId;
    final r = await _req('POST', '/api/v4/leads/complex', [
      {
        'name': name,
        if (s.pipelineId != null) 'pipeline_id': s.pipelineId,
        if (s.statusId != null) 'status_id': s.statusId,
        'responsible_user_id': uid,
        'created_by': uid,
        '_embedded': {
          'contacts': [
            if (contactId != null)
              {'id': contactId}
            else
              {
                'first_name': contactName.isEmpty ? phone : contactName,
                'responsible_user_id': uid,
                'created_by': uid,
                'custom_fields_values': [
                  {
                    'field_code': 'PHONE',
                    'values': [
                      {'value': phone, 'enum_code': 'MOB'}
                    ]
                  }
                ],
              }
          ]
        },
      }
    ]);
    if (r is List && r.isNotEmpty && r.first is Map && r.first['id'] != null) {
      return r.first['id'] as int;
    }
    throw AmoException('amoCRM не вернул ID новой сделки.');
  }

  Future<void> _step(
      Set<String> done, String key, Future<void> Function() fn) async {
    if (done.contains(key)) return;
    await fn();
    done.add(key);
  }

  /// Пишет звонок, результат и задачи в сделку. [done] хранит выполненные
  /// шаги, чтобы повтор после ошибки не создавал дубли.
  Future<void> saveResult({
    required int leadId,
    required bool incoming,
    required String phone,
    required int duration,
    required DateTime at,
    required String text,
    String transcript = '',
    int? closeTaskId,
    String taskText = '',
    DateTime? due,
    required Set<String> done,
  }) async {
    final uid = s.userId;
    await _step(done, 'notes', () async {
      await _req('POST', '/api/v4/leads/$leadId/notes', [
        {
          'note_type': incoming ? 'call_in' : 'call_out',
          'created_by': uid,
          'params': {
            'uniq': 'echoscript_${at.millisecondsSinceEpoch}',
            'duration': duration,
            'source': 'EchoScript',
            'phone': phone,
          },
        },
        if (closeTaskId == null)
          {
            'note_type': 'common',
            'created_by': uid,
            'params': {'text': text},
          },
        if (transcript.isNotEmpty)
          {
            'note_type': 'common',
            'created_by': uid,
            'params': {'text': 'Расшифровка звонка:\n$transcript'},
          },
      ]);
    });
    if (closeTaskId != null) {
      await _step(done, 'close', () async {
        await _req('PATCH', '/api/v4/tasks/$closeTaskId', {
          'is_completed': true,
          'result': {'text': text},
        });
      });
    }
    if (taskText.isNotEmpty && due != null) {
      await _step(done, 'task', () async {
        await _req('POST', '/api/v4/tasks', [
          {
            'text': taskText,
            'complete_till': due.millisecondsSinceEpoch ~/ 1000,
            'entity_id': leadId,
            'entity_type': 'leads',
            'responsible_user_id': uid,
            'created_by': uid,
            'task_type_id': 1,
          }
        ]);
      });
    }
  }
}
