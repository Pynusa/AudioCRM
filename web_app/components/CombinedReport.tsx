import React, { useState } from 'react';
import { TranscriptionResponse } from '../types';
import { FileAudio, MessageSquare, FileText, Sparkles, CheckCircle2, Target, ArrowRightCircle, Copy, Check, Download } from 'lucide-react';
import { copyToClipboard, formatFullTranscript, formatFullReport, formatSingleTranscript } from '../services/clipboardService';
import { exportResults } from '../services/exportService';
import ExportDropdown from './ExportDropdown';

interface CombinedReportProps {
  results: (TranscriptionResponse & { fileName: string })[];
}

const CombinedReport: React.FC<CombinedReportProps> = ({ results }) => {
  const [copiedType, setCopiedType] = useState<'transcripts' | 'report' | null>(null);
  const [copiedFileIndex, setCopiedFileIndex] = useState<number | null>(null);

  if (results.length === 0) return null;

  const handleCopy = async (type: 'transcripts' | 'report') => {
    const text = type === 'transcripts' ? formatFullTranscript(results) : formatFullReport(results);
    const success = await copyToClipboard(text);
    if (success) {
      setCopiedType(type);
      setTimeout(() => setCopiedType(null), 2500);
    }
  };

  const handleCopySingle = async (result: TranscriptionResponse & { fileName: string }, index: number) => {
    const text = formatSingleTranscript(result);
    const success = await copyToClipboard(text);
    if (success) {
      setCopiedFileIndex(index);
      setTimeout(() => setCopiedFileIndex(null), 2500);
    }
  };

  return (
    <div className="space-y-10 animate-in fade-in slide-in-from-bottom-4 duration-500 pb-20">
      {/* Header Banner */}
      <div className="bg-indigo-600 dark:bg-indigo-900 p-6 rounded-2xl border border-indigo-500 dark:border-indigo-800 shadow-lg text-white">
        <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
          <div>
            <h3 className="text-xl font-bold flex items-center mb-1">
              <FileText size={24} className="mr-3 shrink-0" />
              Единый консолидированный отчет ({results.length} {results.length === 1 ? 'файл' : 'файла(ов)'})
            </h3>
            <p className="text-indigo-100 text-sm opacity-90">
              Вся информация из проанализированных записей объединена в один непрерывный документ для удобства копирования.
            </p>
          </div>
          <div className="flex flex-wrap items-center gap-2 shrink-0">
            <button
              onClick={() => handleCopy('transcripts')}
              className="inline-flex items-center px-4 py-2.5 bg-white text-indigo-700 hover:bg-indigo-50 font-semibold text-sm rounded-xl shadow-sm transition-all focus:outline-none focus:ring-2 focus:ring-white/80 active:scale-95"
              aria-label="Скопировать текст расшифровки"
            >
              {copiedType === 'transcripts' ? (
                <>
                  <Check size={16} className="mr-2 text-emerald-600" />
                  <span>Скопировано!</span>
                </>
              ) : (
                <>
                  <Copy size={16} className="mr-2" />
                  <span>Скопировать текст</span>
                </>
              )}
            </button>
            <button
              onClick={() => handleCopy('report')}
              className="inline-flex items-center px-3.5 py-2.5 bg-indigo-500/30 hover:bg-indigo-500/50 text-white font-medium text-sm rounded-xl border border-white/20 transition-all focus:outline-none focus:ring-2 focus:ring-white/80 active:scale-95"
              aria-label="Скопировать весь отчёт с CRM"
            >
              {copiedType === 'report' ? (
                <>
                  <Check size={16} className="mr-2 text-emerald-300" />
                  <span>Отчёт скопирован!</span>
                </>
              ) : (
                <>
                  <Copy size={16} className="mr-2 opacity-80" />
                  <span>Весь отчёт с CRM</span>
                </>
              )}
            </button>
            <ExportDropdown results={results} variant="banner" label="Скачать файл" />
          </div>
        </div>
      </div>

      {/* 1. Unified Summaries Section */}
      <section className="space-y-4">
        <div className="flex items-center space-x-2 border-b border-slate-200 dark:border-slate-800 pb-2">
          <Sparkles className="text-indigo-500" size={20} />
          <h2 className="text-xl font-bold text-slate-900 dark:text-white">Общее резюме переговоров</h2>
        </div>
        <div className="space-y-4">
          {results.map((result, index) => (
            <div key={index} className="bg-white dark:bg-slate-900 p-5 rounded-xl border border-slate-100 dark:border-slate-800 shadow-sm">
              <div className="flex items-center text-xs font-bold text-slate-400 uppercase tracking-widest mb-2">
                <FileAudio size={12} className="mr-1" /> {result.fileName}
              </div>
              <p className="text-slate-700 dark:text-slate-300 leading-relaxed italic border-l-4 border-indigo-200 dark:border-indigo-800 pl-4">
                {result.summary}
              </p>
              {result.crmReport && (
                <div className="mt-4 pt-4 border-t border-slate-50 dark:border-slate-800">
                  <h4 className="text-sm font-bold text-slate-900 dark:text-white mb-2">Детальное резюме (CRM):</h4>
                  <p className="text-sm text-slate-600 dark:text-slate-400 leading-relaxed">
                    {result.crmReport.summary}
                  </p>
                </div>
              )}
            </div>
          ))}
        </div>
      </section>

      {/* 2. Unified Key Points Section */}
      <section className="space-y-4">
        <div className="flex items-center space-x-2 border-b border-slate-200 dark:border-slate-800 pb-2">
          <CheckCircle2 className="text-indigo-500" size={20} />
          <h2 className="text-xl font-bold text-slate-900 dark:text-white">Ключевые моменты (все файлы)</h2>
        </div>
        <div className="bg-white dark:bg-slate-900 p-6 rounded-xl border border-slate-100 dark:border-slate-800 shadow-sm">
          <div className="space-y-6">
            {results.map((result, index) => (
              result.crmReport && (
                <div key={index}>
                  <h4 className="text-xs font-bold text-slate-400 uppercase mb-3 flex items-center">
                    <span className="w-6 h-px bg-slate-200 dark:bg-slate-800 mr-2"></span>
                    Из файла: {result.fileName}
                  </h4>
                  <ul className="grid grid-cols-1 md:grid-cols-2 gap-3">
                    {result.crmReport.keyPoints.map((point, i) => (
                      <li key={i} className="text-sm text-slate-600 dark:text-slate-300 flex items-start bg-slate-50 dark:bg-slate-800/50 p-3 rounded-lg">
                        <span className="text-indigo-500 mr-2 font-bold">•</span>
                        {point}
                      </li>
                    ))}
                  </ul>
                </div>
              )
            ))}
          </div>
        </div>
      </section>

      {/* 3. Unified Client Needs Section */}
      <section className="space-y-4">
        <div className="flex items-center space-x-2 border-b border-slate-200 dark:border-slate-800 pb-2">
          <Target className="text-emerald-500" size={20} />
          <h2 className="text-xl font-bold text-slate-900 dark:text-white">Потребности и боли клиентов</h2>
        </div>
        <div className="bg-white dark:bg-slate-900 p-6 rounded-xl border border-slate-100 dark:border-slate-800 shadow-sm">
          <div className="space-y-6">
            {results.map((result, index) => (
              result.crmReport && (
                <div key={index}>
                  <h4 className="text-xs font-bold text-slate-400 uppercase mb-3 flex items-center">
                    <span className="w-6 h-px bg-slate-200 dark:bg-slate-800 mr-2"></span>
                    Из файла: {result.fileName}
                  </h4>
                  <ul className="space-y-2">
                    {result.crmReport.clientNeeds.map((need, i) => (
                      <li key={i} className="text-sm text-slate-600 dark:text-slate-300 flex items-start bg-emerald-50/30 dark:bg-emerald-900/10 p-3 rounded-lg border border-emerald-100/50 dark:border-emerald-900/30">
                        <span className="text-emerald-500 mr-2 font-bold">→</span>
                        {need}
                      </li>
                    ))}
                  </ul>
                </div>
              )
            ))}
          </div>
        </div>
      </section>

      {/* 4. Unified Next Steps Section */}
      <section className="space-y-4">
        <div className="flex items-center space-x-2 border-b border-slate-200 dark:border-slate-800 pb-2">
          <ArrowRightCircle className="text-amber-500" size={20} />
          <h2 className="text-xl font-bold text-slate-900 dark:text-white">Следующие шаги и задачи</h2>
        </div>
        <div className="bg-white dark:bg-slate-900 p-6 rounded-xl border border-slate-100 dark:border-slate-800 shadow-sm">
          <div className="space-y-6">
            {results.map((result, index) => (
              result.crmReport && (
                <div key={index}>
                  <h4 className="text-xs font-bold text-slate-400 uppercase mb-3 flex items-center">
                    <span className="w-6 h-px bg-slate-200 dark:bg-slate-800 mr-2"></span>
                    Из файла: {result.fileName}
                  </h4>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    {result.crmReport.nextSteps.map((step, i) => (
                      <div key={i} className="flex items-center p-3 bg-amber-50/50 dark:bg-amber-900/10 rounded-lg border border-amber-100 dark:border-amber-900/30 text-sm text-slate-700 dark:text-slate-300">
                        <div className="w-2 h-2 rounded-full bg-amber-500 mr-3 shrink-0"></div>
                        {step}
                      </div>
                    ))}
                  </div>
                </div>
              )
            ))}
          </div>
        </div>
      </section>

      {/* 5. Unified Transcripts Section */}
      <section className="space-y-4">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-2 border-b border-slate-200 dark:border-slate-800 gap-2">
          <div className="flex items-center space-x-2">
            <MessageSquare className="text-indigo-500" size={20} />
            <h2 className="text-xl font-bold text-slate-900 dark:text-white">Полные расшифровки (последовательно)</h2>
          </div>
          <div className="flex flex-wrap items-center gap-2 self-start sm:self-auto">
            <button
              onClick={() => handleCopy('transcripts')}
              className="inline-flex items-center text-xs font-semibold text-indigo-600 dark:text-indigo-400 hover:text-indigo-700 dark:hover:text-indigo-300 bg-indigo-50 dark:bg-indigo-900/40 hover:bg-indigo-100 dark:hover:bg-indigo-900/60 px-3 py-1.5 rounded-lg transition-colors border border-indigo-200 dark:border-indigo-800"
              aria-label="Скопировать все расшифровки"
            >
              {copiedType === 'transcripts' ? (
                <>
                  <Check size={14} className="mr-1.5 text-emerald-500" />
                  <span>Все реплики скопированы!</span>
                </>
              ) : (
                <>
                  <Copy size={14} className="mr-1.5" />
                  <span>Скопировать реплики</span>
                </>
              )}
            </button>
            <ExportDropdown results={results} variant="secondary" label="Скачать (.txt / .md)" />
          </div>
        </div>
        <div className="space-y-8">
          {results.map((result, index) => (
            <div key={index} className="bg-white dark:bg-slate-900 rounded-xl border border-slate-100 dark:border-slate-800 overflow-hidden shadow-sm">
              <div className="bg-slate-50 dark:bg-slate-800/50 px-4 py-2.5 border-b border-slate-100 dark:border-slate-800 flex justify-between items-center">
                <div className="flex items-center space-x-2 truncate">
                  <FileAudio size={14} className="text-indigo-500 shrink-0" />
                  <span className="text-xs font-bold text-slate-600 dark:text-slate-300 uppercase tracking-wider truncate">{result.fileName}</span>
                  <span className="text-[10px] text-slate-400">({result.segments.length} реплик)</span>
                </div>
                <div className="flex items-center gap-1.5 shrink-0 ml-2">
                  <button
                    onClick={() => handleCopySingle(result, index)}
                    className="text-xs font-medium text-slate-600 dark:text-slate-300 hover:text-indigo-600 dark:hover:text-indigo-400 flex items-center bg-white dark:bg-slate-800 hover:bg-slate-100 dark:hover:bg-slate-750 border border-slate-200 dark:border-slate-700 px-2.5 py-1 rounded-md shadow-2xs transition-colors"
                    aria-label={`Скопировать текст ${result.fileName}`}
                  >
                    {copiedFileIndex === index ? (
                      <>
                        <Check size={12} className="mr-1 text-emerald-500" />
                        <span className="text-emerald-600 dark:text-emerald-400 font-semibold">Скопировано</span>
                      </>
                    ) : (
                      <>
                        <Copy size={12} className="mr-1 text-slate-400" />
                        <span>Скопировать</span>
                      </>
                    )}
                  </button>
                  <button
                    onClick={() => exportResults([result], 'txt', true)}
                    className="text-xs font-medium text-slate-600 dark:text-slate-300 hover:text-indigo-600 dark:hover:text-indigo-400 flex items-center bg-white dark:bg-slate-800 hover:bg-slate-100 dark:hover:bg-slate-750 border border-slate-200 dark:border-slate-700 px-2 py-1 rounded-md shadow-2xs transition-colors"
                    title={`Скачать расшифровку ${result.fileName} (.txt)`}
                    aria-label={`Скачать расшифровку ${result.fileName} (.txt)`}
                  >
                    <Download size={12} className="text-slate-400" />
                  </button>
                </div>
              </div>
              <div className="p-6 space-y-4">
                {result.segments.map((segment, i) => (
                  <div key={i} className="text-sm flex flex-col sm:flex-row sm:items-start gap-1 sm:gap-4 border-b border-slate-50 dark:border-slate-800/50 pb-3 last:border-0">
                    <div className="flex items-center shrink-0">
                      <span className="text-[10px] font-mono text-slate-400 bg-slate-100 dark:bg-slate-800 px-1.5 py-0.5 rounded mr-2">
                        {segment.timestamp}
                      </span>
                      <span className="font-bold text-indigo-600 dark:text-indigo-400 min-w-[100px]">
                        {segment.speaker}:
                      </span>
                    </div>
                    <span className="text-slate-600 dark:text-slate-300 leading-relaxed">
                      {segment.content}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
};

export default CombinedReport;
