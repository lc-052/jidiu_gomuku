'use strict';
const fs = require('node:fs');
const path = require('node:path');
const express = require('express');

function mountWeb(app, root) {
  root = path.resolve(root);
  if (!fs.existsSync(path.join(root, 'index.html'))) return;
  app.use((req, res, next) => {
    if (!['GET', 'HEAD'].includes(req.method)) return next();
    let pathname;
    try { pathname = decodeURIComponent(req.path); } catch { return next(); }
    const file = path.resolve(root, '.' + pathname);
    if (!file.startsWith(root + path.sep) || !/\.(js|wasm|json|html|svg|ttf|otf|txt)$/.test(file)) return next();
    res.vary('Accept-Encoding');
    const encoding = req.acceptsEncodings('br', 'gzip', 'identity');
    if (!['br', 'gzip'].includes(encoding)) return next();
    const compressed = file + (encoding === 'br' ? '.br' : '.gz');
    if (!fs.existsSync(compressed)) return next();
    res.type(path.extname(file));
    res.set('Content-Encoding', encoding);
    // Revalidate cached bytes so updates are visible without redownloading unchanged files.
    res.set('Cache-Control', 'public, max-age=0, must-revalidate');
    res.sendFile(compressed);
  });
  app.use(express.static(root, {setHeaders(res) {
    res.vary('Accept-Encoding');
    res.setHeader('Cache-Control', 'public, max-age=0, must-revalidate');
  }}));
  app.get('*', (req, res, next) => {
    if (req.path.startsWith('/socket.io') || path.extname(req.path)) return next();
    res.set('Cache-Control', 'no-cache');
    res.sendFile(path.join(root, 'index.html'));
  });
}
module.exports = {mountWeb};
