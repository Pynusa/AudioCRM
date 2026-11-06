/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
*/

import React, { useState, useEffect, useRef } from 'react';
import { Mic, Upload, Sparkles, AlertTriangle, Moon, Sun, FileAudio, Copy, Check, FileText } from 'lucide-react';
import AudioRecorder from './components/AudioRecorder';
import FileUploader from './components/FileUploader';
import CombinedReport from './components/CombinedReport';
import ExportDropdown from './components/ExportDropdown';
import Button from './components/Button';
import { transcribeAudio } from './services/geminiService';
import { saveFiles, loadFiles, clearFiles } from './services/storageService';
import { copyToClipboard, formatFullTranscript } from './services/clipboardService';
import { AppStatus, AudioData, TranscriptionResponse } from './types';

function App() {
  const [mode, setMode] = useState<'record' | 'upload'>('record');
  const [status, setStatus] = useState<AppStatus>('idle');
  const [processingStep, setProcessingStep] = useState<'preparing' | 'transcribing' | 'idle'>('idle');
  const [audioFiles, setAudioFiles] = useState<AudioData[]>([]);
  const [results, setResults] = useState<(TranscriptionResponse & { fileName: string })[]>([]);
  const [processingIndex, setProcessingIndex] = useState<number>(-1);
  const [elapsedTime, setElapsedTime] = useState<number>(0);
  const [error, setError] = useState<string | null>(null);
  const [copiedTop, setCopiedTop] = useState(false);
  
  const isCanceledRef = useRef(false);
  
  // Initialize dark mode based on system preference
  const [isDarkMode, setIsDarkMode] = useState(() => {
    if (typeof window !== 'undefined') {
      return window.matchMedia('(prefers-color-scheme: dark)').matches;
    }
    return false;
  });

  // Toggle Dark Mode
  useEffect(() => {
    if (isDarkMode) {
      document.documentElement.classList.add('dark');
    } else {
      document.documentElement.classList.remove('dark');
    }
  }, [isDarkMode]);

  // Check for shared file from PWA Web Share Target
  useEffect(() => {
    const loadSharedFile = async () => {
      try {
        const db = await new Promise<IDBDatabase>((resolve, reject) => {
          const request = indexedDB.open('SharedFilesDB', 1);
          request.onupgradeneeded = (e) => {
            (e.target as IDBOpenDBRequest).result.createObjectStore('files');
          };
          request.onsuccess = (e) => resolve((e.target as IDBOpenDBRequest).result);
          request.onerror = () => reject(request.error);
        });

        if (!db.objectStoreNames.contains('files')) return;

        const tx = db.transaction('files', 'readwrite');
        const store = tx.objectStore('files');
        const getReq = store.get('shared-audio');

        getReq.onsuccess = () => {
          const file = getReq.result as File;
          if (file) {
            setMode('upload');
            const reader = new FileReader();
            reader.onloadend = () => {
              const base64data = reader.result as string;
              const base64 = base64data.split(',')[1];
              handleFilesSelected([{
                blob: file,
                base64,
                mimeType: file.type || 'audio/mp3',
                name: file.name
              }]);
            };
            reader.readAsDataURL(file);
            
            // Clear the file so it doesn't load again on refresh
            store.delete('shared-audio');
            
            // Remove query param if present
            if (window.location.search.includes('shared=true')) {
              window.history.replaceState({}, document.title, window.location.pathname);
            }
          }
        };
      } catch (err) {
        console.error("Error loading shared file:", err);
      }
    };

    loadSharedFile();
  }, []);

  // Timer for processing
  useEffect(() => {
    let interval: any;
    if (status === 'processing') {
      setElapsedTime(0);
      interval = setInterval(() => {
        setElapsedTime(prev => prev + 1);
      }, 1000);
    } else {
      clearInterval(interval);
    }
    return () => clearInterval(interval);
  }, [status]);

  // Load saved files on mount
  useEffect(() => {
    const restoreFiles = async () => {
      try {
        const savedFiles = await loadFiles();
        if (savedFiles.length > 0) {
          setAudioFiles(savedFiles);
          setMode('upload');
        }
      } catch (err) {
        console.error("Error restoring files:", err);
      }
    };
    restoreFiles();
  }, []);

  // Save files to storage whenever they change
  useEffect(() => {
    if (audioFiles.length > 0) {
      saveFiles(audioFiles).catch(err => console.error("Error saving files:", err));
    } else {
      clearFiles().catch(err => console.error("Error clearing files:", err));
    }
  }, [audioFiles]);

  const toggleDarkMode = () => setIsDarkMode(!isDarkMode);

  const handleFilesSelected = (files: AudioData[]) => {
    setAudioFiles(files);
    setError(null);
    setResults([]); 
  };

  const fileToBase64 = (blob: Blob): Promise<string> => {
    return new Promise((resolve, reject) => {
      const start = Date.now();
      const reader = new FileReader();
      reader.onload = () => {
        const result = reader.result as string;
        const base64 = result.split(',')[1];
        console.log(`File converted to base64 in ${Date.now() - start}ms, size: ${(base64.length / 1024 / 1024).toFixed(2)} MB`);
        resolve(base64);
      };
      reader.onerror = reject;
      reader.readAsDataURL(blob);
    });
  };

  const handleTranscribe = async () => {
    if (audioFiles.length === 0) return;

    setStatus('processing');
    setError(null);
    setResults([]); // Clear previous results
    isCanceledRef.current = false;

    try {
      for (let i = 0; i < audioFiles.length; i++) {
        // Check if user canceled
        if (isCanceledRef.current) break;
        
        setProcessingIndex(i);
        const file = audioFiles[i];
        
        setProcessingStep('preparing');
        // Lazy load Base64 if not present
        const base64 = file.base64 || await fileToBase64(file.blob);
        
        if (isCanceledRef.current) break;
        
        setProcessingStep('transcribing');
        try {
          console.log(`[${new Date().toLocaleTimeString()}] Starting transcription for file ${i + 1}: ${file.name}`);
          const data = await transcribeAudio(base64, file.mimeType, file.name);
          console.log(`[${new Date().toLocaleTimeString()}] Successfully transcribed ${file.name}`);
          const newResult = { 
            ...(data as TranscriptionResponse), 
            fileName: file.name || 'Аудио файл' 
          };
          
          setResults(prev => [...prev, newResult]);
          
          // Small delay to allow UI to update and browser to breathe
          await new Promise(r => setTimeout(r, 500));
        } catch (fileErr: any) {
          console.error(`Error processing file ${file.name}:`, fileErr);
          // If one file fails, we might want to continue with others or stop
          // For now, let's stop and show the error
          throw fileErr;
        }
      }
      
      if (!isCanceledRef.current) {
        setStatus('success');
        setProcessingIndex(-1);
        setProcessingStep('idle');
        // Clear files after successful transcription to free up storage
        setAudioFiles([]);
      }
    } catch (err: any) {
      setProcessingIndex(-1);
      setProcessingStep('idle');
      console.error("Transcription error:", err);
      
      let errorMessage = err.message || "Произошла ошибка при расшифровке. Пожалуйста, попробуйте еще раз.";
      
      const lower = errorMessage.toLowerCase();
      if (lower.includes('api key not valid') || lower.includes('api key is missing') || (lower.includes('api-ключ') && lower.includes('не настроен'))) {
        errorMessage = "API-ключ Gemini недействителен или отсутствует. Убедитесь, что GEMINI_API_KEY правильно задан в секретах (Settings -> Secrets).";
      } else if (lower.includes('quota') || lower.includes('429') || lower.includes('resource_exhausted')) {
        errorMessage = "Превышена квота запросов API Gemini. Пожалуйста, подождите немного и попробуйте снова.";
      } else if (lower.includes('503') || lower.includes('unavailable') || lower.includes('high demand') || lower.includes('перегружен') || lower.includes('нагрузк') || lower.includes('спрос')) {
        errorMessage = "Серверы Gemini сейчас испытывают высокую нагрузку (пиковый спрос). Мы выполнили автоматические повторные попытки, но сервер всё ещё занят. Пожалуйста, подождите 1–2 минуты и нажмите кнопку снова — ваши файлы сохранены.";
      } else if (lower.includes('не ответила') || lower.includes('превышено время ожидания') || lower.includes('timeout') || lower.includes('deadline')) {
        errorMessage = "Сервер Gemini был перегружен и не успел обработать файл за отведенное время. Мы переключили систему на быструю модель. Нажмите «Повторить попытку» — файл сохранён.";
      }
      
      setError(errorMessage);
      setStatus('error');
    }
  };

  const handleReset = () => {
    setAudioFiles([]);
    setResults([]);
    setStatus('idle');
    setError(null);
  };

  const handleCopyFullTranscript = async () => {
    const text = formatFullTranscript(results);
    const ok = await copyToClipboard(text);
    if (ok) {
      setCopiedTop(true);
      setTimeout(() => setCopiedTop(false), 2500);
    }
  };

  return (
    <div className="min-h-screen bg-slate-50 dark:bg-slate-950 text-slate-900 dark:text-slate-100 pb-20 transition-colors duration-300">
      {/* Header */}
      <header className="bg-white dark:bg-slate-900 border-b border-slate-200 dark:border-slate-800 sticky top-0 z-10 transition-colors duration-300">
        <div className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
          <div className="flex items-center space-x-2">
            <div className="bg-indigo-600 p-2 rounded-lg text-white shadow-lg shadow-indigo-500/30">
              <Sparkles size={20} />
            </div>
            <h1 className="text-xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-indigo-600 to-violet-600 dark:from-indigo-400 dark:to-violet-400">
              EchoScript AI
            </h1>
          </div>
          <div className="flex items-center space-x-4">
            <div className="text-sm text-slate-500 dark:text-slate-400 font-medium hidden sm:block">
              Работает на базе Gemini Flash
            </div>
            <button
              onClick={toggleDarkMode}
              className="p-2 text-slate-500 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-800 rounded-lg transition-colors focus:outline-none focus:ring-2 focus:ring-indigo-500"
              aria-label="Переключить темную тему"
            >
              {isDarkMode ? <Sun size={20} /> : <Moon size={20} />}
            </button>
          </div>
        </div>
      </header>

      <main className="max-w-3xl mx-auto px-4 sm:px-6 py-10">
        
        {/* Intro */}
        <div className="text-center mb-10">
          <h2 className="text-3xl font-bold text-slate-900 dark:text-white mb-4">
            Превратите ваше аудио в точный текст
          </h2>
          <p className="text-lg text-slate-600 dark:text-slate-400 max-w-2xl mx-auto">
            Загрузите файл или запишите аудио, чтобы мгновенно получить расшифровку с разделением по спикерам, таймкодами и определением языка.
          </p>
        </div>

        {/* Status Error */}
        {status === 'error' && error && (
          <div className="mb-6 bg-amber-50 dark:bg-amber-950/40 border border-amber-200 dark:border-amber-800 rounded-xl p-4 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3 text-amber-900 dark:text-amber-200">
            <div className="flex items-start">
              <AlertTriangle className="mr-3 flex-shrink-0 mt-0.5 text-amber-600 dark:text-amber-400" size={20} />
              <p className="text-sm">{error}</p>
            </div>
            {audioFiles.length > 0 && (
              <button
                onClick={handleTranscribe}
                className="whitespace-nowrap px-4 py-2 bg-amber-600 hover:bg-amber-700 text-white text-xs font-semibold rounded-lg shadow-sm transition-colors self-end sm:self-center"
              >
                Повторить попытку
              </button>
            )}
          </div>
        )}

        {/* Input Selection Tabs */}
        {results.length === 0 && (
            <div className="bg-white dark:bg-slate-900 p-1 rounded-xl shadow-sm border border-slate-200 dark:border-slate-800 inline-flex mb-8 w-full sm:w-auto transition-colors duration-300">
            <button
                onClick={() => { setMode('record'); handleReset(); }}
                className={`flex-1 sm:flex-none flex items-center justify-center px-6 py-2.5 rounded-lg text-sm font-medium transition-all focus:outline-none focus:ring-2 focus:ring-offset-1 dark:focus:ring-offset-slate-900 focus:ring-indigo-500 ${
                mode === 'record' 
                    ? 'bg-indigo-600 text-white shadow-sm' 
                    : 'text-slate-600 dark:text-slate-400 hover:bg-slate-50 dark:hover:bg-slate-800'
                }`}
                disabled={status === 'processing'}
            >
                <Mic size={16} className="mr-2" />
                Записать аудио
            </button>
            <button
                onClick={() => { setMode('upload'); handleReset(); }}
                className={`flex-1 sm:flex-none flex items-center justify-center px-6 py-2.5 rounded-lg text-sm font-medium transition-all focus:outline-none focus:ring-2 focus:ring-offset-1 dark:focus:ring-offset-slate-900 focus:ring-indigo-500 ${
                mode === 'upload' 
                    ? 'bg-indigo-600 text-white shadow-sm' 
                    : 'text-slate-600 dark:text-slate-400 hover:bg-slate-50 dark:hover:bg-slate-800'
                }`}
                disabled={status === 'processing'}
            >
                <Upload size={16} className="mr-2" />
                Загрузить файлы
            </button>
            </div>
        )}

        {/* Main Content Area */}
        <div className="space-y-8">
          
          {/* Input Section */}
          {results.length === 0 && status !== 'processing' && (
            <div className="bg-white dark:bg-slate-900 rounded-2xl shadow-sm border border-slate-200 dark:border-slate-800 p-6 sm:p-8 transition-colors duration-300">
              {mode === 'record' ? (
                <AudioRecorder onAudioCaptured={(data) => handleFilesSelected(data ? [data] : [])} disabled={status === 'processing'} />
              ) : (
                <FileUploader onFilesSelected={handleFilesSelected} disabled={status === 'processing'} audioFiles={audioFiles} />
              )}

              {audioFiles.length > 0 && (
                <div className="mt-6 flex justify-end pt-6 border-t border-slate-100 dark:border-slate-800">
                  <Button 
                    onClick={handleTranscribe} 
                    isLoading={status === 'processing'}
                    className="w-full sm:w-auto"
                    icon={<Sparkles size={16} />}
                  >
                    Сгенерировать расшифровку ({audioFiles.length})
                  </Button>
                </div>
              )}
            </div>
          )}

          {/* Processing State */}
          {status === 'processing' && (
            <div className="bg-white dark:bg-slate-900 rounded-2xl shadow-sm border border-slate-200 dark:border-slate-800 p-8 sm:p-12 text-center transition-colors duration-300 animate-in fade-in duration-500">
              <div className="flex justify-center mb-6">
                 <div className="relative">
                    <div className="w-20 h-20 border-4 border-indigo-100 dark:border-indigo-900/30 border-t-indigo-600 dark:border-t-indigo-500 rounded-full animate-spin"></div>
                    <div className="absolute top-0 left-0 w-full h-full flex items-center justify-center">
                        <Sparkles size={24} className="text-indigo-600 dark:text-indigo-400 animate-pulse" />
                    </div>
                 </div>
              </div>
              <h3 className="text-xl font-semibold text-slate-900 dark:text-white mb-2">
                Анализ {audioFiles.length > 1 ? `файла ${processingIndex + 1} из ${audioFiles.length}` : 'аудио'}...
              </h3>
              <p className="text-slate-500 dark:text-slate-400 max-w-sm mx-auto mb-2">
                {audioFiles[processingIndex]?.name || 'Обработка данных'}
              </p>
              <p className="text-indigo-600 dark:text-indigo-400 text-sm font-medium mb-6">
                {processingStep === 'preparing' ? 'Подготовка данных...' : 'Расшифровка нейросетью...'}
              </p>
              
              <div className="max-w-xs mx-auto bg-slate-100 dark:bg-slate-800 rounded-full h-2 overflow-hidden mb-8">
                <div 
                  className="bg-indigo-600 h-full transition-all duration-500 ease-out"
                  style={{ width: `${((processingIndex + 1) / audioFiles.length) * 100}%` }}
                ></div>
              </div>

              <p className="text-xs text-slate-400 dark:text-slate-500 mb-2">
                Прошло времени: {Math.floor(elapsedTime / 60)}:{(elapsedTime % 60).toString().padStart(2, '0')}
              </p>
              <p className="text-xs text-slate-400 dark:text-slate-500 mb-8">
                Это может занять некоторое время в зависимости от размера файлов и скорости интернета.
              </p>

              <Button 
                variant="secondary" 
                onClick={() => {
                  isCanceledRef.current = true;
                  setStatus('idle');
                  setProcessingIndex(-1);
                }}
              >
                Отменить
              </Button>
            </div>
          )}

          {/* Results Section */}
          {results.length > 0 && status === 'success' && (
            <div className="space-y-6">
                <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-6">
                    <h2 className="text-2xl font-bold text-slate-900 dark:text-white">Результаты анализа</h2>
                    <div className="flex flex-wrap items-center gap-2.5 w-full sm:w-auto">
                        <Button
                          onClick={handleCopyFullTranscript}
                          variant="primary"
                          icon={copiedTop ? <Check size={16} className="text-emerald-300" /> : <Copy size={16} />}
                          className="flex-1 sm:flex-none shadow-sm"
                        >
                          {copiedTop ? 'Скопировано!' : 'Скопировать текст'}
                        </Button>
                        <ExportDropdown results={results} variant="secondary" label="Скачать" />
                        <Button onClick={handleReset} variant="secondary">Начать заново</Button>
                    </div>
                </div>

                <div className="pt-4">
                  <CombinedReport results={results} />
                </div>
            </div>
          )}
        </div>

        {/* Disclaimer */}
        <div className="mt-16 text-center text-xs text-slate-500 dark:text-slate-400 max-w-2xl mx-auto leading-relaxed border-t border-slate-200 dark:border-slate-800 pt-8 transition-colors duration-300">
            <p className="mb-2">
            Используя эту функцию, вы подтверждаете, что обладаете необходимыми правами на загружаемый контент. Не загружайте материалы, нарушающие права интеллектуальной собственности или конфиденциальность других лиц. Использование этого генеративного ИИ регулируется нашей <a href="https://policies.google.com/terms/generative-ai/use-policy" target="_blank" rel="noopener noreferrer" className="underline hover:text-slate-700 dark:hover:text-slate-300 transition-colors">Политикой запрещенного использования</a>.
            </p>
            <p>
            Обратите внимание, что загрузки из Google Workspace могут использоваться для разработки и улучшения продуктов и сервисов Google в соответствии с нашими <a href="https://ai.google.dev/gemini-api/terms" target="_blank" rel="noopener noreferrer" className="underline hover:text-slate-700 dark:hover:text-slate-300 transition-colors">условиями</a>.
            </p>
        </div>

      </main>
    </div>
  );
}

export default App;