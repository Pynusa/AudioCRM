import 'package:flutter/material.dart';

import '../models/models.dart';

/// How a provider turns audio into a structured report.
enum PipelineKind {
  /// Audio + prompt → JSON in one multimodal call (Gemini, OpenRouter).
  multimodal,

  /// Speech-to-text endpoint first, then a chat model builds the report.
  speechToText,
}

class ModelOption {
  final String id;
  final String title;
  final String? note;
  const ModelOption(this.id, this.title, [this.note]);
}

class ProviderInfo {
  final ProviderType type;
  final String name;
  final String shortName;
  final Color color;
  final IconData icon;
  final String keyHint;
  final String keyUrl;
  final String defaultBaseUrl;
  final PipelineKind pipeline;
  final List<ModelOption> transcribeModels;
  final List<ModelOption> chatModels;
  final String? maxFileNote;

  const ProviderInfo({
    required this.type,
    required this.name,
    required this.shortName,
    required this.color,
    required this.icon,
    required this.keyHint,
    required this.keyUrl,
    required this.defaultBaseUrl,
    required this.pipeline,
    required this.transcribeModels,
    required this.chatModels,
    this.maxFileNote,
  });

  bool get canAnalyzeText => chatModels.isNotEmpty || type == ProviderType.custom;
}

class ProviderCatalog {
  static const gemini = ProviderInfo(
    type: ProviderType.gemini,
    name: 'Google Gemini',
    shortName: 'Gemini',
    color: Color(0xFF4F46E5),
    icon: Icons.auto_awesome,
    keyHint: 'AIza...',
    keyUrl: 'https://aistudio.google.com/app/apikey',
    defaultBaseUrl: 'https://generativelanguage.googleapis.com',
    pipeline: PipelineKind.multimodal,
    transcribeModels: [
      ModelOption('gemini-3.8-flash', 'Gemini 3.8 Flash', 'Рекомендуется: точная и быстрая'),
      ModelOption('gemini-3.5-flash-lite', 'Gemini 3.5 Flash-Lite', 'Самая быстрая и дешёвая'),
      ModelOption('gemini-3.6-flash', 'Gemini 3.6 Flash', 'Предыдущее поколение Flash'),
      ModelOption('gemini-4-argon', 'Gemini 4 Argon', 'Флагман: максимум качества, медленнее'),
      ModelOption('gemini-3.1-pro-preview', 'Gemini 3.1 Pro (preview)'),
      ModelOption('gemini-3.1-flash-lite', 'Gemini 3.1 Flash-Lite'),
      ModelOption('gemini-3.5-transcribe', 'Gemini 3.5 Transcribe',
          'Только распознавание + спикеры; отчёт делает модель анализа'),
      ModelOption('gemini-flash-latest', 'Gemini Flash (latest)', 'Всегда последняя Flash'),
    ],
    chatModels: [
      ModelOption('gemini-3.8-flash', 'Gemini 3.8 Flash'),
      ModelOption('gemini-3.5-flash-lite', 'Gemini 3.5 Flash-Lite'),
      ModelOption('gemini-4-argon', 'Gemini 4 Argon'),
    ],
    maxFileNote: 'До ~2 ГБ (большие файлы загружаются через Files API)',
  );

  static const openai = ProviderInfo(
    type: ProviderType.openai,
    name: 'OpenAI',
    shortName: 'OpenAI',
    color: Color(0xFF10A37F),
    icon: Icons.blur_on,
    keyHint: 'sk-...',
    keyUrl: 'https://platform.openai.com/api-keys',
    defaultBaseUrl: 'https://api.openai.com/v1',
    pipeline: PipelineKind.speechToText,
    transcribeModels: [
      ModelOption('whisper-1', 'Whisper', 'Таймкоды по сегментам'),
      ModelOption('gpt-4o-transcribe', 'GPT-4o Transcribe', 'Высокая точность, без таймкодов'),
      ModelOption('gpt-4o-mini-transcribe', 'GPT-4o mini Transcribe', 'Дешевле, без таймкодов'),
    ],
    chatModels: [
      ModelOption('gpt-4.1-mini', 'GPT-4.1 mini'),
      ModelOption('gpt-4.1', 'GPT-4.1'),
      ModelOption('gpt-4o-mini', 'GPT-4o mini'),
      ModelOption('gpt-4o', 'GPT-4o'),
    ],
    maxFileNote: 'Лимит OpenAI — 25 МБ на файл',
  );

