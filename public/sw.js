const CACHE_NAME = 'echoscript-v2';
const ASSETS = [
  '/',
  '/index.html',
  '/manifest.json?v=2',
  '/icon-192.png',
  '/icon-512.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(ASSETS))
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key))
      );
    })
  );
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  
  if (event.request.method === 'POST' && url.pathname === '/_share-target') {
    event.respondWith((async () => {
      try {
        const formData = await event.request.formData();
        const file = formData.get('audio');
        
        if (file) {
          await new Promise((resolve, reject) => {
            const request = indexedDB.open('SharedFilesDB', 1);
            request.onupgradeneeded = (e) => {
              e.target.result.createObjectStore('files');
            };
            request.onsuccess = (e) => {
              const db = e.target.result;
              const tx = db.transaction('files', 'readwrite');
              const store = tx.objectStore('files');
              store.put(file, 'shared-audio');
              tx.oncomplete = () => resolve();
              tx.onerror = (err) => reject(err);
            };
            request.onerror = (err) => reject(err);
          });
        }
        
        // Redirect to the home page so the React app can load and read the DB
        return Response.redirect('/?shared=true', 303);
      } catch (err) {
        console.error('Share target error:', err);
        return Response.redirect('/?error=share_failed', 303);
      }
    })());
    return;
  }

  // Basic network-first caching strategy for other requests
  if (event.request.method === 'GET') {
    event.respondWith(
      fetch(event.request).catch(() => caches.match(event.request))
    );
  }
});
