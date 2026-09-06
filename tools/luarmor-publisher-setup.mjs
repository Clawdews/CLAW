// One-use local form for saving the API key with Windows DPAPI. No cloud transmission.
import { createServer } from 'node:http';
import { randomBytes } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const token = randomBytes(32).toString('hex');
let origin;
const server = createServer(async (req, res) => {
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Content-Security-Policy', "default-src 'none'; form-action 'self'; frame-ancestors 'none'");
  if (req.headers.host !== new URL(origin).host) { res.writeHead(403); res.end('Forbidden'); return; }
  if (req.method === 'GET' && req.url === '/') {
    res.end(`<!doctype html><title>CLAW local upload setup</title><h1>CLAW local upload setup</h1><p>Paste the existing Luarmor API key. It stays on this PC and is protected by your Windows login.</p><form method="post"><input type="hidden" name="csrf" value="${token}"><label>Luarmor API key <input type="password" name="key" autocomplete="off" required maxlength="160"></label><button>Protect and save locally</button></form>`); return;
  }
  if (req.method !== 'POST' || req.url !== '/' || req.headers.origin !== origin) { res.writeHead(403); res.end('Forbidden'); return; }
  let body = '';
  for await (const chunk of req) { body += chunk; if (body.length > 2048) { res.writeHead(413); res.end('Too large'); return; } }
  const fields = new URLSearchParams(body); body = '';
  if (fields.get('csrf') !== token || !/^[A-Za-z0-9_-]{32,160}$/.test(fields.get('key') || '')) { res.writeHead(400); res.end('Invalid key or form.'); return; }
  const result = spawnSync(process.execPath, [resolve(root, 'tools/luarmor-publisher.mjs'), '--save-key'], { cwd: root,
    input: fields.get('key'), encoding: 'utf8', windowsHide: true, timeout: 20000 }); fields.delete('key');
  if (result.status !== 0) { res.writeHead(500); res.end('Could not save the protected key. No credential was logged.'); return; }
  res.end('<!doctype html><title>Saved</title><h1>Saved with Windows protection</h1><p>The API key is stored locally. Close this page.</p>');
  console.log('Protected API key saved. Local setup server closing.'); server.close();
});
server.listen(0, '127.0.0.1', () => { origin = `http://127.0.0.1:${server.address().port}`; console.log(origin); });
setTimeout(() => server.close(), 10 * 60 * 1000).unref();
