/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import http from 'http';
import path from 'path';
import { fileURLToPath } from 'url';
import express, { Request, Response } from 'express';
import { WebSocketServer, WebSocket } from 'ws';
import { GoogleGenAI, Type, Modality, ThinkingLevel } from '@google/genai';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const server = http.createServer(app);

// Configure body-parser limits for audio base64 uploads (up to 100MB)
app.use(express.json({ limit: '100mb' }));
app.use(express.urlencoded({ extended: true, limit: '100mb' }));

// Initialize GoogleGenAI client on the server side
const getApiKey = (): string => {
  return (process.env.GEMINI_API_KEY || process.env.API_KEY || process.env.GEMINI_API_KEY1 || '').trim();
};

const getAIClient = (): GoogleGenAI => {
  const apiKey = getApiKey();
  return new GoogleGenAI({
    apiKey,
    httpOptions: {
      headers: {
        'User-Agent': 'aistudio-build',
      },
    },
  });
};

// Healthcheck endpoint
app.get('/api/health', (_req: Request, res: Response) => {
  const hasKey = Boolean(getApiKey());
  res.json({ status: 'ok', hasKey });
});

// Helper function to detect transient Gemini API errors (503 High Demand / 429 Quota / UNAVAILABLE / Timeouts)
function isTransientError(error: any): boolean {
  if (!error) return false;

  const code =
    error.status ||
    error.code ||
    error.statusCode ||
    error.error?.code ||
    error.error?.status;

  if (
    code === 503 ||
    code === '503' ||
    code === 429 ||
    code === '429' ||
    code === 'UNAVAILABLE' ||
    code === 'RESOURCE_EXHAUSTED' ||
    code === 'DEADLINE_EXCEEDED'
  ) {
    return true;
  }

  const fullText = (
    (typeof error === 'string' ? error : '') +
    ' ' +
    (error.message || '') +
    ' ' +
    (error.statusText || '') +
    ' ' +
    JSON.stringify(error)
  ).toLowerCase();

  return (
    fullText.includes('503') ||
    fullText.includes('unavailable') ||
    fullText.includes('high demand') ||
    fullText.includes('spikes in demand') ||
    fullText.includes('temporarily unavailable') ||
    fullText.includes('overloaded') ||
    fullText.includes('429') ||
    fullText.includes('resource_exhausted') ||
    fullText.includes('rate limit') ||
    fullText.includes('too many requests') ||
    fullText.includes('deadline') ||
    fullText.includes('timeout') ||
    fullText.includes('timed out') ||
    fullText.includes('не ответила') ||
    fullText.includes('секунд') ||
    fullText.includes('превысила время ожидания')
  );
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

function timeoutPromise<T>(promise: Promise<T>, ms: number, timeoutMsg: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error(timeoutMsg));
    }, ms);
    promise
      .then((res) => {
        clearTimeout(timer);
        resolve(res);
      })
      .catch((err) => {
        clearTimeout(timer);
        reject(err);
      });
  });
}

function normalizeAudioMimeType(mimeType: string, filename?: string): string {
  let mime = (mimeType || '').trim().toLowerCase();

  // Normalize common variations and wrappers
  if (mime.includes('x-m4a') || mime === 'audio/m4a' || mime.includes('m4a')) {
    return 'audio/mp4';
  }
  if (mime.includes('mp3') || mime.includes('mpeg')) {
    return 'audio/mp3';
  }
  if (mime.includes('wav')) {
    return 'audio/wav';
  }
  if (mime.includes('webm')) {
    return 'audio/webm';
  }
  if (mime.includes('aac')) {
    return 'audio/aac';
  }
  if (mime.includes('ogg')) {
    return 'audio/ogg';
  }

  // Fallback by file extension if mimeType is empty or generic application/octet-stream
  if (filename) {
    const ext = filename.split('.').pop()?.toLowerCase();
    if (ext === 'm4a' || ext === 'mp4') return 'audio/mp4';
    if (ext === 'mp3') return 'audio/mp3';
    if (ext === 'wav') return 'audio/wav';
    if (ext === 'webm') return 'audio/webm';
    if (ext === 'aac') return 'audio/aac';
    if (ext === 'ogg') return 'audio/ogg';
  }

  return mime || 'audio/mp4';
}

