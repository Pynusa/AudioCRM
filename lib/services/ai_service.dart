import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'audio_io.dart';
import 'nvidia_riva_stub.dart' if (dart.library.io) 'nvidia_riva_io.dart';
import 'provider_catalog.dart';
import 'riva_types.dart';

class AiException implements Exception {
  final String message;
  final bool transient;
  final int? status;
  AiException(this.message, {this.transient = false, this.status});
  @override
  String toString() => message;
}

typedef ProgressCallback = void Function(String step);

/// Talks to Gemini / OpenAI / Groq / OpenRouter / any OpenAI-compatible API
/// directly from the device — no backend server needed.
class AiService {
  static const _geminiInlineLimit = 18 * 1024 * 1024; // bytes
  static const _requestTimeout = Duration(minutes: 10);

  final http.Client _client;
  AiService([http.Client? client]) : _client = client ?? http.Client();

  // ───────────────────────────── Prompt ─────────────────────────────

  static String buildPrompt(AppSettings s, {bool fromTranscript = false}) {
    final lang = s.outputLanguage.trim().isEmpty ? 'русский' : s.outputLanguage;
    final crm = s.enableCrm
        ? '''
6. Generate a detailed CRM report in $lang including:
   - Summary of the negotiation (Суть переговоров).
   - Key points discussed (Ключевые моменты).
   - Identified client needs or pain points (Потребности и боли клиента).
   - Overall sentiment of the client (Настроение клиента).
   - Specific recommendations for next steps (Рекомендуемые следующие шаги).'''
        : '';
    final source = fromTranscript
        ? 'You are given a raw machine transcript of an audio recording (with approximate timestamps in [MM:SS] format). '
            'Infer distinct speakers from context and turn-taking, fix obvious recognition errors, and produce a structured result.'
        : 'Process the provided audio file and generate a detailed transcription.';
    final speakers = s.speakerHint.trim().isEmpty
        ? 'Identify distinct speakers (e.g., Спикер 1, Спикер 2, or Менеджер, Клиент).'
        : 'Identify distinct speakers. Hint about participants: ${s.speakerHint.trim()}.';
    final extra = s.customInstructions.trim().isEmpty
        ? ''
        : '\nAdditional user instructions: ${s.customInstructions.trim()}\n';

    return '''
You are an expert audio transcription assistant.
$source
All descriptive text (summary, report) must be written in $lang. The "content" of segments must stay in the ORIGINAL spoken language (verbatim), do not translate it.

Requirements:
1. $speakers
2. Provide accurate timestamps for each segment (Format: MM:SS or HH:MM:SS for long audio).
3. Detect the primary language of each segment.
4. Identify the primary emotion of the speaker in this segment (Happy, Sad, Angry, Neutral).
5. Provide a comprehensive summary of the entire audio in $lang.$crm
$extra
Output Format: JSON object with the following structure:
{
  "summary": "...",
  ${s.enableCrm ? '"crmReport": {"summary": "...", "keyPoints": ["..."], "clientNeeds": ["..."], "sentiment": "...", "nextSteps": ["..."]},' : ''}
  "segments": [
    {"speaker": "...", "timestamp": "...", "content": "...", "language": "...", "emotion": "..."}
  ]
}

IMPORTANT: Group conversation logically (main speaking turns, up to ~60 seconds per segment) to cover the ENTIRE audio from start to end without exceeding output limits. Return ONLY valid JSON.
''';
  }

  static Map<String, dynamic> _geminiSchema(bool crm) => {
        'type': 'OBJECT',
        'properties': {
          'summary': {'type': 'STRING'},
          if (crm)
            'crmReport': {
              'type': 'OBJECT',
              'properties': {
                'summary': {'type': 'STRING'},
                'keyPoints': {
                  'type': 'ARRAY',
                  'items': {'type': 'STRING'}
                },
                'clientNeeds': {
                  'type': 'ARRAY',
                  'items': {'type': 'STRING'}
                },
                'sentiment': {'type': 'STRING'},
                'nextSteps': {
                  'type': 'ARRAY',
                  'items': {'type': 'STRING'}
                },
              },
              'required': [
                'summary',
                'keyPoints',
                'clientNeeds',
                'sentiment',
                'nextSteps'
              ],
            },
          'segments': {
            'type': 'ARRAY',
            'items': {
              'type': 'OBJECT',
              'properties': {
                'speaker': {'type': 'STRING'},
                'timestamp': {'type': 'STRING'},
                'content': {'type': 'STRING'},
                'language': {'type': 'STRING'},
                'emotion': {'type': 'STRING'},
              },
              'required': ['speaker', 'timestamp', 'content', 'language', 'emotion'],
            },
          },
        },
        'required': ['summary', 'segments', if (crm) 'crmReport'],
      };

