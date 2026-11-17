# EchoScript AI

Android-приложение (Flutter) для транскрибации аудио с разделением по спикерам, таймкодами и CRM-отчётом по переговорам.
Работает напрямую с API нейросетей — без собственного сервера.

## Возможности

- Запись с микрофона и загрузка нескольких аудиофайлов (MP3, M4A, WAV, OGG/OPUS, AAC, FLAC, WEBM, MP4…)
- Приём файлов через «Поделиться» из Диктофона Samsung, Telegram, WhatsApp, «Моих файлов»
- Несколько API-ключей, ротация ключей при исчерпании квоты, импорт списком / из `.env` / JSON
- Выбор модели распознавания, резервной модели и модели анализа (в т.ч. загрузка списка моделей из API)
- Провайдеры: **Google Gemini**, **OpenAI**, **Groq**, **OpenRouter**, **NVIDIA NIM** (Whisper Large v3 через Riva gRPC), любой **OpenAI-совместимый** endpoint
- Отчёт: резюме, ключевые моменты, потребности клиента, настроение, следующие шаги, полный диалог
- Экспорт в TXT/Markdown, копирование, история расшифровок, светлая/тёмная тема

## Стек

- Flutter 3.35.4 / Dart 3.9.2, Material 3, `provider`
- Android: minSdk 24, target/compileSdk 36, AGP 8.9.1, Gradle 8.12, Kotlin 2.1.0
- Хранение: `shared_preferences` (ключи, настройки, история)
- Native (Kotlin): приём share-интентов, декодер аудио в WAV 16 кГц для NVIDIA

## Структура

```
lib/
  main.dart                 — точка входа, темы
  models/models.dart        — модели данных
  screens/                  — Расшифровка, История, Ключи и модели, отчёт
  services/ai_service.dart  — запросы ко всем провайдерам, промт, повторы
  services/app_state.dart   — состояние и хранение
  services/provider_catalog.dart — провайдеры и модели
  services/nvidia_riva_*.dart, proto_lite.dart — NVIDIA Riva gRPC
  widgets/                  — запись, выбор модели
android/app/src/main/kotlin/com/echoscriptai/transcriber/
  MainActivity.kt, AudioDecoder.kt
web_app/                    — исходная веб-версия (React + Express), в сборку не входит
```

## Сборка

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Для release-подписи нужны `android/key.properties` и keystore (не хранятся в репозитории).
Без них сборка подписывается debug-ключом.
