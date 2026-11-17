/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import { TranscriptionResponse } from '../types';

/**
 * Downloads a string content as a file with UTF-8 encoding.
 */
export function downloadFile(
  content: string,
  filename: string,
  mimeType: string = 'text/plain;charset=utf-8'
): void {
  // Add UTF-8 BOM (\uFEFF) so Windows Notepad and Excel open Cyrillic text correctly
  const bom = '\uFEFF';
  const blob = new Blob([bom + content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.setAttribute('download', filename);
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}

/**
 * Generates formatted Markdown (.md) document.
 */
export function generateMarkdownReport(
  results: (TranscriptionResponse & { fileName: string })[],
  onlyDialogue: boolean = false
): string {
  if (!results || results.length === 0) return '';

  const dateStr = new Date().toLocaleString('ru-RU', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });

  const lines: string[] = [];

  if (onlyDialogue) {
    lines.push(`# Расшифровка переговоров`);
    lines.push(`*Дата экспорта: ${dateStr}* | *Всего файлов: ${results.length}*\n`);

    results.forEach((res, idx) => {
      lines.push(`## ${res.fileName || `Файл ${idx + 1}`}\n`);
      if (res.segments && res.segments.length > 0) {
        res.segments.forEach((seg) => {
          lines.push(`- **\`${seg.timestamp}\` ${seg.speaker}:** ${seg.content}`);
        });
      } else {
        lines.push(`*Реплики отсутствуют*`);
      }
      lines.push('');
    });

    return lines.join('\n');
  }

  // Full Consolidated Report in Markdown
  lines.push(`# Консолидированный отчёт по переговорам`);
  lines.push(`*Дата экспорта: ${dateStr}* | *Всего файлов: ${results.length}*\n`);

  // 1. Общие резюме
  lines.push(`## 1. Общее резюме переговоров`);
  results.forEach((res, idx) => {
    lines.push(`### 📄 ${res.fileName || `Файл ${idx + 1}`}`);
    if (res.summary) {
      lines.push(`> ${res.summary}\n`);
    }
    if (res.crmReport?.summary && res.crmReport.summary !== res.summary) {
      lines.push(`**Резюме для CRM:** ${res.crmReport.summary}\n`);
    }
  });

  // 2. Ключевые моменты
  lines.push(`## 2. Ключевые моменты`);
  results.forEach((res, idx) => {
    if (res.crmReport?.keyPoints?.length) {
      lines.push(`### 📄 ${res.fileName || `Файл ${idx + 1}`}`);
      res.crmReport.keyPoints.forEach((point) => {
        lines.push(`- ${point}`);
      });
      lines.push('');
    }
  });

  // 3. Потребности и боли
  lines.push(`## 3. Потребности и боли клиентов`);
  results.forEach((res, idx) => {
    if (res.crmReport?.clientNeeds?.length) {
      lines.push(`### 📄 ${res.fileName || `Файл ${idx + 1}`}`);
      res.crmReport.clientNeeds.forEach((need) => {
        lines.push(`- ⚠️ ${need}`);
      });
      lines.push('');
    }
  });

  // 4. Следующие шаги
  lines.push(`## 4. Рекомендуемые следующие шаги`);
  results.forEach((res, idx) => {
    if (res.crmReport?.nextSteps?.length) {
      lines.push(`### 📄 ${res.fileName || `Файл ${idx + 1}`}`);
      res.crmReport.nextSteps.forEach((step) => {
        lines.push(`- [ ] ${step}`);
      });
      lines.push('');
    }
  });

  // 5. Полная расшифровка
  lines.push(`## 5. Полная расшифровка диалогов`);
  results.forEach((res, idx) => {
    lines.push(`### 📄 ${res.fileName || `Файл ${idx + 1}`}`);
    lines.push(`*Всего реплик: ${res.segments.length}*\n`);
    res.segments.forEach((seg) => {
      lines.push(`- **\`${seg.timestamp}\` ${seg.speaker}:** ${seg.content}`);
    });
    lines.push('');
  });

  return lines.join('\n');
}

/**
 * Generates formatted Plain Text (.txt) document.
 */
export function generatePlainTextReport(
  results: (TranscriptionResponse & { fileName: string })[],
  onlyDialogue: boolean = false
): string {
  if (!results || results.length === 0) return '';

  const dateStr = new Date().toLocaleString('ru-RU', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });

  const lines: string[] = [];

  if (onlyDialogue) {
    lines.push(`РАСШИФРОВКА ПЕРЕГОВОРОВ`);
    lines.push(`Дата экспорта: ${dateStr}`);
    lines.push(`Всего файлов: ${results.length}`);
    lines.push('='.repeat(60));
    lines.push('');

    results.forEach((res, idx) => {
      if (results.length > 1) {
        lines.push(`\n=== [${res.fileName || `Файл ${idx + 1}`}] ===\n`);
      }
      res.segments.forEach((seg) => {
        lines.push(`[${seg.timestamp}] ${seg.speaker}: ${seg.content}`);
      });
      lines.push('');
    });

    return lines.join('\n');
  }

  // Full Plain Text Report
  lines.push(`КОНСОЛИДИРОВАННЫЙ ОТЧЁТ И РАСШИФРОВКА ПЕРЕГОВОРОВ`);
  lines.push(`Дата экспорта: ${dateStr}`);
  lines.push(`Количество проанализированных файлов: ${results.length}`);
  lines.push('='.repeat(60));
  lines.push('');

  // 1. Общие резюме
  lines.push(`1. ОБЩЕЕ РЕЗЮМЕ ПЕРЕГОВОРОВ`);
  lines.push('-'.repeat(40));
  results.forEach((res, idx) => {
    lines.push(`\n[Файл: ${res.fileName || `Файл ${idx + 1}`}]`);
    if (res.summary) lines.push(res.summary);
    if (res.crmReport?.summary && res.crmReport.summary !== res.summary) {
      lines.push(`CRM-резюме: ${res.crmReport.summary}`);
    }
  });
  lines.push('\n');

  // 2. Ключевые моменты
  lines.push(`2. КЛЮЧЕВЫЕ МОМЕНТЫ`);
  lines.push('-'.repeat(40));
  results.forEach((res, idx) => {
    if (res.crmReport?.keyPoints?.length) {
      lines.push(`\n[Файл: ${res.fileName || `Файл ${idx + 1}`}]`);
      res.crmReport.keyPoints.forEach((point) => {
        lines.push(`• ${point}`);
      });
    }
  });
  lines.push('\n');

  // 3. Потребности и боли
  lines.push(`3. ПОТРЕБНОСТИ И БОЛИ КЛИЕНТОВ`);
  lines.push('-'.repeat(40));
  results.forEach((res, idx) => {
    if (res.crmReport?.clientNeeds?.length) {
      lines.push(`\n[Файл: ${res.fileName || `Файл ${idx + 1}`}]`);
      res.crmReport.clientNeeds.forEach((need) => {
        lines.push(`→ ${need}`);
      });
    }
  });
  lines.push('\n');

  // 4. Следующие шаги
  lines.push(`4. СЛЕДУЮЩИЕ ШАГИ И ЗАДАЧИ`);
  lines.push('-'.repeat(40));
  results.forEach((res, idx) => {
    if (res.crmReport?.nextSteps?.length) {
      lines.push(`\n[Файл: ${res.fileName || `Файл ${idx + 1}`}]`);
      res.crmReport.nextSteps.forEach((step) => {
        lines.push(`[ ] ${step}`);
      });
    }
  });
  lines.push('\n');

  // 5. Полные расшифровки
  lines.push(`5. ПОЛНАЯ РАСШИФРОВКА ДИАЛОГОВ`);
  lines.push('='.repeat(60));
  results.forEach((res, idx) => {
    lines.push(`\n=== [Файл: ${res.fileName || `Файл ${idx + 1}`}] ===`);
    res.segments.forEach((seg) => {
      lines.push(`[${seg.timestamp}] ${seg.speaker}: ${seg.content}`);
    });
    lines.push('');
  });

  return lines.join('\n');
}

/**
 * Helper to export and trigger file download.
 */
export function exportResults(
  results: (TranscriptionResponse & { fileName: string })[],
  format: 'txt' | 'md',
  onlyDialogue: boolean = false
): void {
  const dateSlug = new Date().toISOString().slice(0, 10);
  const baseName =
    results.length === 1 && results[0].fileName
      ? results[0].fileName.replace(/\.[^/.]+$/, '')
      : 'echoscript_combined';

  const typeSlug = onlyDialogue ? 'transcript' : 'report';
  const filename = `${baseName}_${typeSlug}_${dateSlug}.${format}`;

  if (format === 'md') {
    const content = generateMarkdownReport(results, onlyDialogue);
    downloadFile(content, filename, 'text/markdown;charset=utf-8');
  } else {
    const content = generatePlainTextReport(results, onlyDialogue);
    downloadFile(content, filename, 'text/plain;charset=utf-8');
  }
}