  // ───────────────────────────── Public API ─────────────────────────────

  /// Transcribes one audio item. Handles retries, fallback model and key rotation.
  Future<TranscriptionResult> transcribe({
    required AudioItem audio,
    required ApiKeyEntry key,
    required List<ApiKeyEntry> rotationKeys,
    required AppSettings settings,
    ApiKeyEntry? analysisKey,
    required ProgressCallback onProgress,
    required bool Function() isCanceled,
    void Function(String oldModel, String newModel)? onModelReplaced,
  }) async {
    final models = <String>[
      settings.transcribeModel,
      if (settings.fallbackModel.trim().isNotEmpty &&
          settings.fallbackModel != settings.transcribeModel)
        settings.fallbackModel.trim(),
    ];
    final keys = <ApiKeyEntry>[
      key,
      if (settings.rotateKeys)
        ...rotationKeys.where((k) => k.id != key.id && k.provider == key.provider),
    ];

    Object? lastError;
    for (var ki = 0; ki < keys.length; ki++) {
      final k = keys[ki];
      for (var mi = 0; mi < models.length; mi++) {
        final model = models[mi];
        for (var attempt = 1; attempt <= 2; attempt++) {
          if (isCanceled()) throw AiException('Отменено');
          try {
            final label = keys.length > 1 ? ' · ключ «${k.label}»' : '';
            onProgress(attempt == 1
                ? 'Модель $model$label'
                : 'Повторная попытка ($model)$label');
            return await _transcribeOnce(
              audio: audio,
              key: k,
              model: model,
              settings: settings,
              analysisKey: analysisKey,
              onProgress: onProgress,
            );
          } on AiException catch (e) {
            lastError = e;
            debugPrint('[AI] $model attempt $attempt failed: ${e.message}');
            // Retired model (404) → switch to the replacement suggested by the
            // provider (or our own mapping) and remember it.
            if (e.status == 404) {
              final repl = suggestedReplacement(e.message, model);
              if (repl != null && !models.contains(repl)) {
                models.insert(mi + 1, repl);
                onModelReplaced?.call(model, repl);
                onProgress('Модель $model недоступна → переключаюсь на $repl');
                break;
              }
            }
            if (!e.transient) {
              // Invalid key / quota on this key → try next key, otherwise fail.
              if ((e.status == 401 || e.status == 403 || e.status == 429) &&
                  ki < keys.length - 1) {
                break;
              }
              rethrow;
            }
            if (attempt < 2) {
              await Future.delayed(Duration(milliseconds: 1500 * attempt));
            }
          } on TimeoutException {
            lastError = AiException(
                'Модель $model не ответила вовремя. Попробуйте более быструю модель.',
                transient: true);
            break; // timeouts → go straight to the fallback model
          }
        }
      }
    }
    if (lastError is AiException) throw lastError;
    throw AiException('Не удалось выполнить расшифровку: $lastError');
  }

  Future<TranscriptionResult> _transcribeOnce({
    required AudioItem audio,
    required ApiKeyEntry key,
    required String model,
    required AppSettings settings,
    ApiKeyEntry? analysisKey,
    required ProgressCallback onProgress,
  }) async {
    final info = ProviderCatalog.of(key.provider);
    Map<String, dynamic> json;
    switch (key.provider) {
      case ProviderType.gemini:
        json = isSpeechOnlyModel(model)
            ? await _geminiTranscribeModel(
                audio, key, model, settings, analysisKey, onProgress)
            : await _geminiTranscribe(audio, key, model, settings, onProgress);
        break;
      case ProviderType.openrouter:
        json = await _openRouterTranscribe(audio, key, model, settings, onProgress);
        break;
      case ProviderType.nvidia:
        json = await _nvidiaRiva(audio, key, model, settings, analysisKey, onProgress);
        break;
      case ProviderType.openai:
      case ProviderType.groq:
      case ProviderType.custom:
        json = await _sttPipeline(audio, key, info, model, settings,
            analysisKey, onProgress);
        break;
    }
    return TranscriptionResult.fromJson(json, fileName: audio.name, model: model);
  }

  // ───────────────────────────── Gemini ─────────────────────────────

  String _geminiBase(ApiKeyEntry k) =>
      (k.baseUrl?.isNotEmpty ?? false) ? k.baseUrl! : ProviderCatalog.gemini.defaultBaseUrl;

