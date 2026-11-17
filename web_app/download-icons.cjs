const https = require('https');
const fs = require('fs');

function download(url, dest) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': 'Mozilla/5.0' } }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        return download(res.headers.location, dest).then(resolve).catch(reject);
      }
      const file = fs.createWriteStream(dest);
      res.pipe(file);
      file.on('finish', () => file.close(resolve));
    }).on('error', reject);
  });
}

Promise.all([
  download('https://placehold.co/192x192/4f46e5/ffffff/png?text=Mic', 'public/icon-192.png'),
  download('https://placehold.co/512x512/4f46e5/ffffff/png?text=Mic', 'public/icon-512.png')
]).then(() => console.log('Icons downloaded successfully')).catch(console.error);
