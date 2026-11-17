import 'riva_types.dart';

/// Web build: gRPC over HTTP/2 isn't available in browsers.
class RivaAsrClient {
  static bool get supported => false;

  static Future<List<RivaChunk>> prepareChunks(String path, int chunkSeconds) =>
      throw RivaException(12, 'NVIDIA Whisper работает только в Android-приложении.');

  static Future<RivaResult> recognize({
    required String apiKey,
    required String functionId,
    required String host,
    required RivaChunk chunk,
    required String languageCode,
  }) =>
      throw RivaException(12, 'NVIDIA Whisper работает только в Android-приложении.');
}
