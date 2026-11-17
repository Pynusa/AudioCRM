import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

import '../models/models.dart';

/// Platform-neutral helpers for reading audio (works on Android & Web preview).

Future<Uint8List> readAudioBytes(AudioItem a) async {
  if (a.bytes != null) return a.bytes!;
  if (a.path != null) return XFile(a.path!).readAsBytes();
  throw StateError('Нет данных аудиофайла');
}

Stream<List<int>> openAudioStream(AudioItem a) async* {
  if (a.bytes != null) {
    const chunk = 1024 * 1024;
    for (var i = 0; i < a.bytes!.length; i += chunk) {
      yield a.bytes!.sublist(
          i, i + chunk > a.bytes!.length ? a.bytes!.length : i + chunk);
    }
    return;
  }
  if (a.path != null) {
    yield* XFile(a.path!).openRead();
    return;
  }
  throw StateError('Нет данных аудиофайла');
}

Future<int> fileLength(String path) => XFile(path).length();

String _ext(String? name) {
  if (name == null || !name.contains('.')) return '';
  return name.split('.').last.toLowerCase();
}

/// Port of `normalizeAudioMimeType` from the original server.ts.
String normalizeAudioMime(String mimeType, [String? filename]) {
  final mime = mimeType.trim().toLowerCase();
  final ext = _ext(filename);
  if (mime.contains('m4a') || ext == 'm4a') return 'audio/mp4';
  if (mime.contains('mp3') || mime.contains('mpeg') || ext == 'mp3') {
    return 'audio/mp3';
  }
  if (mime.contains('wav') || ext == 'wav') return 'audio/wav';
  if (mime.contains('webm') || ext == 'webm') return 'audio/webm';
  if (mime.contains('aac') || ext == 'aac') return 'audio/aac';
  if (mime.contains('ogg') || mime.contains('opus') || ext == 'ogg' || ext == 'opus' || ext == 'oga') {
    return 'audio/ogg';
  }
  if (mime.contains('flac') || ext == 'flac') return 'audio/flac';
  if (mime.contains('amr') || ext == 'amr') return 'audio/amr';
  if (mime.contains('3gp') || ext == '3gp') return 'audio/3gpp';
  if (ext == 'mp4' || mime.contains('mp4')) return 'audio/mp4';
  if (mime.startsWith('video/')) return 'video/mp4';
  if (mime.isNotEmpty && mime != 'application/octet-stream') return mime;
  return 'audio/mp4';
}

String mimeFromName(String name) => normalizeAudioMime('', name);

String extensionForMime(String mime) {
  final m = normalizeAudioMime(mime);
  switch (m) {
    case 'audio/mp3':
      return 'mp3';
    case 'audio/wav':
      return 'wav';
    case 'audio/webm':
      return 'webm';
    case 'audio/aac':
      return 'aac';
    case 'audio/ogg':
      return 'ogg';
    case 'audio/flac':
      return 'flac';
    default:
      return 'm4a';
  }
}

/// Format token for OpenAI-style `input_audio` content parts.
String audioFormatForOpenAI(String mime, String name) {
  final m = normalizeAudioMime(mime, name);
  switch (m) {
    case 'audio/mp3':
      return 'mp3';
    case 'audio/wav':
      return 'wav';
    case 'audio/ogg':
      return 'ogg';
    case 'audio/flac':
      return 'flac';
    case 'audio/aac':
      return 'aac';
    case 'audio/webm':
      return 'webm';
    default:
      return 'm4a';
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} МБ';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} ГБ';
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