// Candidate models in preference order: fast, stable GA flash model first for immediate audio processing, then preview model
const CANDIDATE_MODELS = ['gemini-2.5-flash', 'gemini-3.8-flash'];

async function generateContentWithRetryAndFallback(
  ai: GoogleGenAI,
  requestParams: { contents: any; config: any }
) {
  let lastError: any = null;

  for (let mIdx = 0; mIdx < CANDIDATE_MODELS.length; mIdx++) {
    const model = CANDIDATE_MODELS[mIdx];
    const maxAttempts = 2;

    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        console.log(`[Server] Generating content with ${model} (attempt ${attempt}/${maxAttempts})...`);

        // Configure model-specific parameters:
        // gemini-3.8-flash defaults to ThinkingLevel.MEDIUM which adds reasoning delay on audio.
        // ThinkingLevel.LOW reduces latency while maintaining high accuracy.
        const modelConfig = { ...requestParams.config };
        if (model.startsWith('gemini-3') || model.startsWith('gemini-4')) {
          modelConfig.thinkingConfig = { thinkingLevel: ThinkingLevel.LOW };
        } else {
          delete modelConfig.thinkingConfig;
        }

        // Apply a generous 120-second timeout per attempt to allow large 15-30 minute audio files to finish
        const generatePromise = ai.models.generateContent({
          model,
          contents: requestParams.contents,
          config: modelConfig,
        });

        const response = await timeoutPromise(
          generatePromise,
          120000,
          `Модель ${model} не ответила за 120 секунд`
        );

        if (response && response.text) {
          console.log(`[Server] Successfully received response from ${model}`);
          return { response, usedModel: model };
        }
        throw new Error(`Модель ${model} вернула пустой ответ.`);
      } catch (err: any) {
        lastError = err;
        const transient = isTransientError(err);
        const isTimeout =
          String(err?.message || '').includes('не ответила') ||
          String(err?.message || '').includes('секунд') ||
          String(err?.message || '').includes('timeout');

        console.warn(`[Server] Error from ${model} (attempt ${attempt}/${maxAttempts}, transient=${transient}, isTimeout=${isTimeout}):`, err?.message || err);

        // If it's a non-transient error (e.g. invalid credentials, bad format), fail fast
        if (!transient && !isTimeout) {
          throw err;
        }

        // If a model timed out, do NOT repeat the same slow model — immediately jump to the next candidate model
        if (isTimeout && mIdx < CANDIDATE_MODELS.length - 1) {
          console.warn(`[Server] Model ${model} timed out. Switching immediately to fallback model ${CANDIDATE_MODELS[mIdx + 1]}...`);
          await sleep(500);
          break; // break inner loop to try next model in CANDIDATE_MODELS
        }

        // If transient error (e.g. 503 spike) and we have retry attempts left on this model
        if (attempt < maxAttempts) {
          const delay = attempt * 1500;
          console.log(`[Server] High demand/transient spike detected. Retrying ${model} in ${(delay / 1000).toFixed(1)}s...`);
          await sleep(delay);
          continue;
        }

        // If we exhausted attempts on this model, switch to fallback model
        if (mIdx < CANDIDATE_MODELS.length - 1) {
          console.warn(`[Server] Switching to fallback model ${CANDIDATE_MODELS[mIdx + 1]}...`);
          await sleep(1000);
          break;
        }
      }
    }
  }

  throw lastError;
}

