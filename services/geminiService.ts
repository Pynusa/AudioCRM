/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import { TranscriptionSegment, CRMReport } from "../types";

/**
 * Transcribes audio via the server-side Gemini API endpoint (/api/transcribe).
 * The client communicates with the server without needing an API key in the browser.
 */
export const transcribeAudio = async (
  base64Audio: string,
  mimeType: string,
  fileName?: string
): Promise<{ segments: TranscriptionSegment[]; summary: string; crmReport: CRMReport }> => {
  const base64SizeMB = (base64Audio.length / 1024 / 1024).toFixed(2);
  console.log(`[GeminiService] Requesting server transcription for "${fileName || 'audio'}". Mime: ${mimeType}, Base64: ${base64SizeMB} MB`);

  const controller = new AbortController();
  // 8 minutes timeout to allow large audio files (up to 25MB) to process without premature client-side abort
  const timeoutId = setTimeout(() => {
    controller.abort();
  }, 480000);

  try {
    const response = await fetch('/api/transcribe', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        base64Audio,
        mimeType,
        fileName,
      }),
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      let errorMessage = 'Ошибка при расшифровке на сервере';
      try {
        const errorData = await response.json();
        if (errorData?.error) {
          errorMessage = errorData.error;
        }
      } catch {
        errorMessage = `Сервер вернул ошибку: ${response.status} ${response.statusText}`;
      }
      throw new Error(errorMessage);
    }

    const data = await response.json();
    return data;
  } catch (error: any) {
    clearTimeout(timeoutId);
    if (error.name === 'AbortError') {
      throw new Error('Превышено время ожидания ответа от сервера (8 минут). Для очень длинных записей (более 40 минут) попробуйте разделить файл на части.');
    }
    console.error('[GeminiService] Transcription error:', error);
    throw error;
  }
};

/**
 * Connects to the server-side Gemini Live API WebSocket bridge.
 */
export const connectLiveAPI = (callbacks: {
  onAudioChunk?: (base64Audio: string) => void;
  onInterrupted?: () => void;
  onError?: (err: any) => void;
  onClose?: () => void;
}) => {
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  const wsUrl = `${protocol}//${window.location.host}/api/live`;
  const ws = new WebSocket(wsUrl);

  ws.onmessage = (event) => {
    try {
      const msg = JSON.parse(event.data);
      if (msg.audio && callbacks.onAudioChunk) {
        callbacks.onAudioChunk(msg.audio);
      }
      if (msg.interrupted && callbacks.onInterrupted) {
        callbacks.onInterrupted();
      }
      if (msg.error && callbacks.onError) {
        callbacks.onError(msg.error);
      }
    } catch (err) {
      console.error('[GeminiService] Error parsing Live WebSocket message:', err);
    }
  };

  ws.onerror = (err) => {
    callbacks.onError?.(err);
  };

  ws.onclose = () => {
    callbacks.onClose?.();
  };

  return {
    sendAudio: (base64Pcm: string) => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ audio: base64Pcm }));
      }
    },
    close: () => {
      ws.close();
    },
  };
};