  static const groq = ProviderInfo(
    type: ProviderType.groq,
    name: 'Groq',
    shortName: 'Groq',
    color: Color(0xFFF55036),
    icon: Icons.bolt,
    keyHint: 'gsk_...',
    keyUrl: 'https://console.groq.com/keys',
    defaultBaseUrl: 'https://api.groq.com/openai/v1',
    pipeline: PipelineKind.speechToText,
    transcribeModels: [
      ModelOption('whisper-large-v3-turbo', 'Whisper Large v3 Turbo', 'Очень быстро'),
      ModelOption('whisper-large-v3', 'Whisper Large v3', 'Точнее'),
    ],
    chatModels: [
      ModelOption('llama-3.3-70b-versatile', 'Llama 3.3 70B'),
      ModelOption('openai/gpt-oss-120b', 'GPT-OSS 120B'),
      ModelOption('openai/gpt-oss-20b', 'GPT-OSS 20B'),
      ModelOption('llama-3.1-8b-instant', 'Llama 3.1 8B Instant'),
    ],
    maxFileNote: 'Лимит Groq — 25 МБ (бесплатно) / 100 МБ',
  );

  static const openrouter = ProviderInfo(
    type: ProviderType.openrouter,
    name: 'OpenRouter',
    shortName: 'OpenRouter',
    color: Color(0xFF6366F1),
    icon: Icons.hub,
    keyHint: 'sk-or-...',
    keyUrl: 'https://openrouter.ai/keys',
    defaultBaseUrl: 'https://openrouter.ai/api/v1',
    pipeline: PipelineKind.multimodal,
    transcribeModels: [
      ModelOption('google/gemini-3.8-flash', 'Gemini 3.8 Flash', 'через OpenRouter'),
      ModelOption('google/gemini-3.5-flash-lite', 'Gemini 3.5 Flash-Lite', 'через OpenRouter'),
      ModelOption('google/gemini-4-argon', 'Gemini 4 Argon', 'через OpenRouter'),
      ModelOption('google/gemini-3.6-flash', 'Gemini 3.6 Flash'),
      ModelOption('openai/gpt-audio', 'GPT Audio'),
      ModelOption('mistralai/voxtral-small-24b-2507', 'Voxtral Small'),
    ],
    chatModels: [
      ModelOption('google/gemini-3.8-flash', 'Gemini 3.8 Flash'),
      ModelOption('anthropic/claude-sonnet-5.5', 'Claude Sonnet 5.5'),
      ModelOption('openai/gpt-4.1-mini', 'GPT-4.1 mini'),
      ModelOption('deepseek/deepseek-v4.1-flash', 'DeepSeek V4.1 Flash'),
    ],
    maxFileNote: 'Рекомендуется до ~20 МБ',
  );

