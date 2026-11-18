import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/models.dart';
import 'ai_service.dart';
import 'provider_catalog.dart';
import 'proxy.dart';

enum AppStatus { idle, processing, success, error }

class AppState extends ChangeNotifier {
  static const _kKeys = 'api_keys_v1';
  static const _kSettings = 'settings_v1';
  static const _kHistory = 'history_v1';
  static const _kModelCache = 'model_cache_v1';

  final ProxyRouter proxy = ProxyRouter();
  late final AiService ai = AiService(proxy);
  late SharedPreferences _prefs;

  List<ApiKeyEntry> keys = [];
  AppSettings settings = const AppSettings();
  List<HistorySession> history = [];

  /// Remote model lists cached per key id.
  Map<String, List<String>> modelCache = {};

  // Current session
  List<AudioItem> queue = [];
  List<TranscriptionResult> results = [];
  AppStatus status = AppStatus.idle;
  String? error;
  int processingIndex = -1;
  String progressStep = '';
  int elapsed = 0;
  Timer? _timer;
  bool _canceled = false;
  bool loaded = false;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    await proxy.load();
    try {
      final k = _prefs.getString(_kKeys);
      if (k != null) {
        keys = (jsonDecode(k) as List)
            .whereType<Map>()
            .map((e) => ApiKeyEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      final s = _prefs.getString(_kSettings);
      if (s != null) {
        settings = AppSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
      }
      final h = _prefs.getString(_kHistory);
      if (h != null) {
        history = (jsonDecode(h) as List)
            .whereType<Map>()
            .map((e) => HistorySession.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      final mc = _prefs.getString(_kModelCache);
      if (mc != null) {
        modelCache = (jsonDecode(mc) as Map).map((k, v) =>
            MapEntry(k.toString(), (v as List).map((e) => e.toString()).toList()));
      }
    } catch (e) {
      debugPrint('Load error: $e');
    }
    _migrateRetiredModels();
    _ensureValidSelection();
    loaded = true;
    notifyListeners();
  }

  /// Replaces models that providers have shut down / closed for new users.
  void _migrateRetiredModels() {
    final m = ProviderCatalog.migrateModel;
    final st = settings;
    final next = st.copyWith(
      transcribeModel: m(st.transcribeModel),
      fallbackModel: m(st.fallbackModel),
      analysisModel: m(st.analysisModel),
    );
    if (next.transcribeModel != st.transcribeModel ||
        next.fallbackModel != st.fallbackModel ||
        next.analysisModel != st.analysisModel) {
      settings = next;
      _prefs.setString(_kSettings, jsonEncode(settings.toJson()));
    }
  }

  ThemeMode get themeMode => switch (settings.themeMode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  // ───────────────────── Keys ─────────────────────

  ApiKeyEntry? keyById(String? id) {
    if (id == null) return null;
    for (final k in keys) {
      if (k.id == id) return k;
    }
    return null;
  }

  ApiKeyEntry? get transcribeKey => keyById(settings.transcribeKeyId);
  ApiKeyEntry? get analysisKey => keyById(settings.analysisKeyId);

  bool get isReady => transcribeKey != null && settings.transcribeModel.isNotEmpty;

  bool get needsAnalysisStep {
    final k = transcribeKey;
    if (k == null) return false;
    return ProviderCatalog.of(k.provider).pipeline == PipelineKind.speechToText ||
        AiService.isSpeechOnlyModel(settings.transcribeModel);
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<ApiKeyEntry> addKey({
    required ProviderType provider,
    required String key,
    String? label,
    String? baseUrl,
    String? functionId,
  }) async {
    final info = ProviderCatalog.of(provider);
    final count = keys.where((k) => k.provider == provider).length;
    final entry = ApiKeyEntry(
      id: _newId(),
      provider: provider,
      label: (label?.trim().isNotEmpty ?? false)
          ? label!.trim()
          : '${info.shortName} ${count + 1}',
      key: key.trim(),
      baseUrl: baseUrl?.trim().isEmpty ?? true ? null : baseUrl!.trim(),
      functionId:
          functionId?.trim().isEmpty ?? true ? null : functionId!.trim(),
    );
    keys.add(entry);
    _ensureValidSelection();
    await _saveKeys();
    await _saveSettings();
    notifyListeners();
    return entry;
  }

  Future<void> updateKey(ApiKeyEntry entry) async {
    final i = keys.indexWhere((k) => k.id == entry.id);
    if (i >= 0) keys[i] = entry;
    await _saveKeys();
    notifyListeners();
  }

  Future<void> removeKey(String id) async {
    keys.removeWhere((k) => k.id == id);
    modelCache.remove(id);
    _ensureValidSelection();
    await _saveKeys();
    await _saveSettings();
    notifyListeners();
  }

  /// Bulk import: accepts plain lists, `.env` lines (`GEMINI_API_KEY=...`) or
  /// JSON exported by this app. Returns number of keys added.
  Future<int> importKeys(String raw) async {
    var added = 0;
    final existing = keys.map((k) => k.key).toSet();
    final t = raw.trim();
    // JSON backup from this app
    if (t.startsWith('[') || t.startsWith('{')) {
      try {
        final v = jsonDecode(t);
        if (v is Map) await _restoreExtras(v);
        final list = v is List ? v : (v is Map ? (v['keys'] as List? ?? []) : []);
        for (final e in list.whereType<Map>()) {
          final entry = ApiKeyEntry.fromJson(Map<String, dynamic>.from(e));
          if (entry.key.isEmpty || existing.contains(entry.key)) continue;
          keys.add(ApiKeyEntry(
              id: _newId() + added.toString(),
              provider: entry.provider,
              label: entry.label,
              key: entry.key,
              baseUrl: entry.baseUrl,
              functionId: entry.functionId));
          existing.add(entry.key);
          added++;
        }
        if (added > 0) {
          _ensureValidSelection();
          await _saveKeys();
          await _saveSettings();
          notifyListeners();
          return added;
        }
      } catch (_) {}
    }
    final tokenRe = RegExp(r'(AIza[0-9A-Za-z_\-]{30,}|nvapi-[0-9A-Za-z_\-]{20,}|sk-or-[0-9A-Za-z_\-]{20,}|gsk_[0-9A-Za-z]{20,}|sk-[0-9A-Za-z_\-]{20,})');
    for (final line in t.split(RegExp(r'[\r\n,; ]+'))) {
      for (final m in tokenRe.allMatches(line)) {
        final key = m.group(0)!;
        if (existing.contains(key)) continue;
        final p = ProviderCatalog.detect(key);
        if (p == null) continue;
        await addKey(provider: p, key: key);
        existing.add(key);
        added++;
      }
    }
    return added;
  }

    String exportKeysJson() {
    Map<String, dynamic>? amo;
    try {
      final raw = _prefs.getString('amo_settings_v1');
      if (raw != null) {
        amo = Map<String, dynamic>.from(jsonDecode(raw) as Map)
          ..remove('userId')
          ..remove('userName');
      }
    } catch (_) {}
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'EchoScript AI',
      'keys': keys.map((k) => k.toJson()).toList(),
      'proxy': proxy.settings.toJson(),
      if (amo != null) 'amo': amo,
    });
  }

  /// Восстанавливает из резервной копии настройки прокси и amoCRM.
  Future<void> _restoreExtras(Map v) async {
    try {
      final p = v['proxy'];
      if (p is Map && '${p['host'] ?? ''}'.isNotEmpty) {
        await _prefs.setString('proxy_v1', jsonEncode(p));
        await proxy.load();
      }
      final a = v['amo'];
      if (a is Map) {
        var cur = <String, dynamic>{};
        final raw = _prefs.getString('amo_settings_v1');
        if (raw != null) {
          cur = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        }
        final next = Map<String, dynamic>.from(a)
          ..remove('userId')
          ..remove('userName')
          ..removeWhere((k, val) => val == null || val == '');
        await _prefs.setString(
            'amo_settings_v1', jsonEncode({...cur, ...next}));
      }
    } catch (e) {
      debugPrint('Restore error: $e');
    }
  }


  void _ensureValidSelection() {
    if (keyById(settings.transcribeKeyId) == null) {
      final k = keys.isNotEmpty ? keys.first : null;
      settings = settings.copyWith(
        transcribeKeyId: k?.id ?? '',
        transcribeModel: k == null
            ? settings.transcribeModel
            : ProviderCatalog.of(k.provider).transcribeModels.first.id,
        fallbackModel: '',
      );
    }
    final tk = transcribeKey;
    if (tk != null && needsAnalysisStep && keyById(settings.analysisKeyId) == null) {
      // Pick the best key for analysis: same key if it can chat, else Gemini.
      ApiKeyEntry? best;
      if (ProviderCatalog.of(tk.provider).chatModels.isNotEmpty) best = tk;
      best ??= keys.where((k) => ProviderCatalog.of(k.provider).chatModels.isNotEmpty).firstOrNull;
      if (best != null) {
        settings = settings.copyWith(
          analysisKeyId: best.id,
          analysisModel: ProviderCatalog.of(best.provider).chatModels.first.id,
        );
      }
    }
  }

  // ───────────────────── Settings ─────────────────────

  Future<void> updateSettings(AppSettings s) async {
    settings = s;
    _ensureValidSelection();
    await _saveSettings();
    notifyListeners();
  }

  Future<void> selectTranscribeKey(ApiKeyEntry k) async {
    final changedProvider = transcribeKey?.provider != k.provider;
    settings = settings.copyWith(
      transcribeKeyId: k.id,
      transcribeModel: changedProvider
          ? ProviderCatalog.of(k.provider).transcribeModels.first.id
          : settings.transcribeModel,
      fallbackModel: changedProvider ? '' : settings.fallbackModel,
    );
    _ensureValidSelection();
    await _saveSettings();
    notifyListeners();
  }

  Future<List<String>> fetchModels(ApiKeyEntry k) async {
    final list = await ai.listModels(k);
    modelCache[k.id] = list;
    await _prefs.setString(_kModelCache, jsonEncode(modelCache));
    notifyListeners();
    return list;
  }

  // ───────────────────── Queue & processing ─────────────────────

  void addAudio(List<AudioItem> items) {
    if (status == AppStatus.success) {
      results = [];
      status = AppStatus.idle;
    }
    queue = [...queue, ...items];
    error = null;
    notifyListeners();
  }

  void removeAudio(int i) {
    queue = [...queue]..removeAt(i);
    notifyListeners();
  }

  void reset() {
    queue = [];
    results = [];
    status = AppStatus.idle;
    error = null;
    processingIndex = -1;
    notifyListeners();
  }

  void cancel() {
    _canceled = true;
    _stopTimer();
    status = results.isNotEmpty ? AppStatus.success : AppStatus.idle;
    processingIndex = -1;
    notifyListeners();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    WakelockPlus.disable().catchError((_) {});
  }

  Future<void> transcribeAll() async {
    final key = transcribeKey;
    if (key == null || queue.isEmpty) return;
    _canceled = false;
    status = AppStatus.processing;
    error = null;
    results = [];
    elapsed = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsed++;
      notifyListeners();
    });
    WakelockPlus.enable().catchError((_) {});
    notifyListeners();

    try {
      for (var i = 0; i < queue.length; i++) {
        if (_canceled) return;
        processingIndex = i;
        progressStep = 'Подготовка...';
        notifyListeners();
        final r = await ai.transcribe(
          audio: queue[i],
          key: key,
          rotationKeys: keys,
          settings: settings,
          analysisKey: needsAnalysisStep ? analysisKey : null,
          onProgress: (s) {
            progressStep = s;
            notifyListeners();
          },
          isCanceled: () => _canceled,
          onModelReplaced: (oldM, newM) {
            final st = settings;
            settings = st.copyWith(
              transcribeModel:
                  st.transcribeModel == oldM ? newM : st.transcribeModel,
              fallbackModel: st.fallbackModel == oldM ? newM : st.fallbackModel,
            );
            _saveSettings();
            notifyListeners();
          },
        );
        if (_canceled) return;
        results = [...results, r];
        notifyListeners();
      }
      _stopTimer();
      status = AppStatus.success;
      processingIndex = -1;
      queue = [];
      await _addToHistory(results);
    } catch (e) {
      if (_canceled) return;
      _stopTimer();
      processingIndex = -1;
      error = e.toString();
      status = AppStatus.error;
      // Keep finished results if some files succeeded.
      if (results.isNotEmpty) {
        await _addToHistory(results);
        final done = results.length;
        queue = queue.sublist(done);
      }
    }
    notifyListeners();
  }

  // ───────────────────── History ─────────────────────

  Future<void> _addToHistory(List<TranscriptionResult> r) async {
    history.insert(
        0, HistorySession(id: _newId(), createdAt: DateTime.now(), results: r));
    if (history.length > 100) history = history.sublist(0, 100);
    await _saveHistory();
  }

  Future<void> deleteHistory(String id) async {
    history.removeWhere((h) => h.id == id);
    await _saveHistory();
    notifyListeners();
  }

  Future<void> clearHistory() async {
    history = [];
    await _saveHistory();
    notifyListeners();
  }

  // ───────────────────── Persistence ─────────────────────

  Future<void> _saveKeys() =>
      _prefs.setString(_kKeys, jsonEncode(keys.map((k) => k.toJson()).toList()));
  Future<void> _saveSettings() =>
      _prefs.setString(_kSettings, jsonEncode(settings.toJson()));
  Future<void> _saveHistory() => _prefs.setString(
      _kHistory, jsonEncode(history.map((h) => h.toJson()).toList()));
}
