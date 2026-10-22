'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const express = require('express');
const {prepareWeb} = require('./prepare_web');
const {mountWeb} = require('./web_assets');

test('compressed assets preserve bytes, MIME types, cache validation and encoding negotiation', async () => {
  const parent = path.resolve(__dirname, '../build');
  fs.mkdirSync(parent, {recursive: true});
  const root = fs.mkdtempSync(path.join(parent, 'web-assets-test-'));
  fs.mkdirSync(path.join(root, 'canvaskit'));
  const js = 'window.example = 1;\n'.repeat(1000);
  const wasm = Buffer.from([0,97,115,109, ...Array(5000).fill(0)]);
  fs.writeFileSync(path.join(root, 'index.html'), '<html>fixture</html>');
  fs.writeFileSync(path.join(root, 'main.dart.js'), js);
  fs.writeFileSync(path.join(root, 'canvaskit/canvaskit.wasm'), wasm);
  prepareWeb(root);
  const app = express();
  mountWeb(app, root);
  const server = http.createServer(app);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const origin = 'http://127.0.0.1:' + server.address().port;
  try {
    for (const encoding of ['gzip', 'br', 'identity']) {
      const response = await fetch(origin + '/main.dart.js', {headers: {'Accept-Encoding': encoding}});
      assert.equal(response.status, 200);
      assert.match(response.headers.get('content-type'), /javascript/);
      assert.match(response.headers.get('vary'), /Accept-Encoding/);
      assert.equal(response.headers.get('content-encoding'), encoding === 'identity' ? null : encoding);
      assert.equal(await response.text(), js);
      // Raw HTTP avoids fetch adding Cache-Control: no-cache to conditional requests.
      const cachedStatus = await new Promise((resolve, reject) => {
        http.get(origin + '/main.dart.js', {headers: {
          'Accept-Encoding': encoding, 'If-None-Match': response.headers.get('etag'),
        }}, reply => {reply.resume(); reply.on('end', () => resolve(reply.statusCode));}).on('error', reject);
      });
      assert.equal(cachedStatus, 304);
    }
    const wasmResponse = await fetch(origin + '/canvaskit/canvaskit.wasm', {headers: {'Accept-Encoding': 'gzip'}});
    assert.equal(wasmResponse.headers.get('content-type'), 'application/wasm');
    assert.deepEqual(Buffer.from(await wasmResponse.arrayBuffer()), wasm);
    const disabled = await fetch(origin + '/main.dart.js', {headers: {'Accept-Encoding': 'gzip;q=0, br;q=0, identity;q=1'}});
    assert.equal(disabled.headers.get('content-encoding'), null);
    await disabled.arrayBuffer();
    assert.equal((await fetch(origin + '/missing.js')).status, 404);
    assert.equal((await fetch(origin + '/%2e%2e%2fpackage.json')).status, 404);
    assert.match(await (await fetch(origin + '/play')).text(), /fixture/);
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});
