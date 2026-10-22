'use strict';
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');

// Precompress once during packaging/build, rather than on every visitor request.
function prepareWeb(root) {
  let original = 0, gzip = 0;
  function walk(directory) {
    for (const item of fs.readdirSync(directory, {withFileTypes: true})) {
      const file = path.join(directory, item.name);
      if (item.isDirectory()) walk(file);
      else if (/\.(js|wasm|json|html|svg|ttf|otf|txt)$/.test(file)) {
        const data = fs.readFileSync(file);
        const gz = zlib.gzipSync(data, {level: 9});
        const br = zlib.brotliCompressSync(data, {params: {
          [zlib.constants.BROTLI_PARAM_QUALITY]: 6,
        }});
        fs.writeFileSync(file + '.gz', gz);
        fs.writeFileSync(file + '.br', br);
        original += data.length; gzip += Math.min(data.length, gz.length);
      }
    }
  }
  walk(root);
  return {original, gzip};
}
if (require.main === module) {
  console.log(JSON.stringify(prepareWeb(path.resolve(process.argv[2] || path.join(__dirname, 'web')))));
}
module.exports = {prepareWeb};