  /// build.nvidia.com — Whisper Large v3 hosted on NVCF (Riva gRPC) for
  /// speech-to-text + OpenAI-compatible LLMs on integrate.api.nvidia.com.
  static const nvidia = ProviderInfo(
    type: ProviderType.nvidia,
    name: 'NVIDIA NIM (build.nvidia.com)',
    shortName: 'NVIDIA',
    color: Color(0xFF76B900),
    icon: Icons.memory,
    keyHint: 'nvapi-...',
    keyUrl: 'https://build.nvidia.com/openai/whisper-large-v3',
    defaultBaseUrl: 'https://integrate.api.nvidia.com/v1',
    pipeline: PipelineKind.speechToText,
    transcribeModels: [
      ModelOption(nvidiaWhisperModel, 'Whisper Large v3', 'Распознавание речи на GPU NVIDIA'),
    ],
    chatModels: [
      ModelOption('deepseek-ai/deepseek-v4.1-flash', 'DeepSeek V4.1 Flash', 'Анализ текста'),
      ModelOption('moonshotai/kimi-k2.6', 'Kimi K2.6'),
      ModelOption('nvidia/nemotron-3-super-120b-a12b', 'Nemotron 3 Super 120B'),
      ModelOption('mistralai/mistral-large-4-1t-a52b', 'Mistral Large 4'),
      ModelOption('openai/gpt-oss-20b', 'GPT-OSS 20B'),
    ],
    maxFileNote: 'Аудио декодируется на телефоне и отправляется частями по 30 сек',
  );

  static const nvidiaWhisperModel = 'openai/whisper-large-v3';

  /// NVCF function id of the hosted Whisper Large v3 (from the build.nvidia.com
  /// API page). Can be overridden per key in the "Function ID" field.
  static const nvidiaWhisperFunctionId = 'b702f636-f60c-4a3d-a6f4-f3568c13bd7d';
  static const nvidiaGrpcHost = 'grpc.nvcf.nvidia.com';

  static const custom = ProviderInfo(
    type: ProviderType.custom,
    name: 'Свой (OpenAI-совместимый)',
    shortName: 'Custom',
    color: Color(0xFF64748B),
    icon: Icons.dns_outlined,
    keyHint: 'ключ API',
    keyUrl: '',
    defaultBaseUrl: 'https://',
    pipeline: PipelineKind.speechToText,
    transcribeModels: [
      ModelOption('whisper-1', 'whisper-1'),
    ],
    chatModels: [],
  );

  static const all = [gemini, openai, groq, openrouter, nvidia, custom];

  /// Models Google has retired / closed for new users → current replacement.
  static const retiredModels = <String, String>{
    'gemini-2.5-flash': 'gemini-3.8-flash',
    'gemini-2.5-pro': 'gemini-3.8-flash',
    'gemini-2.5-flash-lite': 'gemini-3.5-flash-lite',
    'gemini-2.0-flash': 'gemini-3.8-flash',
    'gemini-2.0-flash-lite': 'gemini-3.5-flash-lite',
    'gemini-pro-latest': 'gemini-3.8-flash',
    'gemini-3-pro-preview': 'gemini-3.8-flash',
    'gemini-3.1-flash-lite-preview': 'gemini-3.1-flash-lite',
    'google/gemini-2.5-flash': 'google/gemini-3.8-flash',
    'google/gemini-2.5-pro': 'google/gemini-3.8-flash',
    'google/gemini-2.5-flash-lite': 'google/gemini-3.5-flash-lite',
    'openai/gpt-4o-audio-preview': 'openai/gpt-audio',
    'anthropic/claude-sonnet-4': 'anthropic/claude-sonnet-5.5',
    'deepseek/deepseek-chat': 'deepseek/deepseek-v4.1-flash',
  };

  static String migrateModel(String m) => retiredModels[m] ?? m;

  static ProviderInfo of(ProviderType t) =>
      all.firstWhere((p) => p.type == t, orElse: () => gemini);

  /// Guesses the provider from the key prefix.
  static ProviderType? detect(String key) {
    final k = key.trim();
    if (k.startsWith('AIza')) return ProviderType.gemini;
    if (k.startsWith('nvapi-')) return ProviderType.nvidia;
    if (k.startsWith('sk-or-')) return ProviderType.openrouter;
    if (k.startsWith('gsk_')) return ProviderType.groq;
    if (k.startsWith('sk-')) return ProviderType.openai;
    return null;
  }
}
