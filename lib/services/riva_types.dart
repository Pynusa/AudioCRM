class RivaChunk {
  final String path;
  final int offsetMs;
  final int durationMs;
  RivaChunk({required this.path, required this.offsetMs, required this.durationMs});
}

class RivaPiece {
  final int startMs;
  final String text;
  RivaPiece({required this.startMs, required this.text});
}

class RivaResult {
  final List<RivaPiece> pieces;
  final String language;
  RivaResult({required this.pieces, required this.language});
}

class RivaException implements Exception {
  /// gRPC status code (16 = UNAUTHENTICATED, 7 = PERMISSION_DENIED,
  /// 8 = RESOURCE_EXHAUSTED, 14 = UNAVAILABLE, 4 = DEADLINE_EXCEEDED).
  final int code;
  final String message;
  RivaException(this.code, this.message);
  @override
  String toString() => message;
}