// Audio transcription endpoint
app.post('/api/transcribe', async (req: Request, res: Response) => {
  try {
    const { base64Audio, mimeType, fileName } = req.body;

    if (!base64Audio) {
      return res.status(400).json({ error: 'Параметр base64Audio обязателен.' });
    }

    const apiKey = getApiKey();
    if (!apiKey) {
      return res.status(500).json({
        error: 'API-ключ Gemini не настроен на сервере. Убедитесь, что GEMINI_API_KEY задан в секретах (Settings -> Secrets).'
      });
    }

    const normalizedMime = normalizeAudioMimeType(mimeType, fileName);
    const ai = getAIClient();

    const prompt = `
    You are an expert audio transcription assistant.
    Process the provided audio file and generate a detailed transcription and CRM analysis in Russian.
    
    Requirements:
    1. Identify distinct speakers (e.g., Speaker 1, Speaker 2, or Менеджер, Клиент).
    2. Provide accurate timestamps for each segment (Format: MM:SS).
    3. Detect the primary language of each segment.
    4. Identify the primary emotion of the speaker in this segment (Happy, Sad, Angry, Neutral).
    5. Provide a comprehensive summary of the entire audio in Russian.
    6. Generate a detailed CRM report in Russian including:
       - Summary of the negotiation (Суть переговоров).
       - Key points discussed (Ключевые моменты).
       - Identified client needs or pain points (Потребности и боли клиента).
       - Overall sentiment of the client (Настроение клиента).
       - Specific recommendations for next steps (Рекомендуемые следующие шаги).
    
    Output Format: JSON object with the following structure:
    {
      "summary": "...",
      "crmReport": {
        "summary": "...",
        "keyPoints": ["..."],
        "clientNeeds": ["..."],
        "sentiment": "...",
        "nextSteps": ["..."]
      },
      "segments": [
        {
          "speaker": "...",
          "timestamp": "...",
          "content": "...",
          "language": "...",
          "language_code": "...",
          "emotion": "..."
        }
      ]
    }
    
    IMPORTANT: Group conversation logically (e.g., 30-90 seconds per segment or main speaking turns) to ensure thorough coverage of the entire audio without exceeding JSON token limits.
    `;

    console.log(`[Server] Transcribing audio "${fileName || 'audio'}". Mime: ${normalizedMime} (original: ${mimeType}), Size: ${(base64Audio.length / 1024 / 1024).toFixed(2)} MB`);

    const { response, usedModel } = await generateContentWithRetryAndFallback(ai, {
      contents: {
        parts: [
          {
            inlineData: {
              mimeType: normalizedMime,
              data: base64Audio,
            },
          },
          {
            text: prompt,
          },
        ],
      },
      config: {
        responseMimeType: 'application/json',
        responseSchema: {
          type: Type.OBJECT,
          properties: {
            summary: { type: Type.STRING },
            crmReport: {
              type: Type.OBJECT,
              properties: {
                summary: { type: Type.STRING },
                keyPoints: { type: Type.ARRAY, items: { type: Type.STRING } },
                clientNeeds: { type: Type.ARRAY, items: { type: Type.STRING } },
                sentiment: { type: Type.STRING },
                nextSteps: { type: Type.ARRAY, items: { type: Type.STRING } },
              },
              required: ['summary', 'keyPoints', 'clientNeeds', 'sentiment', 'nextSteps'],
            },
            segments: {
              type: Type.ARRAY,
              items: {
                type: Type.OBJECT,
                properties: {
                  speaker: { type: Type.STRING },
                  timestamp: { type: Type.STRING },
                  content: { type: Type.STRING },
                  language: { type: Type.STRING },
                  language_code: { type: Type.STRING },
                  emotion: { type: Type.STRING },
                },
                required: ['speaker', 'timestamp', 'content', 'language', 'language_code', 'emotion'],
              },
            },
          },
          required: ['summary', 'segments', 'crmReport'],
        },
      },
    });

    const text = response.text;
    if (!text) {
      return res.status(502).json({ error: 'Модель Gemini вернула пустой ответ.' });
    }

    let parsedData: any;
    try {
      parsedData = JSON.parse(text);
    } catch {
      // Clean possible markdown wrapper if present
      const cleaned = text.replace(/^```json\s*/i, '').replace(/```\s*$/i, '').trim();
      parsedData = JSON.parse(cleaned);
    }

    console.log(`[Server] Transcription completed successfully via ${usedModel}`);
    return res.json(parsedData);
  } catch (error: any) {
    console.error('[Server] Transcription error:', error);
    const transient = isTransientError(error);
    const message = transient
      ? 'Серверы Gemini сейчас испытывают высокий спрос (пиковая нагрузка). Мы автоматически повторили запрос и попробовали резервную модель, но модель всё ещё перегружена. Пожалуйста, подождите 1–2 минуты и попробуйте снова.'
      : (error.message || 'Ошибка обработки аудио');
    return res.status(transient ? 503 : 500).json({ error: message, details: error.message });
  }
});

