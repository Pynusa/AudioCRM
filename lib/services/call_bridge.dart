import 'package:flutter/services.dart';

class CallEntry {
  final String number;
  final String name;
  final int type; // 1 входящий, 2 исходящий, 3 пропущенный
  final DateTime date;
  final int duration;
  CallEntry(this.number, this.name, this.type, this.date, this.duration);

  bool get incoming => type != 2;
  DateTime get end => date.add(Duration(seconds: duration));
  String get typeLabel => switch (type) {
        1 => 'Входящий',
        2 => 'Исходящий',
        3 => 'Пропущенный',
        5 => 'Отклонён',
        _ => 'Звонок',
      };
}

class RecordingEntry {
  final String uri;
  final String name;
  final DateTime date;
  final int size;
  final String mime;
  final String folder;
  RecordingEntry(this.uri, this.name, this.date, this.size, this.mime, this.folder);
}

class CallBridge {
  static const _ch = MethodChannel('echoscript/calls');
  static Future<void> requestOverlay() => _ch.invokeMethod('requestOverlay');
    static void Function()? onPlaybackDone;
  static void onOpenCalls(void Function() cb) {
    _ch.setMethodCallHandler((c) async {
      if (c.method == 'openCalls') cb();
      if (c.method == 'playbackDone') onPlaybackDone?.call();
    });
  }
  static Future<void> play(String uri) =>
      _ch.invokeMethod('playRecording', {'uri': uri});
  static Future<void> stopPlayback() => _ch.invokeMethod('stopRecording');
  static Future<bool> consumeOpenCalls() async {
    try {
      return await _ch.invokeMethod<bool>('consumeOpenCalls') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasPermissions() async {
    try {
      return await _ch.invokeMethod<bool>('hasPermissions') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestPermissions() async =>
      await _ch.invokeMethod<bool>('requestPermissions') ?? false;

  static Future<List<CallEntry>> recentCalls([int limit = 50]) async {
    final r = await _ch.invokeMethod<List>('recentCalls', {'limit': limit}) ?? [];
    return r.whereType<Map>().map((m) => CallEntry(
          '${m['number'] ?? ''}',
          '${m['name'] ?? ''}',
          (m['type'] as num?)?.toInt() ?? 0,
          DateTime.fromMillisecondsSinceEpoch((m['date'] as num?)?.toInt() ?? 0),
          (m['duration'] as num?)?.toInt() ?? 0,
        )).toList();
  }

  static Future<List<RecordingEntry>> recordings(DateTime since) async {
    final r = await _ch.invokeMethod<List>(
            'recordings', {'since': since.millisecondsSinceEpoch}) ??
        [];
    return r.whereType<Map>().map((m) => RecordingEntry(
          '${m['uri']}',
          '${m['name'] ?? ''}',
          DateTime.fromMillisecondsSinceEpoch((m['date'] as num?)?.toInt() ?? 0),
          (m['size'] as num?)?.toInt() ?? 0,
          '${m['mime'] ?? ''}',
          '${m['folder'] ?? ''}',
        )).toList();
  }

  static Future<({String path, String name, String mime})> importRecording(
      String uri) async {
    final m = await _ch.invokeMethod<Map>('importRecording', {'uri': uri});
    if (m == null) throw Exception('Не удалось прочитать запись');
    return (
      path: '${m['path']}',
      name: '${m['name']}',
      mime: '${m['mimeType'] ?? ''}'
    );
  }
}
