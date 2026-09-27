// Сборка наброска в один HTML-файл: npm install && npm run build
// dist/fog-isles.html            — для публикации (без <html>/<head>, их добавляет хостинг)
// dist/fog-isles-standalone.html — открывается двойным кликом
import { build } from 'esbuild';
import fs from 'node:fs';

await build({ entryPoints: ['src/main.js'], bundle: true, minify: true, format: 'iife', target: 'es2020', outfile: 'dist/bundle.js', legalComments: 'none', logLevel: 'warning' });
const js = fs.readFileSync('dist/bundle.js', 'utf8').replace(/<\/script/gi, '<\\/script');
const shell = fs.readFileSync('src/shell.html', 'utf8');
const [head, body] = shell.split('<!--HEAD-END-->');
const script = `<script>/* three.js r170 — (c) three.js authors, MIT license */\n${js}</script>`;
const bodyOut = body.replace('<!--BUNDLE-->', () => script);
fs.mkdirSync('dist', { recursive: true });
fs.writeFileSync('dist/fog-isles.html', head + bodyOut);
fs.writeFileSync('dist/fog-isles-standalone.html', `<!doctype html>\n<html lang="ru">\n<head>\n<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n${head}</head>\n<body>${bodyOut}</body>\n</html>\n`);
console.log('bundle', (js.length / 1024).toFixed(0), 'KB; page', (fs.statSync('dist/fog-isles.html').size / 1024).toFixed(0), 'KB');