// Streaming generation endpoint (Server-Sent Events) with fallback
app.post('/api/generate/stream', async (req: Request, res: Response) => {
  try {
    const { prompt, model = 'gemini-3.8-flash', systemInstruction } = req.body;
    if (!prompt) {
      return res.status(400).json({ error: 'Параметр prompt обязателен.' });
    }

    const ai = getAIClient();
    const candidateModels = [model, 'gemini-2.5-flash'];
    let responseStream: any = null;

    for (const m of candidateModels) {
      try {
        responseStream = await ai.models.generateContentStream({
          model: m,
          contents: prompt,
          config: systemInstruction ? { systemInstruction } : undefined,
        });
        break;
      } catch (err: any) {
        if (isTransientError(err) && m !== candidateModels[candidateModels.length - 1]) {
          console.warn(`[Server] Streaming model ${m} transient error, attempting fallback to ${candidateModels[1]}...`);
          await sleep(1500);
          continue;
        }
        throw err;
      }
    }

    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');

    for await (const chunk of responseStream) {
      if (chunk.text) {
        res.write(`data: ${JSON.stringify({ text: chunk.text })}\n\n`);
      }
    }
    res.write('data: [DONE]\n\n');
    res.end();
  } catch (error: any) {
    console.error('[Server] Streaming generation error:', error);
    const transient = isTransientError(error);
    const errorMsg = transient
      ? 'Серверы Gemini временно испытывают высокий спрос. Пожалуйста, попробуйте снова через минуту.'
      : (error.message || 'Ошибка генерации');
    res.write(`data: ${JSON.stringify({ error: errorMsg })}\n\n`);
    res.end();
  }
});

// WebSocket Server for Gemini Live API
const wss = new WebSocketServer({ noServer: true });

wss.on('connection', async (clientWs: WebSocket) => {
  console.log('[Server WebSocket] Client connected to Live API');
  try {
    const apiKey = getApiKey();
    if (!apiKey) {
      clientWs.send(JSON.stringify({ error: 'API key not configured on server' }));
      clientWs.close();
      return;
    }

    const ai = getAIClient();
    const session = await ai.live.connect({
      model: 'gemini-3.8-live',
      config: {
        responseModalities: [Modality.AUDIO],
        speechConfig: {
          voiceConfig: { prebuiltVoiceConfig: { voiceName: 'Zephyr' } },
        },
        systemInstruction: 'You are a helpful assistant for voice interactions in Russian and English.',
      },
      callbacks: {
        onmessage: (message: any) => {
          for (const part of message.serverContent?.modelTurn?.parts ?? []) {
            if (part.inlineData?.data) {
              clientWs.send(JSON.stringify({ audio: part.inlineData.data }));
            }
          }
          if (message.serverContent?.interrupted) {
            clientWs.send(JSON.stringify({ interrupted: true }));
          }
        },
      },
    });

    clientWs.on('message', (data: any) => {
      try {
        const parsed = JSON.parse(data.toString());
        if (parsed.audio) {
          session.sendRealtimeInput({
            audio: { data: parsed.audio, mimeType: 'audio/pcm;rate=16000' },
          });
        }
      } catch (err) {
        console.error('[Server WebSocket] Error handling message:', err);
      }
    });

    clientWs.on('close', () => {
      console.log('[Server WebSocket] Client disconnected');
      session.close?.();
    });
  } catch (err: any) {
    console.error('[Server WebSocket] Live API connection error:', err);
    clientWs.send(JSON.stringify({ error: err.message || 'Live API connection error' }));
    clientWs.close();
  }
});

server.on('upgrade', (request, socket, head) => {
  const pathname = request.url ? new URL(request.url, `http://${request.headers.host}`).pathname : '';
  if (pathname === '/api/live' || pathname === '/live') {
    wss.handleUpgrade(request, socket, head, (ws) => {
      wss.emit('connection', ws, request);
    });
  }
});

// Setup Vite in Dev or Static Assets in Production
const isProd = process.env.NODE_ENV === 'production';
const PORT = parseInt(process.env.PORT || '3000', 10);

async function startServer() {
  if (!isProd) {
    const { createServer: createViteServer } = await import('vite');
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: 'spa',
    });
    app.use(vite.middlewares);
  } else {
    const distPath = path.resolve(__dirname, 'dist');
    app.use(express.static(distPath));
    app.get('*', (_req: Request, res: Response) => {
      res.sendFile(path.resolve(distPath, 'index.html'));
    });
  }

  server.listen(PORT, '0.0.0.0', () => {
    console.log(`[Server] EchoScript server listening on http://0.0.0.0:${PORT} (${isProd ? 'production' : 'development'})`);
  });
}

startServer();
