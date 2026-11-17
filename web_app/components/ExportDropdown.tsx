/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useRef, useEffect } from 'react';
import { Download, FileText, ChevronDown, MessageSquare, Check } from 'lucide-react';
import { TranscriptionResponse } from '../types';
import { exportResults } from '../services/exportService';

interface ExportDropdownProps {
  results: (TranscriptionResponse & { fileName: string })[];
  variant?: 'primary' | 'secondary' | 'banner';
  className?: string;
  align?: 'left' | 'right';
  label?: string;
}

const ExportDropdown: React.FC<ExportDropdownProps> = ({
  results,
  variant = 'secondary',
  className = '',
  align = 'right',
  label = 'Скачать',
}) => {
  const [isOpen, setIsOpen] = useState(false);
  const [downloadedFormat, setDownloadedFormat] = useState<string | null>(null);
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Close when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };

    if (isOpen) {
      document.addEventListener('mousedown', handleClickOutside);
    }
    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, [isOpen]);

  const handleExport = (format: 'txt' | 'md', onlyDialogue: boolean = false) => {
    exportResults(results, format, onlyDialogue);
    const key = `${format}-${onlyDialogue ? 'dialogue' : 'full'}`;
    setDownloadedFormat(key);
    setTimeout(() => {
      setDownloadedFormat(null);
      setIsOpen(false);
    }, 1500);
  };

  const getButtonStyles = () => {
    switch (variant) {
      case 'banner':
        return 'bg-white/10 hover:bg-white/20 text-white border border-white/25 focus:ring-white/80';
      case 'primary':
        return 'bg-indigo-600 hover:bg-indigo-700 text-white shadow-sm focus:ring-indigo-500';
      case 'secondary':
      default:
        return 'bg-white dark:bg-slate-800 hover:bg-slate-50 dark:hover:bg-slate-700 text-slate-700 dark:text-slate-200 border border-slate-200 dark:border-slate-700 shadow-sm focus:ring-indigo-500';
    }
  };

  return (
    <div className={`relative inline-block text-left ${className}`} ref={dropdownRef}>
      <button
        type="button"
        onClick={() => setIsOpen(!isOpen)}
        className={`inline-flex items-center justify-center px-3.5 py-2 text-sm font-semibold rounded-xl transition-all outline-none focus:ring-2 focus:ring-offset-1 dark:focus:ring-offset-slate-900 active:scale-95 ${getButtonStyles()}`}
        aria-expanded={isOpen}
        aria-haspopup="true"
      >
        <Download size={16} className="mr-2 shrink-0" />
        <span>{label}</span>
        <ChevronDown size={14} className={`ml-1.5 transition-transform duration-200 opacity-70 ${isOpen ? 'rotate-180' : ''}`} />
      </button>

      {isOpen && (
        <div
          className={`absolute z-30 mt-2 w-64 rounded-2xl bg-white dark:bg-slate-800 shadow-xl ring-1 ring-black/5 dark:ring-white/10 border border-slate-100 dark:border-slate-700 p-1.5 divide-y divide-slate-100 dark:divide-slate-700/60 animate-in fade-in zoom-in-95 duration-150 ${
            align === 'right' ? 'right-0' : 'left-0'
          }`}
          role="menu"
        >
          <div className="py-1">
            <div className="px-3 py-1.5 text-[11px] font-semibold text-slate-400 dark:text-slate-500 uppercase tracking-wider">
              Полный отчёт и CRM
            </div>
            <button
              onClick={() => handleExport('md', false)}
              className="w-full text-left flex items-start px-3 py-2 text-sm text-slate-700 dark:text-slate-200 hover:bg-indigo-50 dark:hover:bg-indigo-950/40 rounded-xl transition-colors group"
              role="menuitem"
            >
              <FileText size={16} className="mr-2.5 mt-0.5 text-indigo-600 dark:text-indigo-400 shrink-0" />
              <div className="flex-1">
                <div className="font-medium flex items-center justify-between">
                  <span>Markdown (.md)</span>
                  {downloadedFormat === 'md-full' && <Check size={14} className="text-emerald-500" />}
                </div>
                <p className="text-[11px] text-slate-400 dark:text-slate-400">С форматированием и разметкой</p>
              </div>
            </button>

            <button
              onClick={() => handleExport('txt', false)}
              className="w-full text-left flex items-start px-3 py-2 text-sm text-slate-700 dark:text-slate-200 hover:bg-indigo-50 dark:hover:bg-indigo-950/40 rounded-xl transition-colors group"
              role="menuitem"
            >
              <FileText size={16} className="mr-2.5 mt-0.5 text-slate-500 dark:text-slate-400 shrink-0" />
              <div className="flex-1">
                <div className="font-medium flex items-center justify-between">
                  <span>Текстовый файл (.txt)</span>
                  {downloadedFormat === 'txt-full' && <Check size={14} className="text-emerald-500" />}
                </div>
                <p className="text-[11px] text-slate-400 dark:text-slate-400">Универсальный текстовый формат</p>
              </div>
            </button>
          </div>

          <div className="py-1">
            <div className="px-3 py-1.5 text-[11px] font-semibold text-slate-400 dark:text-slate-500 uppercase tracking-wider">
              Только диалоги
            </div>
            <button
              onClick={() => handleExport('txt', true)}
              className="w-full text-left flex items-start px-3 py-2 text-sm text-slate-700 dark:text-slate-200 hover:bg-indigo-50 dark:hover:bg-indigo-950/40 rounded-xl transition-colors group"
              role="menuitem"
            >
              <MessageSquare size={16} className="mr-2.5 mt-0.5 text-emerald-600 dark:text-emerald-400 shrink-0" />
              <div className="flex-1">
                <div className="font-medium flex items-center justify-between">
                  <span>Реплики (.txt)</span>
                  {downloadedFormat === 'txt-dialogue' && <Check size={14} className="text-emerald-500" />}
                </div>
                <p className="text-[11px] text-slate-400 dark:text-slate-400">Чистый текст без CRM-блоков</p>
              </div>
            </button>

            <button
              onClick={() => handleExport('md', true)}
              className="w-full text-left flex items-start px-3 py-2 text-sm text-slate-700 dark:text-slate-200 hover:bg-indigo-50 dark:hover:bg-indigo-950/40 rounded-xl transition-colors group"
              role="menuitem"
            >
              <MessageSquare size={16} className="mr-2.5 mt-0.5 text-indigo-500 dark:text-indigo-400 shrink-0" />
              <div className="flex-1">
                <div className="font-medium flex items-center justify-between">
                  <span>Реплики (.md)</span>
                  {downloadedFormat === 'md-dialogue' && <Check size={14} className="text-emerald-500" />}
                </div>
                <p className="text-[11px] text-slate-400 dark:text-slate-400">Диалоги спикеров в Markdown</p>
              </div>
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

export default ExportDropdown;
