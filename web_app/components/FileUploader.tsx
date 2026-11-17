/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
*/

import React, { useState, useRef } from 'react';
import { UploadCloud, FileAudio, X } from 'lucide-react';
import { AudioData } from '../types';

interface FileUploaderProps {
  onFilesSelected: (audioFiles: AudioData[]) => void;
  disabled?: boolean;
  audioFiles: AudioData[];
}

const FileUploader: React.FC<FileUploaderProps> = ({ onFilesSelected, disabled, audioFiles }) => {
  const [dragActive, setDragActive] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const processFiles = async (files: FileList | File[]) => {
    if (disabled || isProcessing) return;
    
    const newFiles = Array.from(files);
    const totalCount = audioFiles.length + newFiles.length;
    
    if (totalCount > 5) {
      alert("Вы можете загрузить не более 5 файлов одновременно.");
      return;
    }

    setIsProcessing(true);
    const processedFiles: AudioData[] = [];
    const MAX_FILE_SIZE = 25 * 1024 * 1024; // 25MB

    for (const file of newFiles) {
      const isAudioOrVideo =
        (file.type && (file.type.startsWith('audio/') || file.type.startsWith('video/'))) ||
        /\.(mp3|wav|m4a|aac|ogg|webm|mp4|wma|flac)$/i.test(file.name);

      if (!isAudioOrVideo) {
        alert(`Файл "${file.name}" не является аудио или видео.`);
        continue;
      }

      if (file.size > MAX_FILE_SIZE) {
        alert(`Файл "${file.name}" слишком большой (более 25 МБ). Пожалуйста, используйте файлы меньшего размера для стабильной работы.`);
        continue;
      }

      // Infer standard MIME type if browser leaves file.type empty (common for .m4a)
      let detectedMime = file.type;
      if (!detectedMime) {
        const ext = file.name.split('.').pop()?.toLowerCase();
        if (ext === 'm4a' || ext === 'mp4') detectedMime = 'audio/mp4';
        else if (ext === 'mp3') detectedMime = 'audio/mp3';
        else if (ext === 'wav') detectedMime = 'audio/wav';
        else if (ext === 'aac') detectedMime = 'audio/aac';
        else if (ext === 'webm') detectedMime = 'audio/webm';
        else detectedMime = 'audio/mp4';
      }

      processedFiles.push({
        blob: file,
        mimeType: detectedMime,
        name: file.name
      });
    }

    onFilesSelected([...audioFiles, ...processedFiles]);
    setIsProcessing(false);
    if (inputRef.current) inputRef.current.value = "";
  };

  const handleDrag = (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    if (e.type === "dragenter" || e.type === "dragover") {
      setDragActive(true);
    } else if (e.type === "dragleave") {
      setDragActive(false);
    }
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setDragActive(false);
    if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
      processFiles(e.dataTransfer.files);
    }
  };

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files.length > 0) {
      processFiles(e.target.files);
    }
  };

  const handleRemoveFile = (index: number) => {
    const updatedFiles = audioFiles.filter((_, i) => i !== index);
    onFilesSelected(updatedFiles);
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (disabled) return;
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      inputRef.current?.click();
    }
  };

  return (
    <div className="w-full space-y-4">
      <input
        ref={inputRef}
        type="file"
        className="hidden"
        accept="audio/*,video/*"
        onChange={handleChange}
        disabled={disabled || audioFiles.length >= 5}
        multiple
      />
      
      {audioFiles.length < 5 && (
        <div
          role="button"
          tabIndex={disabled ? -1 : 0}
          aria-label="Загрузить аудиофайлы"
          className={`flex flex-col items-center justify-center p-8 border-2 border-dashed rounded-2xl transition-all outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 dark:focus:ring-offset-slate-900 ${
            dragActive 
              ? "border-indigo-500 bg-indigo-50 dark:bg-indigo-900/20" 
              : "border-slate-300 dark:border-slate-700 bg-white dark:bg-slate-800 hover:border-indigo-400 dark:hover:border-indigo-500 hover:bg-slate-50 dark:hover:bg-slate-800/80"
          } ${disabled || isProcessing ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}`}
          onDragEnter={handleDrag}
          onDragLeave={handleDrag}
          onDragOver={handleDrag}
          onDrop={handleDrop}
          onClick={() => !disabled && !isProcessing && inputRef.current?.click()}
          onKeyDown={handleKeyDown}
        >
          <div className="p-3 bg-indigo-50 dark:bg-indigo-900/30 text-indigo-500 dark:text-indigo-400 rounded-full mb-3">
            <UploadCloud size={28} />
          </div>
          <p className="text-base font-medium text-slate-700 dark:text-slate-200 mb-1">
            {isProcessing ? "Обработка файлов..." : "Нажмите для загрузки или перетащите файлы"}
          </p>
          <p className="text-xs text-slate-500 dark:text-slate-400">
            MP3, WAV, M4A, WEBM (До 5 файлов, макс. 25МБ каждый)
          </p>
        </div>
      )}

      {audioFiles.length > 0 && (
        <div className="space-y-2">
          <p className="text-sm font-semibold text-slate-600 dark:text-slate-400 px-1">
            Загруженные файлы ({audioFiles.length}/5):
          </p>
          {audioFiles.map((file, index) => (
            <div key={index} className="bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-xl p-4 flex items-center justify-between shadow-sm transition-colors duration-300">
              <div className="flex items-center space-x-3 overflow-hidden">
                <div className="p-2 bg-indigo-100 dark:bg-indigo-900/40 text-indigo-600 dark:text-indigo-400 rounded-lg flex-shrink-0">
                  <FileAudio size={20} />
                </div>
                <div className="overflow-hidden">
                  <p className="font-medium text-slate-800 dark:text-slate-200 truncate text-sm">
                    {file.name || `Файл ${index + 1}`}
                  </p>
                  <p className="text-[10px] text-slate-500 dark:text-slate-400">Готово к расшифровке</p>
                </div>
              </div>
              <button 
                onClick={() => handleRemoveFile(index)}
                className="p-1.5 text-slate-400 dark:text-slate-500 hover:text-red-500 dark:hover:text-red-400 hover:bg-red-50 dark:hover:bg-red-900/20 rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-red-500"
                disabled={disabled}
                aria-label="Удалить файл"
              >
                <X size={16} />
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

export default FileUploader;