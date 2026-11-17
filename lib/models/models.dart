import 'dart:typed_data';

/// Supported AI providers.
enum ProviderType { gemini, openai, groq, openrouter, nvidia, custom }

ProviderType providerFromName(String? name) => ProviderType.values.firstWhere(
      (p) => p.name == name,
      orElse: () => ProviderType.gemini,
    );

/// A single API key added by the user.
class ApiKeyEntry {
  final String id;
  final ProviderType provider;
  final String label;
  final String key;

  /// Only used by [ProviderType.custom] (OpenAI-compatible endpoint).
  final String? baseUrl;

  /// NVIDIA NVCF function id override (build.nvidia.com model endpoint).
  final String? functionId;
  final DateTime createdAt;

  ApiKeyEntry({
    required this.id,
    required this.provider,
    required this.label,
    required this.key,
    this.baseUrl,
    this.functionId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get maskedKey {
    if (key.length <= 10) return '••••••';
    return '${key.substring(0, 6)}••••${key.substring(key.length - 4)}';
  }

  ApiKeyEntry copyWith({
    String? label,
    String? key,
    String? baseUrl,
    String? functionId,
    ProviderType? provider,
  }) =>
      ApiKeyEntry(
        id: id,
        provider: provider ?? this.provider,
        label: label ?? this.label,
        key: key ?? this.key,
        baseUrl: baseUrl ?? this.baseUrl,
        functionId: functionId ?? this.functionId,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'provider': provider.name,
        'label': label,
        'key': key,
        'baseUrl': baseUrl,
        'functionId': functionId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ApiKeyEntry.fromJson(Map<String, dynamic> j) => ApiKeyEntry(
        id: j['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
        provider: providerFromName(j['provider'] as String?),
        label: j['label'] as String? ?? '',
        key: j['key'] as String? ?? '',
        baseUrl: j['baseUrl'] as String?,
        functionId: j['functionId'] as String?,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
      );
}

/// User preferences for the transcription pipeline.
class AppSettings {
  /// Key used for the transcription step.
  final String? transcribeKeyId;
  final String transcribeModel;

  /// Optional backup model (same provider) used on overload / timeout.
  final String fallbackModel;

  /// Key + model used for the analysis step (two-step providers only).
  /// `null` → analysis disabled for Whisper-style providers.
  final String? analysisKeyId;
  final String analysisModel;

  final String outputLanguage;
  final bool enableCrm;
  final String customInstructions;
  final String speakerHint;
  final bool rotateKeys;
  final String themeMode; // system | light | dark

  const AppSettings({
    this.transcribeKeyId,
    this.transcribeModel = 'gemini-3.8-flash',
    this.fallbackModel = '',
    this.analysisKeyId,
    this.analysisModel = '',
    this.outputLanguage = 'русский',
    this.enableCrm = true,
    this.customInstructions = '',
    this.speakerHint = '',
    this.rotateKeys = true,
    this.themeMode = 'system',
  });

  AppSettings copyWith({
    String? transcribeKeyId,
    String? transcribeModel,
    String? fallbackModel,
    String? analysisKeyId,
    bool clearAnalysisKey = false,
    String? analysisModel,
    String? outputLanguage,
    bool? enableCrm,
    String? customInstructions,
    String? speakerHint,
    bool? rotateKeys,
    String? themeMode,
  }) =>
      AppSettings(
        transcribeKeyId: transcribeKeyId ?? this.transcribeKeyId,
        transcribeModel: transcribeModel ?? this.transcribeModel,
        fallbackModel: fallbackModel ?? this.fallbackModel,
        analysisKeyId:
            clearAnalysisKey ? null : (analysisKeyId ?? this.analysisKeyId),
        analysisModel: analysisModel ?? this.analysisModel,
        outputLanguage: outputLanguage ?? this.outputLanguage,
        enableCrm: enableCrm ?? this.enableCrm,
        customInstructions: customInstructions ?? this.customInstructions,
        speakerHint: speakerHint ?? this.speakerHint,
        rotateKeys: rotateKeys ?? this.rotateKeys,
        themeMode: themeMode ?? this.themeMode,
      );

  Map<String, dynamic> toJson() => {
        'transcribeKeyId': transcribeKeyId,
        'transcribeModel': transcribeModel,
        'fallbackModel': fallbackModel,
        'analysisKeyId': analysisKeyId,
        'analysisModel': analysisModel,
        'outputLanguage': outputLanguage,
        'enableCrm': enableCrm,
        'customInstructions': customInstructions,
        'speakerHint': speakerHint,
        'rotateKeys': rotateKeys,
        'themeMode': themeMode,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        transcribeKeyId: j['transcribeKeyId'] as String?,
        transcribeModel: j['transcribeModel'] as String? ?? 'gemini-3.8-flash',
        fallbackModel: j['fallbackModel'] as String? ?? '',
        analysisKeyId: j['analysisKeyId'] as String?,
        analysisModel: j['analysisModel'] as String? ?? '',
        outputLanguage: j['outputLanguage'] as String? ?? 'русский',
        enableCrm: j['enableCrm'] as bool? ?? true,
        customInstructions: j['customInstructions'] as String? ?? '',
        speakerHint: j['speakerHint'] as String? ?? '',
        rotateKeys: j['rotateKeys'] as bool? ?? true,
        themeMode: j['themeMode'] as String? ?? 'system',
      );
}

/// An audio file waiting to be transcribed.
class AudioItem {
  final String name;
  final String? path;
  final Uint8List? bytes;
  final String mimeType;
  final int size;
  final Duration? duration;

  AudioItem({
    required this.name,
    this.path,
    this.bytes,
    required this.mimeType,
    required this.size,
    this.duration,
  });
}

class TranscriptionSegment {
  final String speaker;
  final String timestamp;
  final String content;
  final String language;
  final String emotion;

  TranscriptionSegment({
    required this.speaker,
    required this.timestamp,
    required this.content,
    this.language = '',
    this.emotion = '',
  });

  Map<String, dynamic> toJson() => {
        'speaker': speaker,
        'timestamp': timestamp,
        'content': content,
        'language': language,
        'emotion': emotion,
      };

  factory TranscriptionSegment.fromJson(Map<String, dynamic> j) =>
      TranscriptionSegment(
        speaker: (j['speaker'] ?? 'Спикер').toString(),
        timestamp: (j['timestamp'] ?? '').toString(),
        content: (j['content'] ?? j['text'] ?? '').toString(),
        language: (j['language'] ?? '').toString(),
        emotion: (j['emotion'] ?? '').toString(),
      );
}

class CrmReport {
  final String summary;
  final List<String> keyPoints;
  final List<String> clientNeeds;
  final String sentiment;
  final List<String> nextSteps;

  CrmReport({
    required this.summary,
    required this.keyPoints,
    required this.clientNeeds,
    required this.sentiment,
    required this.nextSteps,
  });

  static List<String> _list(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    if (v is String && v.isNotEmpty) return [v];
    return [];
  }

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'keyPoints': keyPoints,
        'clientNeeds': clientNeeds,
        'sentiment': sentiment,
        'nextSteps': nextSteps,
      };

  factory CrmReport.fromJson(Map<String, dynamic> j) => CrmReport(
        summary: (j['summary'] ?? '').toString(),
        keyPoints: _list(j['keyPoints']),
        clientNeeds: _list(j['clientNeeds']),
        sentiment: (j['sentiment'] ?? '').toString(),
        nextSteps: _list(j['nextSteps']),
      );
}

class TranscriptionResult {
  final String fileName;
  final String summary;
  final List<TranscriptionSegment> segments;
  final CrmReport? crmReport;
  final String model;

  TranscriptionResult({
    required this.fileName,
    required this.summary,
    required this.segments,
    this.crmReport,
    this.model = '',
  });

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'summary': summary,
        'segments': segments.map((s) => s.toJson()).toList(),
        'crmReport': crmReport?.toJson(),
        'model': model,
      };

  factory TranscriptionResult.fromJson(Map<String, dynamic> j,
      {String? fileName, String? model}) {
    final segs = j['segments'];
    final crm = j['crmReport'];
    return TranscriptionResult(
      fileName: fileName ?? (j['fileName'] ?? 'Аудио').toString(),
      summary: (j['summary'] ?? '').toString(),
      segments: segs is List
          ? segs
              .whereType<Map>()
              .map((e) =>
                  TranscriptionSegment.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : [],
      crmReport:
          crm is Map ? CrmReport.fromJson(Map<String, dynamic>.from(crm)) : null,
      model: model ?? (j['model'] ?? '').toString(),
    );
  }
}

/// A saved transcription session (one or several files).
class HistorySession {
  final String id;
  final DateTime createdAt;
  final List<TranscriptionResult> results;

  HistorySession({
    required this.id,
    required this.createdAt,
    required this.results,
  });

  String get title => results.length == 1
      ? results.first.fileName
      : '${results.first.fileName} + ещё ${results.length - 1}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'results': results.map((r) => r.toJson()).toList(),
      };

  factory HistorySession.fromJson(Map<String, dynamic> j) => HistorySession(
        id: j['id'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
        results: (j['results'] as List? ?? [])
            .whereType<Map>()
            .map((e) =>
                TranscriptionResult.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}
