import 'package:cross_file/cross_file.dart';
import 'package:flutter/services.dart';
import 'package:grpc/grpc.dart';

import 'proto_lite.dart';
import 'riva_types.dart';

/// NVIDIA Riva ASR over gRPC (build.nvidia.com / NVCF hosted Whisper).
class RivaAsrClient {
  static const _audio = MethodChannel('echoscript/audio');

  static final _recognize = ClientMethod<Uint8List, Uint8List>(
    '/nvidia.riva.asr.RivaSpeechRecognition/Recognize',
    (v) => v,
    (v) => v is Uint8List ? v : Uint8List.fromList(v),
  );

  static bool get supported => true;

  /// Decodes the file on-device into 16 kHz mono WAV chunks.
  static Future<List<RivaChunk>> prepareChunks(String path, int chunkSeconds) async {
    final raw = await _audio.invokeMethod<List<dynamic>>('decodeToWavChunks', {
      'path': path,
      'chunkSeconds': chunkSeconds,
    });
    return (raw ?? [])
        .whereType<Map>()
        .map((m) => RivaChunk(
              path: m['path'].toString(),
              offsetMs: (m['offsetMs'] as num).toInt(),
              durationMs: (m['durationMs'] as num).toInt(),
            ))
        .toList();
  }

  static Future<RivaResult> recognize({
    required String apiKey,
    required String functionId,
    required String host,
    required RivaChunk chunk,
    required String languageCode,
  }) async {
    final channel = ClientChannel(
      host,
      port: 443,
      options: const ChannelOptions(
        credentials: ChannelCredentials.secure(),
        connectionTimeout: Duration(seconds: 30),
      ),
    );
    try {
      final client = _RivaClient(channel);
      final audio = await XFile(chunk.path).readAsBytes();

      final config = ProtoWriter()
        ..int32(1, 1) // encoding = LINEAR_PCM
        ..int32(2, 16000) // sample_rate_hertz
        ..string(3, languageCode) // language_code
        ..int32(4, 1) // max_alternatives
        ..int32(7, 1) // audio_channel_count
        ..boolean(8, true) // enable_word_time_offsets
        ..boolean(11, true) // enable_automatic_punctuation
        ..boolean(14, true); // verbatim_transcripts
      final req = ProtoWriter()
        ..message(1, config)
        ..bytes(2, audio);

      final resp = await client.recognize(
        req.toBytes(),
        CallOptions(
          metadata: {
            'function-id': functionId,
            'authorization': 'Bearer ${apiKey.trim()}',
          },
          timeout: const Duration(minutes: 5),
        ),
      );
      return _parse(resp, chunk.offsetMs);
    } on GrpcError catch (e) {
      throw RivaException(e.code, e.message ?? e.codeName);
    } finally {
      await channel.shutdown();
    }
  }

  static RivaResult _parse(Uint8List data, int offsetMs) {
    final pieces = <RivaPiece>[];
    String lang = '';
    for (final r in protoDecode(data).where((f) => f.number == 1 && f.bytes != null)) {
      // SpeechRecognitionResult → first alternative
      final alt = protoDecode(r.bytes!).firstWhere(
          (f) => f.number == 1 && f.bytes != null,
          orElse: () => ProtoField(0, 0));
      if (alt.bytes == null) continue;
      String transcript = '';
      int? firstWordMs;
      for (final f in protoDecode(alt.bytes!)) {
        if (f.number == 1 && f.bytes != null) transcript = f.asString;
        if (f.number == 4 && f.bytes != null && lang.isEmpty) lang = f.asString;
        if (f.number == 3 && f.bytes != null && firstWordMs == null) {
          for (final w in protoDecode(f.bytes!)) {
            if (w.number == 1) firstWordMs = w.asInt32;
          }
          firstWordMs ??= 0;
        }
      }
      if (transcript.trim().isEmpty) continue;
      pieces.add(RivaPiece(
          startMs: offsetMs + (firstWordMs ?? 0), text: transcript.trim()));
    }
    return RivaResult(pieces: pieces, language: lang);
  }
}

class _RivaClient extends Client {
  _RivaClient(super.channel);

  ResponseFuture<Uint8List> recognize(Uint8List req, CallOptions options) =>
      $createUnaryCall(RivaAsrClient._recognize, req, options: options);
}