  Future<Map<String, dynamic>> _geminiTranscribe(AudioItem audio, ApiKeyEntry key,
      String model, AppSettings s, ProgressCallback onProgress) async {
    final mime = normalizeAudioMime(audio.mimeType, audio.name);
    Map<String, dynamic> audioPart;

    if (audio.size <= _geminiInlineLimit) {
      onProgress('Подготовка аудио...');
      final bytes = await readAudioBytes(audio);
      audioPart = {
        'inline_data': {'mime_type': mime, 'data': base64Encode(bytes)}
      };
    } else {
      onProgress('Загрузка файла в Gemini (${formatBytes(audio.size)})...');
      final uri = await _geminiUploadFile(audio, key, mime, onProgress);
      audioPart = {
        'file_data': {'mime_type': mime, 'file_uri': uri}
      };
    }

    onProgress('Расшифровка нейросетью ($model)...');
    final body = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            audioPart,
            {'text': buildPrompt(s)}
          ]
        }
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        'responseSchema': _geminiSchema(s.enableCrm),
        ..._geminiTuning(model),
      },
    };
    final text = await _geminiGenerate(key, model, body);
    return parseJsonLoose(text);
  }

  /// Generation params per model family. Gemini 3+ ignores/rejects sampling
  /// params and uses `thinkingLevel` (low keeps audio latency down, like the
  /// original server.ts); Gemini 2.x uses `thinkingBudget`.
  static Map<String, dynamic> _geminiTuning(String model) {
    final m = RegExp(r'gemini-(\d+)').firstMatch(model);
    final gen = m == null ? 3 : int.parse(m.group(1)!);
    if (gen >= 3 || model.contains('latest')) {
      return {
        'maxOutputTokens': 65536,
        if (!model.contains('transcribe'))
          'thinkingConfig': {'thinkingLevel': 'low'},
      };
    }
    return {
      'maxOutputTokens': 65536,
      'temperature': 0.2,
      if (model.contains('flash')) 'thinkingConfig': {'thinkingBudget': 512},
    };
  }

  Future<String> _geminiGenerate(
      ApiKeyEntry key, String model, Map<String, dynamic> body) async {
    final url = Uri.parse(
        '${_geminiBase(key)}/v1beta/models/$model:generateContent');
    Future<http.Response> send(Map<String, dynamic> b) => _client
        .post(url,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': key.key.trim(),
            },
            body: jsonEncode(b))
        .timeout(_requestTimeout);
    var res = await send(body);
    if (res.statusCode == 400 &&
        utf8.decode(res.bodyBytes, allowMalformed: true).toLowerCase().contains('json mode')) {
      // Model doesn't support structured output → ask for JSON in the prompt only.
      final cfg = Map<String, dynamic>.from(body['generationConfig'] as Map? ?? {})
        ..remove('responseMimeType')
        ..remove('responseSchema');
      res = await send({...body, 'generationConfig': cfg});
    }
    _check(res, 'Gemini');
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final cands = data['candidates'] as List?;
    if (cands == null || cands.isEmpty) {
      final block = data['promptFeedback']?['blockReason'];
      throw AiException(block != null
          ? 'Gemini заблокировал запрос: $block'
          : 'Gemini вернул пустой ответ.');
    }
    final cand = cands.first as Map<String, dynamic>;
    final parts = cand['content']?['parts'] as List? ?? [];
    final text = parts
        .whereType<Map>()
        .where((p) => p['thought'] != true)
        .map((p) => p['text'] ?? '')
        .join();
    if (text.trim().isEmpty) {
      throw AiException(
          'Gemini вернул пустой ответ (${cand['finishReason'] ?? 'unknown'}).',
          transient: true);
    }
    return text;
  }

  Future<String> _geminiUploadFile(AudioItem audio, ApiKeyEntry key, String mime,
      ProgressCallback onProgress) async {
    final base = _geminiBase(key);
    final start = await _client
        .post(
          Uri.parse('$base/upload/v1beta/files'),
          headers: {
            'x-goog-api-key': key.key.trim(),
            'X-Goog-Upload-Protocol': 'resumable',
            'X-Goog-Upload-Command': 'start',
            'X-Goog-Upload-Header-Content-Length': '${audio.size}',
            'X-Goog-Upload-Header-Content-Type': mime,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'file': {'display_name': audio.name}
          }),
        )
        .timeout(const Duration(minutes: 1));
    _check(start, 'Gemini Files API');
    final uploadUrl = start.headers['x-goog-upload-url'];
    if (uploadUrl == null) {
      throw AiException('Gemini Files API не вернул адрес загрузки.');
    }

    final req = http.StreamedRequest('POST', Uri.parse(uploadUrl));
    req.headers.addAll({
      'Content-Length': '${audio.size}',
      'X-Goog-Upload-Offset': '0',
      'X-Goog-Upload-Command': 'upload, finalize',
    });
    req.contentLength = audio.size;
    final sendFuture = _client.send(req).timeout(_requestTimeout);
    var sent = 0;
    var lastPct = -1;
    await for (final chunk in openAudioStream(audio)) {
      req.sink.add(chunk);
      sent += chunk.length;
      final pct = (sent * 100 / audio.size).floor();
      if (pct != lastPct && pct % 5 == 0) {
        lastPct = pct;
        onProgress('Загрузка файла: $pct%');
      }
    }
    await req.sink.close();
    final streamed = await sendFuture;
    final res = await http.Response.fromStream(streamed);
    _check(res, 'Gemini Files API');
    final file = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['file'] as Map;
    final name = file['name'] as String;
    var state = file['state'] as String? ?? 'PROCESSING';
    final uri = file['uri'] as String;

    var waited = 0;
    while (state == 'PROCESSING' && waited < 300) {
      onProgress('Gemini обрабатывает файл...');
      await Future.delayed(const Duration(seconds: 3));
      waited += 3;
      final r = await _client.get(Uri.parse('$base/v1beta/$name'),
          headers: {'x-goog-api-key': key.key.trim()});
      _check(r, 'Gemini Files API');
      state = (jsonDecode(r.body) as Map)['state'] as String? ?? 'ACTIVE';
    }
    if (state == 'FAILED') {
      throw AiException('Gemini не смог обработать аудиофайл.');
    }
    return uri;
  }

  // ───────────────────────────── OpenRouter (multimodal) ─────────────────────────────

  Future<Map<String, dynamic>> _openRouterTranscribe(AudioItem audio,
      ApiKeyEntry key, String model, AppSettings s, ProgressCallback onProgress) async {
    onProgress('Подготовка аудио...');
    final bytes = await readAudioBytes(audio);
    final format = audioFormatForOpenAI(audio.mimeType, audio.name);
    onProgress('Расшифровка нейросетью ($model)...');
    final text = await _chat(
      key: key,
      baseUrl: ProviderCatalog.openrouter.defaultBaseUrl,
      model: model,
      messages: [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': buildPrompt(s)},
            {
              'type': 'input_audio',
              'input_audio': {'data': base64Encode(bytes), 'format': format}
            },
          ]
        }
      ],
      jsonMode: true,
    );
    return parseJsonLoose(text);
  }

  // ───────────────────────────── Speech-to-text + analysis ─────────────────────────────

  String _baseUrlOf(ApiKeyEntry k) {
    final info = ProviderCatalog.of(k.provider);
    var b = (k.baseUrl?.trim().isNotEmpty ?? false) ? k.baseUrl!.trim() : info.defaultBaseUrl;
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    return b;
  }

  Future<Map<String, dynamic>> _sttPipeline(
    AudioItem audio,
    ApiKeyEntry key,
    ProviderInfo info,
    String model,
    AppSettings s,
    ApiKeyEntry? analysisKey,
    ProgressCallback onProgress,
  ) async {
    onProgress('Распознавание речи ($model)...');
    final bytes = await readAudioBytes(audio);
    final verbose = model.contains('whisper');
    final req = http.MultipartRequest(
        'POST', Uri.parse('${_baseUrlOf(key)}/audio/transcriptions'));
    req.headers['Authorization'] = 'Bearer ${key.key.trim()}';
    req.fields['model'] = model;
    req.fields['response_format'] = verbose ? 'verbose_json' : 'json';
    req.files.add(http.MultipartFile.fromBytes('file', bytes,
        filename: _safeFileName(audio.name, audio.mimeType)));
    final streamed = await _client.send(req).timeout(_requestTimeout);
    final res = await http.Response.fromStream(streamed);
    _check(res, info.shortName);
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;

    final rawSegments = <TranscriptionSegment>[];
    final segs = data['segments'] as List?;
    if (segs != null && segs.isNotEmpty) {
      for (final sg in segs.whereType<Map>()) {
        rawSegments.add(TranscriptionSegment(
          speaker: 'Спикер',
          timestamp: formatSeconds((sg['start'] as num?)?.toDouble() ?? 0),
          content: (sg['text'] ?? '').toString().trim(),
          language: (data['language'] ?? '').toString(),
        ));
      }
    } else {
      rawSegments.add(TranscriptionSegment(
        speaker: 'Спикер',
        timestamp: '00:00',
        content: (data['text'] ?? '').toString().trim(),
        language: (data['language'] ?? '').toString(),
      ));
    }

    return _analyzeTranscript(rawSegments, s, analysisKey, onProgress);
  }

  /// Second step for speech-only models: speakers, summary and CRM report
  /// produced by a chat model from the raw transcript.
  Future<Map<String, dynamic>> _analyzeTranscript(
    List<TranscriptionSegment> rawSegments,
    AppSettings s,
    ApiKeyEntry? analysisKey,
    ProgressCallback onProgress,
  ) async {
    final plain = rawSegments
        .map((e) => '[${e.timestamp}]${e.speaker.startsWith('Спикер ') ? ' ${e.speaker}:' : ''} ${e.content}')
        .join('\n');
    if (plain.trim().isEmpty) {
      throw AiException('Речь в записи не распознана.');
    }

    final ak = analysisKey;
    if (ak == null || s.analysisModel.trim().isEmpty) {
      return {
        'summary': 'Анализ (резюме и CRM-отчёт) отключён — выберите модель анализа в настройках («Ключи и модели» → «Анализ текста»).',
        'segments': _mergeShort(rawSegments).map((e) => e.toJson()).toList(),
      };
    }

    onProgress('Анализ текста (${s.analysisModel})...');
    final text = ak.provider == ProviderType.gemini
        ? await _geminiGenerate(ak, s.analysisModel, {
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': '${buildPrompt(s, fromTranscript: true)}\n\nTRANSCRIPT:\n$plain'}
                ]
              }
            ],
            'generationConfig': {
              'responseMimeType': 'application/json',
              'responseSchema': _geminiSchema(s.enableCrm),
              ..._geminiTuning(s.analysisModel),
            },
          })
        : await _chat(
            key: ak,
            baseUrl: _baseUrlOf(ak),
            model: s.analysisModel,
            messages: [
              {'role': 'system', 'content': buildPrompt(s, fromTranscript: true)},
              {'role': 'user', 'content': 'TRANSCRIPT:\n$plain'},
            ],
            jsonMode: true,
          );
    return parseJsonLoose(text);
  }

  List<TranscriptionSegment> _mergeShort(List<TranscriptionSegment> segs) {
    if (segs.length < 2) return segs;
    final out = <TranscriptionSegment>[];
    var buf = StringBuffer();
    String? ts;
    String speaker = segs.first.speaker;
    for (final s in segs) {
      if (s.speaker != speaker && buf.isNotEmpty) {
        out.add(TranscriptionSegment(
            speaker: speaker, timestamp: ts ?? '', content: buf.toString(), language: s.language));
        buf = StringBuffer();
        ts = null;
      }
      speaker = s.speaker;
      ts ??= s.timestamp;
      buf.write('${buf.isEmpty ? '' : ' '}${s.content}');
      if (buf.length > 350) {
        out.add(TranscriptionSegment(
            speaker: speaker, timestamp: ts, content: buf.toString(), language: s.language));
        buf = StringBuffer();
        ts = null;
      }
    }
    if (buf.isNotEmpty) {
      out.add(TranscriptionSegment(
          speaker: speaker, timestamp: ts ?? '', content: buf.toString(),
          language: segs.last.language));
    }
    return out;
  }

  // ───────────────────────────── Gemini speech-to-text models ─────────────────────────────

  /// Models that only do speech-to-text and reject JSON mode / prompts
  /// (e.g. gemini-3.5-transcribe). They need a separate analysis model.
  static bool isSpeechOnlyModel(String model) {
    final m = model.toLowerCase();
    return m.contains('transcribe') || m.contains('whisper');
  }

  /// gemini-3.5-transcribe via the Interactions API with speaker diarization
  /// and word timestamps, then the analysis model builds the report.
  Future<Map<String, dynamic>> _geminiTranscribeModel(
    AudioItem audio,
    ApiKeyEntry key,
    String model,
    AppSettings s,
    ApiKeyEntry? analysisKey,
    ProgressCallback onProgress,
  ) async {
    final mime = normalizeAudioMime(audio.mimeType, audio.name);
    Map<String, dynamic> input;
    if (audio.size <= _geminiInlineLimit) {
      onProgress('Подготовка аудио...');
      final bytes = await readAudioBytes(audio);
      input = {'type': 'audio', 'data': base64Encode(bytes), 'mime_type': mime};
    } else {
      onProgress('Загрузка файла в Gemini (${formatBytes(audio.size)})...');
      final uri = await _geminiUploadFile(audio, key, mime, onProgress);
      input = {'type': 'audio', 'uri': uri, 'mime_type': mime};
    }

    onProgress('Распознавание речи ($model)...');
    final res = await _client
        .post(
          Uri.parse('${_geminiBase(key)}/v1beta/interactions'),
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': key.key.trim(),
          },
          body: jsonEncode({
            'model': 'models/$model',
            'input': [input],
            'generation_config': {
              'transcription_config': {
                'language_codes': <String>[],
                'mode': {
                  'type': 'verbatim',
                  'diarization_mode': 'speaker',
                  'timestamp_granularities': ['word'],
                },
              },
            },
          }),
        )
        .timeout(_requestTimeout);
    _check(res, 'Gemini');
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final segments = parseInteractionTranscript(data);
    if (segments.isEmpty) {
      throw AiException('Речь в записи не распознана.');
    }
    return _analyzeTranscript(segments, s, analysisKey, onProgress);
  }

  /// Groups word annotations (speaker + offsets) into speaker turns.
  static List<TranscriptionSegment> parseInteractionTranscript(Map<String, dynamic> data) {
    final words = <Map>[];
    final texts = <String>[];
    for (final step in (data['steps'] as List? ?? []).whereType<Map>()) {
      for (final c in (step['content'] as List? ?? []).whereType<Map>()) {
        if (c['text'] is String) texts.add(c['text'] as String);
        for (final a in (c['annotations'] as List? ?? []).whereType<Map>()) {
          if (a['type'] == 'word_info') words.add(a);
        }
      }
    }
    if (words.isEmpty) {
      final t = (data['output_text'] ?? texts.join('\n')).toString().trim();
      return t.isEmpty
          ? []
          : [TranscriptionSegment(speaker: 'Спикер', timestamp: '00:00', content: t)];
    }
    double sec(dynamic v) =>
        double.tryParse(v?.toString().replaceAll('s', '') ?? '') ?? 0;
    final speakerNames = <String, String>{};
    String nameOf(String? raw) {
      final k = raw ?? 'spk_1';
      return speakerNames.putIfAbsent(k, () => 'Спикер ${speakerNames.length + 1}');
    }

    final out = <TranscriptionSegment>[];
    String? cur;
    double start = 0;
    final buf = StringBuffer();
    void flush() {
      if (buf.isEmpty) return;
      out.add(TranscriptionSegment(
          speaker: nameOf(cur), timestamp: formatSeconds(start), content: buf.toString().trim()));
      buf.clear();
    }

    for (final w in words) {
      final spk = w['speaker']?.toString();
      final st = sec(w['start_offset']);
      if (buf.isEmpty) {
        cur = spk;
        start = st;
      } else if (spk != cur || buf.length > 600) {
        flush();
        cur = spk;
        start = st;
      }
      final t = (w['text'] ?? '').toString();
      final glue = buf.isEmpty || RegExp(r'^[,.!?;:…)»]').hasMatch(t) ? '' : ' ';
      buf.write('$glue$t');
    }
    flush();
    return out;
  }

  // ───────────────────────────── NVIDIA Riva (build.nvidia.com) ─────────────────────────────

  Future<Map<String, dynamic>> _nvidiaRiva(
    AudioItem audio,
    ApiKeyEntry key,
    String model,
    AppSettings s,
    ApiKeyEntry? analysisKey,
    ProgressCallback onProgress,
  ) async {
    if (!RivaAsrClient.supported || audio.path == null) {
      throw AiException(
          'NVIDIA Whisper работает только в Android-приложении (в веб-версии недоступно).');
    }
    onProgress('Декодирование аудио на телефоне...');
    List<RivaChunk> chunks;
    try {
      chunks = await RivaAsrClient.prepareChunks(audio.path!, 30);
    } catch (e) {
      throw AiException('Не удалось декодировать аудио: $e');
    }
    final fid = (key.functionId?.trim().isNotEmpty ?? false)
        ? key.functionId!.trim()
        : ProviderCatalog.nvidiaWhisperFunctionId;
    final host = (key.baseUrl?.trim().isNotEmpty ?? false) &&
            !key.baseUrl!.contains('integrate.api')
        ? key.baseUrl!.replaceAll(RegExp(r'^https?://'), '').replaceAll(RegExp(r'[:/].*$'), '')
        : ProviderCatalog.nvidiaGrpcHost;

    final segments = <TranscriptionSegment>[];
    String lang = '';
    for (var i = 0; i < chunks.length; i++) {
      onProgress('NVIDIA Whisper: часть ${i + 1} из ${chunks.length}');
      RivaResult r;
      try {
        r = await RivaAsrClient.recognize(
          apiKey: key.key,
          functionId: fid,
          host: host,
          chunk: chunks[i],
          languageCode: 'multi',
        );
      } on RivaException catch (e) {
        throw _rivaError(e);
      }
      if (lang.isEmpty) lang = r.language;
      for (final p in r.pieces) {
        segments.add(TranscriptionSegment(
          speaker: 'Спикер',
          timestamp: formatSeconds(p.startMs / 1000),
          content: p.text,
          language: r.language,
        ));
      }
    }
    if (segments.isEmpty) throw AiException('Речь в записи не распознана.');
    return _analyzeTranscript(segments, s, analysisKey, onProgress);
  }

  AiException _rivaError(RivaException e) {
    switch (e.code) {
      case 16:
      case 7:
        return AiException(
            'NVIDIA: ключ недействителен или нет доступа к Whisper (${e.message}). Проверьте ключ nvapi- на build.nvidia.com.',
            status: 401);
      case 8:
        return AiException('NVIDIA: превышен лимит запросов. ${e.message}', status: 429);
      case 5:
        return AiException(
            'NVIDIA: функция Whisper не найдена — проверьте Function ID в настройках ключа. ${e.message}',
            status: 404);
      case 14:
      case 4:
        return AiException('NVIDIA: сервер недоступен или перегружен. ${e.message}', transient: true);
      default:
        return AiException('NVIDIA: ошибка ${e.code}. ${e.message}');
    }
  }

  Future<String> _chat({
    required ApiKeyEntry key,
    required String baseUrl,
    required String model,
    required List<Map<String, dynamic>> messages,
    bool jsonMode = false,
    int? maxTokens,
  }) async {
    final res = await _client
        .post(
          Uri.parse('$baseUrl/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${key.key.trim()}',
            if (key.provider == ProviderType.openrouter) ...{
              'HTTP-Referer': 'https://github.com/Pynusa/AudioCRM',
              'X-Title': 'EchoScript AI',
            },
          },
          body: jsonEncode({
            'model': model,
            'messages': messages,
            'temperature': 0.2,
            if (maxTokens != null) 'max_tokens': maxTokens,
            if (jsonMode && supportsJsonMode(key.provider, model))
              'response_format': {'type': 'json_object'},
          }),
        )
        .timeout(_requestTimeout);
    _check(res, ProviderCatalog.of(key.provider).shortName);
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final choices = data['choices'] as List?;
    dynamic content;
    if (choices != null && choices.isNotEmpty) {
      final msg = (choices.first as Map)['message'];
      if (msg is Map) content = msg['content'];
    }
    if (content == null || content.toString().trim().isEmpty) {
      final err = data['error']?['message'];
      throw AiException(err?.toString() ?? 'Модель вернула пустой ответ.',
          transient: err == null);
    }
    return content.toString();
  }

  // ───────────────────────────── Model listing / key test ─────────────────────────────

  /// Fetches the list of models available for this key.
  Future<List<String>> listModels(ApiKeyEntry key) async {
    if (key.provider == ProviderType.gemini) {
      final res = await _client.get(
          Uri.parse('${_geminiBase(key)}/v1beta/models?pageSize=1000'),
          headers: {'x-goog-api-key': key.key.trim()}).timeout(const Duration(seconds: 30));
      _check(res, 'Gemini');
      final models = (jsonDecode(res.body)['models'] as List? ?? [])
          .whereType<Map>()
          .where((m) => (m['supportedGenerationMethods'] as List? ?? [])
              .contains('generateContent'))
          .map((m) => (m['name'] as String).replaceFirst('models/', ''))
          .where((n) =>
              n.startsWith('gemini') &&
              !RegExp(r'tts|image|embedding|live|omni|robotics|banana|computer-use|native-audio|translate')
                  .hasMatch(n))
          .toList();
      models.sort((a, b) => b.compareTo(a));
      return models;
    }
    final res = await _client.get(Uri.parse('${_baseUrlOf(key)}/models'),
        headers: {'Authorization': 'Bearer ${key.key.trim()}'}).timeout(const Duration(seconds: 30));
    _check(res, ProviderCatalog.of(key.provider).shortName);
    final list = (jsonDecode(utf8.decode(res.bodyBytes))['data'] as List? ?? [])
        .whereType<Map>()
        .toList();
    if (key.provider == ProviderType.openrouter) {
      // Audio-capable models first.
      final audio = list
          .where((m) => (m['architecture']?['input_modalities'] as List? ?? [])
              .contains('audio'))
          .map((m) => m['id'].toString())
          .toList()
        ..sort();
      final rest = list
          .map((m) => m['id'].toString())
          .where((id) => !audio.contains(id))
          .toList()
        ..sort();
      return [...audio, ...rest];
    }
    final ids = list.map((m) => m['id'].toString()).toList()..sort();
    return ids;
  }

  /// Returns list of OpenRouter model ids that accept audio input (for UI hints).
  Future<String> testKey(ApiKeyEntry key) async {
    if (key.provider == ProviderType.nvidia) {
      final res = await _client.get(Uri.parse('${_baseUrlOf(key)}/models'),
          headers: {'Authorization': 'Bearer ${key.key.trim()}'}).timeout(const Duration(seconds: 30));
      _check(res, 'NVIDIA');
      // /models is public, so verify the key with a tiny chat request.
      await _chat(
        key: key,
        baseUrl: _baseUrlOf(key),
        model: ProviderCatalog.nvidia.chatModels.last.id,
        messages: [
          {'role': 'user', 'content': 'Reply with OK'}
        ],
        maxTokens: 5,
      );
      return 'Ключ NVIDIA работает (Whisper + модели анализа)';
    }
    final models = await listModels(key);
    return 'Ключ работает. Доступно моделей: ${models.length}';
  }

  // ───────────────────────────── Helpers ─────────────────────────────

  void _check(http.Response res, String provider) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    String msg = res.reasonPhrase ?? 'HTTP ${res.statusCode}';
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      final e = j is Map ? j['error'] : null;
      if (e is Map && e['message'] != null) {
        msg = e['message'].toString();
      } else if (e is String) {
        msg = e;
      }
    } catch (_) {}
    final code = res.statusCode;
    final lower = msg.toLowerCase();
    final transient = code == 500 ||
        code == 502 ||
        code == 503 ||
        code == 504 ||
        lower.contains('overloaded') ||
        lower.contains('unavailable') ||
        lower.contains('high demand');
    String human;
    if (code == 400 && (lower.contains('api key not valid') || lower.contains('api_key_invalid'))) {
      human = '$provider: API-ключ недействителен. Проверьте ключ в настройках.';
      throw AiException(human, status: 401);
    } else if (code == 401 || code == 403) {
      human = '$provider: доступ запрещён ($code) — ключ неверный или нет прав. $msg';
    } else if (code == 429) {
      human = '$provider: превышена квота или лимит запросов (429). $msg';
    } else if (code == 404) {
      human = '$provider: модель не найдена (404). Выберите другую модель. $msg';
    } else if (code == 413) {
      human = '$provider: файл слишком большой (413). $msg';
    } else if (transient) {
      human = '$provider: сервер перегружен ($code). $msg';
    } else {
      human = '$provider: ошибка $code. $msg';
    }
    throw AiException(human, transient: transient, status: code);
  }

  /// Extracts "use models/xxx" from a provider error, falls back to our map.
  static String? suggestedReplacement(String message, String model) {
    final m = RegExp(r'use models/([a-z0-9][a-z0-9.\-]+[a-z0-9])',
            caseSensitive: false)
        .firstMatch(message);
    if (m != null) {
      var id = m.group(1)!;
      if (model.startsWith('google/') && !id.startsWith('google/')) {
        id = 'google/$id';
      }
      if (id != model) return id;
    }
    final mapped = ProviderCatalog.migrateModel(model);
    return mapped == model ? null : mapped;
  }

  /// Providers / models known to accept `response_format: json_object`.
  static bool supportsJsonMode(ProviderType p, String model) {
    if (p == ProviderType.nvidia) return false; // varies per model; prompt asks for JSON
    if (model.contains('transcribe') || model.contains('whisper')) return false;
    return true;
  }

  static Map<String, dynamic> parseJsonLoose(String text) {
    var t = text.trim();
    t = t.replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '');
    t = t.replaceFirst(RegExp(r'```\s*$'), '').trim();
    try {
      final v = jsonDecode(t);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
    final s = t.indexOf('{');
    final e = t.lastIndexOf('}');
    if (s >= 0 && e > s) {
      try {
        final v = jsonDecode(t.substring(s, e + 1));
        if (v is Map<String, dynamic>) return v;
      } catch (_) {}
    }
    throw AiException(
        'Модель вернула некорректный JSON (возможно, ответ обрезан из-за длины записи). Попробуйте другую модель или разделите файл.',
        transient: true);
  }

  static String _safeFileName(String name, String mime) {
    if (name.contains('.')) return name;
    final ext = extensionForMime(mime);
    return '$name.$ext';
  }

  static String formatSeconds(double sec) {
    final d = Duration(milliseconds: (sec * 1000).round());
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

}
