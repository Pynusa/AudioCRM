/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import { TranscriptionResponse } from '../types';

/**
 * Robust copy-to-clipboard with fallback for iframe and restricted browser contexts.
 */
export async function copyToClipboard(text: string): Promise<boolean> {
  if (!text) return false;

  try {
    if (navigator?.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
      return true;
    }
  } catch (err) {
    console.warn('[Clipboard] navigator.clipboard.writeText failed, using fallback:', err);
  }

  try {
    const textArea = document.createElement('textarea');
    textArea.value = text;
    textArea.style.position = 'fixed';
    textArea.style.top = '0';
    textArea.style.left = '0';
    textArea.style.width = '2em';
    textArea.style.height = '2em';
    textArea.style.padding = '0';
    textArea.style.border = 'none';
    textArea.style.outline = 'none';
    textArea.style.boxShadow = 'none';
    textArea.style.background = 'transparent';
    textArea.style.opacity = '0';
    document.body.appendChild(textArea);
    textArea.focus();
    textArea.select();

    const successful = document.execCommand('copy');
    document.body.removeChild(textArea);
    return successful;
  } catch (err) {
    console.error('[Clipboard] ExecCommand copy failed:', err);
    return false;
  }
}

/**
 * Formats all transcribed dialogue segments across all files into clean text.
 */
export function formatFullTranscript(
  results: (TranscriptionResponse & { fileName: string })[]
): string {
  if (!results || results.length === 0) return '';

  return results
    .map((result, idx) => {
      const header = results.length > 1 ? `=== ${result.fileName || `Файл ${idx + 1}`} ===\n` : '';
      const dialogue = result.segments
        .map(seg => `[${seg.timestamp}] ${seg.speaker}: ${seg.content}`)
        .join('\n');

      return header ? `${header}\n${dialogue}` : dialogue;
    })
    .join('\n\n' + '—'.repeat(40) + '\n\n');
}

/**
 * Formats a single file's transcribed dialogue into clean text.
 */
export function formatSingleTranscript(
  result: TranscriptionResponse & { fileName: string }
): string {
  if (!result || !result.segments) return '';

  return result.segments
    .map(seg => `[${seg.timestamp}] ${seg.speaker}: ${seg.content}`)
    .join('\n');
}

/**
 * Formats the complete consolidated report (Summaries + CRM + Full Transcription).
 */
export function formatFullReport(
  results: (TranscriptionResponse & { fileName: string })[]
): string {
  if (!results || results.length === 0) return '';

  const parts: string[] = [];

  parts.push(`КОНСОЛИДИРОВАННЫЙ ОТЧЁТ ПО ПЕРЕГОВОРАМ (${results.length} файл(ов))`);
  parts.push('='.repeat(50));

  // 1. Общие резюме
  parts.push('\n### 1. ОБЩЕЕ РЕЗЮМЕ ПЕРЕГОВОРОВ');
  results.forEach((res, i) => {
    parts.push(`\n[${res.fileName || `Файл ${i + 1}`}]`);
    if (res.summary) parts.push(res.summary);
    if (res.crmReport?.summary && res.crmReport.summary !== res.summary) {
      parts.push(`CRM-резюме: ${res.crmReport.summary}`);
    }
  });

  // 2. Ключевые моменты
  parts.push('\n\n### 2. КЛЮЧЕВЫЕ МОМЕНТЫ');
  results.forEach((res, i) => {
    if (res.crmReport?.keyPoints?.length) {
      parts.push(`\n[${res.fileName || `Файл ${i + 1}`}]`);
      res.crmReport.keyPoints.forEach(p => parts.push(`• ${p}`));
    }
  });

  // 3. Потребности и боли
  parts.push('\n\n### 3. ПОТРЕБНОСТИ И БОЛИ КЛИЕНТОВ');
  results.forEach((res, i) => {
    if (res.crmReport?.clientNeeds?.length) {
      parts.push(`\n[${res.fileName || `Файл ${i + 1}`}]`);
      res.crmReport.clientNeeds.forEach(n => parts.push(`→ ${n}`));
    }
  });

  // 4. Следующие шаги
  parts.push('\n\n### 4. СЛЕДУЮЩИЕ ШАГИ И ЗАДАЧИ');
  results.forEach((res, i) => {
    if (res.crmReport?.nextSteps?.length) {
      parts.push(`\n[${res.fileName || `Файл ${i + 1}`}]`);
      res.crmReport.nextSteps.forEach(s => parts.push(`✓ ${s}`));
    }
  });

  // 5. Полные расшифровки
  parts.push('\n\n### 5. ПОЛНАЯ РАСШИФРОВКА РЕПЛИК');
  parts.push('='.repeat(50));
  results.forEach((res, i) => {
    parts.push(`\n[${res.fileName || `Файл ${i + 1}`}]`);
    res.segments.forEach(seg => {
      parts.push(`[${seg.timestamp}] ${seg.speaker}: ${seg.content}`);
    });
  });

  return parts.join('\n');
}
