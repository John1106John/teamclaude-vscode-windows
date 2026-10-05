/*
  warm-teamclaude.mjs - one manual keep-warm pass.

  The rolling 5h session window only starts once an account sends a real
  message, so a rotation onto a cold account gets a window that starts right
  when its headroom is needed. TeamClaude's own keep-warm scheduler
  (`warmupSeconds`) does this on a timer; this script is the same pass, run
  by hand - useful right after starting the proxy, or to see which accounts
  are cold without waiting for the next interval.

  On Windows the scheduler itself needed a fix to spawn the `claude.cmd` shim
  through a shell (KarpelesLab/teamclaude#488); it ships from teamclaude
  1.1.23, so on an older build the timer silently warms nothing and this is
  the only way to do it.

  It mirrors src/warmer.js: the same eligibility tests, the same pinned base
  URL, the same argv, the same one-at-a-time pacing. It spends a little quota
  per account warmed (a few tokens, a slice of the 5h and weekly buckets)  - 
  that is inherent, since only real usage starts the timer.

  Needs: the proxy running, and `claude` on PATH.
*/
import { readFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { homedir } from 'node:os';
import { join } from 'node:path';

const MODEL = 'haiku';        // warmer.js: cheapest model
const PROMPT = 'hi';          // warmer.js
const TIMEOUT_MS = 120_000;   // warmer.js

// Mirrors encodePinComponent() in src/claude-env.js. Copied rather than
// imported so this script does not have to resolve a global install.
const encodePinComponent = (s) =>
  encodeURIComponent(s).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);

const configPath = process.env.TEAMCLAUDE_CONFIG || join(homedir(), '.config', 'teamclaude.json');

let config;
try {
  config = JSON.parse(await readFile(configPath, 'utf-8'));
} catch (err) {
  console.error(`Cannot read ${configPath}: ${err.message}`);
  process.exit(1);
}
const port = config.proxy?.port || 3456;
const proxyKey = config.proxy?.apiKey || '';

let status;
try {
  const res = await fetch(`http://127.0.0.1:${port}/teamclaude/status`, {
    headers: proxyKey ? { 'x-api-key': proxyKey } : {},
  });
  if (!res.ok) throw new Error(`status endpoint answered ${res.status}`);
  status = await res.json();
} catch (err) {
  console.error(`No proxy answering on 127.0.0.1:${port} (${err.message}).`);
  console.error('Start it with launch-teamclaude-vscode.bat, or `teamclaude server`.');
  process.exit(1);
}

// warmer.js _isWarmCandidate / _isWarmTarget, against the status payload.
const now = Date.now();
const skipReason = (a) => {
  if (a.type !== 'oauth') return 'not an OAuth account';
  if (a.provider && a.provider !== 'anthropic') return `provider ${a.provider}`; // the 5h window is Anthropic's
  if (a.upstream) return 'third-party backend';
  if (a.disabled) return 'disabled';
  if (a.status === 'error' || a.status === 'exhausted' || a.status === 'throttled') return a.status;
  const reset = a.quota?.unified5hReset;
  if (reset && now < reset) {
    return `5h window already running (resets ${new Date(reset).toLocaleTimeString()})`;
  }
  return null;
};

const accounts = status.accounts || [];
const targets = [];
console.log(`${accounts.length} account(s) in the pool:\n`);
for (const a of accounts) {
  const reason = skipReason(a);
  if (reason) console.log(`  skip  ${a.name}  (${reason})`);
  else targets.push(a);
}
for (const a of targets) console.log(`  WARM  ${a.name}`);

if (targets.length === 0) {
  console.log('\nNothing to warm: every eligible account already has a live 5h window.');
  process.exit(0);
}

// The pin travels as a path prefix, so the identity must match what the proxy
// resolves. accountUuid/orgUuid live in the config, not in the status payload.
const identityOf = (name) => {
  const c = (config.accounts || []).find((x) => x.name === name);
  if (!c) return null;
  return c.accountUuid && c.orgUuid ? `${c.accountUuid}/${c.orgUuid}` : c.accountUuid || c.name;
};

const warm = (name) =>
  new Promise((resolve) => {
    const identity = identityOf(name);
    if (!identity) return resolve({ name, code: 'no identity in config' });
    const child = spawn('claude', ['-p', '--bare', '--model', MODEL, '--output-format', 'text', PROMPT], {
      env: {
        ...process.env,
        ANTHROPIC_BASE_URL: `http://127.0.0.1:${port}/tc-acct/${encodePinComponent(identity)}`,
        ANTHROPIC_API_KEY: proxyKey || 'tc-warm',
      },
      stdio: 'ignore',
      // The `claude` on PATH is npm's .cmd shim; a shell-less spawn only ever
      // tries .exe and fails with ENOENT. This is the missing guard in #488.
      shell: process.platform === 'win32',
    });
    const timer = setTimeout(() => { child.kill('SIGKILL'); resolve({ name, code: 'timeout' }); }, TIMEOUT_MS);
    child.on('error', (err) => { clearTimeout(timer); resolve({ name, code: err.code || err.message }); });
    child.on('exit', (code) => { clearTimeout(timer); resolve({ name, code }); });
  });

console.log(`\nWarming ${targets.length} account(s), one at a time...\n`);
const results = [];
for (const a of targets) {
  const started = Date.now();
  const r = await warm(a.name);
  const secs = ((Date.now() - started) / 1000).toFixed(1);
  const ok = r.code === 0;
  console.log(`  ${ok ? 'OK  ' : 'FAIL'} ${r.name}  (${ok ? `${secs}s` : r.code})`);
  results.push({ ...r, ok });
}

const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length} warmed, ${failed.length} failed.`);
if (failed.length) {
  console.log('A failure here usually means `claude` is not on PATH, or the account needs a fresh login.');
  process.exit(1);
}
