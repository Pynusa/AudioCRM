import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import 'audio_io.dart';

/// Receives files shared into the app from other Android apps.
class ShareIntake {
  static const _ch = MethodChannel('echoscript/share');

  static void listen(void Function(List<AudioItem>) onFiles) {
    if (kIsWeb) return;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'onSharedFiles') {
        final items = await _toItems(call.arguments);
        if (items.isNotEmpty) onFiles(items);
      }
    });
  }

  static Future<List<AudioItem>> initial() async {
    if (kIsWeb) return [];
    try {
      final r = await _ch.invokeMethod('getSharedFiles');
      return _toItems(r);
    } catch (_) {
      return [];
    }
  }

  static Future<List<AudioItem>> _toItems(dynamic raw) async {
    final out = <AudioItem>[];
    if (raw is! List) return out;
    for (final e in raw.whereType<Map>()) {
      final path = e['path']?.toString();
      if (path == null) continue;
      final name = e['name']?.toString() ?? 'audio';
      out.add(AudioItem(
        name: name,
        path: path,
        mimeType: normalizeAudioMime(e['mimeType']?.toString() ?? '', name),
        size: await fileLength(path),
      ));
    }
    return out;
  }
}

class FileServices {
  static const audioExtensions = [
    'mp3', 'm4a', 'wav', 'ogg', 'opus', 'oga', 'webm', 'aac', 'flac', 'amr',
    '3gp', 'mp4', 'mkv', 'mov',
  ];

  static Future<List<AudioItem>> pickAudio() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: audioExtensions,
      allowMultiple: true,
      withData: kIsWeb,
    );
    if (res == null) return [];
    return res.files
        .map((f) => AudioItem(
              name: f.name,
              path: kIsWeb ? null : f.path,
              bytes: kIsWeb ? f.bytes : null,
              mimeType: mimeFromName(f.name),
              size: f.size,
            ))
        .where((a) => a.path != null || a.bytes != null)
        .toList();
  }

  static Future<String?> pickTextFile() async {
    final res = await FilePicker.pickFiles(
      type: FileType.any,
      withData: true,
    );
    final b = res?.files.single.bytes;
    if (b == null) {
      final p = res?.files.single.path;
      if (p == null) return null;
      return utf8.decode(await XFile(p).readAsBytes(), allowMalformed: true);
    }
    return utf8.decode(b, allowMalformed: true);
  }

  static Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  static Uint8List _withBom(String content) =>
      Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(content)]);

  /// Opens the Android share sheet (Telegram, Gmail, Drive, Samsung Notes...).
  static Future<void> shareText(String content, String fileName,
      {String mime = 'text/plain'}) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(_withBom(content), mimeType: mime, name: fileName)],
      fileNameOverrides: [fileName],
      subject: fileName,
    ));
  }

  /// Lets the user choose a folder (e.g. Downloads) and saves the file there.
  static Future<bool> saveText(String content, String fileName) async {
    final path = await FilePicker.saveFile(
      dialogTitle: 'Сохранить файл',
      fileName: fileName,
      bytes: _withBom(content),
    );
    return path != null || kIsWeb;
  }
}
