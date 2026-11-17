import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import '../services/audio_io.dart';

/// Microphone recorder (AAC/m4a on Android, webm/opus on web preview).
class RecorderPanel extends StatefulWidget {
  final void Function(AudioItem) onRecorded;
  const RecorderPanel({super.key, required this.onRecorded});

  @override
  State<RecorderPanel> createState() => _RecorderPanelState();
}

class _RecorderPanelState extends State<RecorderPanel>
    with SingleTickerProviderStateMixin {
  final _rec = AudioRecorder();
  bool _recording = false;
  bool _paused = false;
  Duration _dur = Duration.zero;
  Timer? _timer;
  StreamSubscription<Amplitude>? _ampSub;
  final List<double> _levels = List.filled(40, 0.05, growable: true);
  String? _error;

  @override
  void dispose() {
    _timer?.cancel();
    _ampSub?.cancel();
    _rec.dispose();
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      if (!await _rec.hasPermission()) {
        setState(() => _error =
            'Нет доступа к микрофону. Разрешите его в настройках телефона: Настройки → Приложения → EchoScript AI → Разрешения.');
        return;
      }
      String path = '';
      RecordConfig config;
      if (kIsWeb) {
        config = const RecordConfig(encoder: AudioEncoder.opus, numChannels: 1);
      } else {
        final dir = await getTemporaryDirectory();
        path =
            '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
        config = const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
          numChannels: 1,
          noiseSuppress: true,
          echoCancel: false,
          autoGain: true,
        );
      }
      await _rec.start(config, path: path);
      WakelockPlus.enable().catchError((_) {});
      _dur = Duration.zero;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_paused) setState(() => _dur += const Duration(seconds: 1));
      });
      _ampSub = _rec
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen((a) {
        final v = ((a.current + 50) / 50).clamp(0.03, 1.0);
        setState(() {
          _levels.removeAt(0);
          _levels.add(v);
        });
      });
      setState(() {
        _recording = true;
        _paused = false;
      });
    } catch (e) {
      setState(() => _error = 'Не удалось начать запись: $e');
    }
  }

  Future<void> _togglePause() async {
    if (_paused) {
      await _rec.resume();
    } else {
      await _rec.pause();
    }
    setState(() => _paused = !_paused);
  }

  Future<void> _stop() async {
    _timer?.cancel();
    await _ampSub?.cancel();
    final path = await _rec.stop();
    WakelockPlus.disable().catchError((_) {});
    setState(() {
      _recording = false;
      _paused = false;
      _levels.fillRange(0, _levels.length, 0.05);
    });
    if (path == null) return;
    final now = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    final name =
        'Запись ${p(now.day)}.${p(now.month)} ${p(now.hour)}-${p(now.minute)}.${kIsWeb ? 'webm' : 'm4a'}';
    if (kIsWeb) {
      final bytes = await http.readBytes(Uri.parse(path));
      widget.onRecorded(AudioItem(
          name: name,
          bytes: bytes,
          mimeType: 'audio/webm',
          size: bytes.length,
          duration: _dur));
    } else {
      widget.onRecorded(AudioItem(
          name: name,
          path: path,
          mimeType: 'audio/mp4',
          size: await fileLength(path),
          duration: _dur));
    }
  }

  Future<void> _discard() async {
    _timer?.cancel();
    await _ampSub?.cancel();
    await _rec.cancel();
    WakelockPlus.disable().catchError((_) {});
    setState(() {
      _recording = false;
      _paused = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        const SizedBox(height: 8),
        SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (final l in _levels)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 4,
                  height: math.max(4, 60 * l),
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: _recording
                        ? cs.primary.withValues(alpha: _paused ? 0.3 : 0.9)
                        : cs.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          formatDuration(_dur),
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w300,
                color: _recording ? cs.onSurface : cs.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          _recording
              ? (_paused ? 'Пауза' : 'Идёт запись...')
              : 'Нажмите, чтобы начать запись',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_recording)
              IconButton.filledTonal(
                iconSize: 26,
                onPressed: _discard,
                tooltip: 'Удалить запись',
                icon: const Icon(Icons.delete_outline),
              ),
            const SizedBox(width: 20),
            GestureDetector(
              onTap: _recording ? _stop : _start,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: _recording
                        ? [const Color(0xFFEF4444), const Color(0xFFDC2626)]
                        : [cs.primary, const Color(0xFF7C3AED)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (_recording ? Colors.red : cs.primary)
                          .withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  _recording ? Icons.stop_rounded : Icons.mic_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
            const SizedBox(width: 20),
            if (_recording)
              IconButton.filledTonal(
                iconSize: 26,
                onPressed: _togglePause,
                tooltip: _paused ? 'Продолжить' : 'Пауза',
                icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
              ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.error, fontSize: 13)),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}
