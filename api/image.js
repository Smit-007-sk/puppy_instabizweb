const fs = require('fs');
const path = require('path');

module.exports = (req, res) => {
  try {
    let targetUrl = req.query.url;
    if (!targetUrl) {
      return res.status(400).send('Missing url parameter');
    }

    targetUrl = decodeURIComponent(targetUrl).split('?')[0];
    const cleanRel = targetUrl.replace(/^\/+/, '').replace(/\//g, path.sep);

    const candidates = [
      path.join(process.cwd(), cleanRel),
      path.join(__dirname, '..', cleanRel)
    ];

    let foundPath = candidates.find(p => {
      try {
        return fs.existsSync(p) && fs.statSync(p).isFile();
      } catch (e) {
        return false;
      }
    });

    if (!foundPath && !path.extname(cleanRel)) {
      const exts = ['.jpg', '.jpeg', '.png', '.webp', '.svg'];
      for (const c of candidates) {
        for (const ext of exts) {
          try {
            if (fs.existsSync(c + ext) && fs.statSync(c + ext).isFile()) {
              foundPath = c + ext;
              break;
            }
          } catch (e) {}
        }
        if (foundPath) break;
      }
    }

    if (!foundPath) {
      return res.status(404).send('Image not found: ' + cleanRel);
    }

    const ext = path.extname(foundPath).toLowerCase();
    const mimeTypes = {
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.png': 'image/png',
      '.webp': 'image/webp',
      '.svg': 'image/svg+xml',
      '.gif': 'image/gif',
      '.avif': 'image/avif',
      '.mp4': 'video/mp4'
    };

    res.setHeader('Content-Type', mimeTypes[ext] || 'application/octet-stream');
    res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
    const stream = fs.createReadStream(foundPath);
    return stream.pipe(res);
  } catch (err) {
    return res.status(500).send('Internal Server Error: ' + err.message);
  }
};
