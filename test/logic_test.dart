import 'package:echoscript_ai/models/models.dart';
import 'package:echoscript_ai/services/ai_service.dart';
import 'package:echoscript_ai/services/audio_io.dart';
import 'package:echoscript_ai/services/proto_lite.dart';
import 'package:echoscript_ai/services/provider_catalog.dart';
import 'package:echoscript_ai/services/report_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detects provider by key prefix', () {
    expect(ProviderCatalog.detect('AIzaSyXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'),
        ProviderType.gemini);
    expect(ProviderCatalog.detect('sk-or-v1-abc'), ProviderType.openrouter);
    expect(ProviderCatalog.detect('gsk_abc'), ProviderType.groq);
    expect(ProviderCatalog.detect('sk-proj-abc'), ProviderType.openai);
    expect(ProviderCatalog.detect('random'), isNull);
  });

  test('parses JSON wrapped in markdown fences', () {
    final j = AiService.parseJsonLoose(
        '```json\n{"summary":"ok","segments":[{"speaker":"A","timestamp":"00:01","content":"Привет"}]}\n```');
    final r = TranscriptionResult.fromJson(j, fileName: 'a.m4a');
    expect(r.summary, 'ok');
    expect(r.segments.single.content, 'Привет');
  });

  test('normalizes mime types like original server', () {
    expect(normalizeAudioMime('audio/x-m4a'), 'audio/mp4');
    expect(normalizeAudioMime('', 'call.mp3'), 'audio/mp3');
    expect(normalizeAudioMime('application/octet-stream', 'voice.opus'), 'audio/ogg');
  });

  test('formats report', () {
    final r = TranscriptionResult(
      fileName: 'call.m4a',
      summary: 'Резюме',
      segments: [
        TranscriptionSegment(speaker: 'Менеджер', timestamp: '00:05', content: 'Здравствуйте')
      ],
      crmReport: CrmReport(
          summary: 'CRM',
          keyPoints: ['Цена'],
          clientNeeds: ['Скидка'],
          sentiment: 'Позитивное',
          nextSteps: ['Позвонить']),
    );
    expect(ReportFormatter.fullTranscript([r]), '[00:05] Менеджер: Здравствуйте');
    final md = ReportFormatter.markdown([r]);
    expect(md, contains('- [ ] Позвонить'));
    expect(md, contains('⚠️ Скидка'));
  });

  test('picks replacement for retired Gemini model from API error', () {
    const msg = 'Gemini: модель не найдена (404). Выберите другую модель. This model models/gemini-2.5-flash is no longer available to new users. Please update your code to use models/gemini-3.8-flash for the latest features and improvements. We recommend you to use the Interactions API (https://ai.google.dev/gemini-api/docs/get-started).';
    expect(AiService.suggestedReplacement(msg, 'gemini-2.5-flash'), 'gemini-3.8-flash');
    expect(AiService.suggestedReplacement('not found', 'gemini-2.5-pro'), 'gemini-3.8-flash');
    expect(AiService.suggestedReplacement('use the Interactions API', 'gemini-3.8-flash'), isNull);
    expect(ProviderCatalog.migrateModel('gemini-2.5-flash'), 'gemini-3.8-flash');
  });

  test('parses gemini-3.5-transcribe diarized output into speaker turns', () {
    final segs = AiService.parseInteractionTranscript({
      'steps': [
        {
          'type': 'model_output',
          'content': [
            {
              'type': 'text',
              'text': 'Добрый день. Здравствуйте',
              'annotations': [
                {'type': 'word_info', 'text': 'Добрый', 'speaker': 'spk_1', 'start_offset': '0.1s'},
                {'type': 'word_info', 'text': 'день.', 'speaker': 'spk_1', 'start_offset': '0.5s'},
                {'type': 'word_info', 'text': 'Здравствуйте', 'speaker': 'spk_2', 'start_offset': '65.0s'},
              ]
            }
          ]
        }
      ]
    });
    expect(segs.length, 2);
    expect(segs[0].speaker, 'Спикер 1');
    expect(segs[0].content, 'Добрый день.');
    expect(segs[1].speaker, 'Спикер 2');
    expect(segs[1].timestamp, '01:05');
  });

  test('speech-only models are detected', () {
    expect(AiService.isSpeechOnlyModel('gemini-3.5-transcribe'), isTrue);
    expect(AiService.isSpeechOnlyModel('openai/whisper-large-v3'), isTrue);
    expect(AiService.isSpeechOnlyModel('gemini-3.8-flash'), isFalse);
    expect(ProviderCatalog.detect('nvapi-abcdefghijklmnopqrstuvwxyz'), ProviderType.nvidia);
  });

  test('protobuf round-trip for Riva messages', () {
    final cfg = ProtoWriter()
      ..int32(1, 1)
      ..int32(2, 16000)
      ..string(3, 'multi')
      ..boolean(8, true);
    final req = ProtoWriter()
      ..message(1, cfg)
      ..bytes(2, [1, 2, 3]);
    final top = protoDecode(req.toBytes());
    expect(top.first.number, 1);
    final inner = protoDecode(top.first.bytes!);
    expect(inner.firstWhere((f) => f.number == 2).varint, 16000);
    expect(inner.firstWhere((f) => f.number == 3).asString, 'multi');
    expect(top.last.bytes, [1, 2, 3]);
  });
}
