/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import { AudioData } from '../types';

const DB_NAME = 'EchoScriptFilesDB';
const STORE_NAME = 'uploaded_files';
const DB_VERSION = 1;

export const openDB = (): Promise<IDBDatabase> => {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = (e) => {
      const db = (e.target as IDBOpenDBRequest).result;
      if (!db.objectStoreNames.contains(STORE_NAME)) {
        db.createObjectStore(STORE_NAME, { keyPath: 'id', autoIncrement: true });
      }
    };
    request.onsuccess = (e) => resolve((e.target as IDBOpenDBRequest).result);
    request.onerror = (e) => reject((e.target as IDBOpenDBRequest).error);
  });
};

export const saveFiles = async (files: AudioData[]): Promise<void> => {
  const db = await openDB();
  const tx = db.transaction(STORE_NAME, 'readwrite');
  const store = tx.objectStore(STORE_NAME);
  
  // Clear existing files first to keep it simple (we only support 5 at a time)
  await new Promise<void>((resolve, reject) => {
    const clearReq = store.clear();
    clearReq.onsuccess = () => resolve();
    clearReq.onerror = () => reject(clearReq.error);
  });

  for (const file of files) {
    // We store the Blob/File directly. IndexedDB supports Blobs.
    // We don't store the Base64 to save space and memory.
    const dataToSave = {
      blob: file.blob,
      mimeType: file.mimeType,
      name: file.name,
      timestamp: Date.now()
    };
    store.add(dataToSave);
  }

  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
};

export const loadFiles = async (): Promise<AudioData[]> => {
  const db = await openDB();
  const tx = db.transaction(STORE_NAME, 'readonly');
  const store = tx.objectStore(STORE_NAME);
  const request = store.getAll();

  return new Promise((resolve, reject) => {
    request.onsuccess = () => {
      const results = request.result;
      const audioFiles: AudioData[] = results.map(item => ({
        blob: item.blob,
        mimeType: item.mimeType,
        name: item.name,
        base64: '' // Base64 will be generated on demand
      }));
      resolve(audioFiles);
    };
    request.onerror = () => reject(request.error);
  });
};

export const clearFiles = async (): Promise<void> => {
  const db = await openDB();
  const tx = db.transaction(STORE_NAME, 'readwrite');
  const store = tx.objectStore(STORE_NAME);
  store.clear();
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
};
