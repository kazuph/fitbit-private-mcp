#!/usr/bin/env node
// Cloudflare Workers向けパッチスクリプト
// MoonBit生成コードのグローバルスコープ制限を回避する
import { readFileSync, writeFileSync } from 'fs';

const file = process.argv[2];
if (!file) {
  console.error('Usage: node patch-for-cloudflare.js <file>');
  process.exit(1);
}

let content = readFileSync(file, 'utf-8');
let patched = false;

// 1. Workersがmodule初期化時に拒否するrandom seed生成を固定値へ置換する。
let seedHandled = false;
const seedPatterns = [
  {
    search: 'const _M0FPB4seed = _M0FPB12random__seed();',
    replace: 'const _M0FPB4seed = 0; /* Workers disallow crypto during module initialization */'
  },
  {
    search: 'const moonbitlang$core$builtin$seed = moonbitlang$core$builtin$random_seed();',
    replace: '// Patched for Cloudflare Workers (no global crypto)\nconst moonbitlang$core$builtin$seed = 123456789;\nconst moonbitlang$core$builtin$$$$seed = moonbitlang$core$builtin$seed; // alias for double$$ reference'
  },
  {
    search: 'const moonbitlang$core$builtin$$seed = moonbitlang$core$builtin$$random_seed();',
    replace: '// Patched for Cloudflare Workers (no global crypto)\nconst moonbitlang$core$builtin$$$$seed = 123456789;'
  }
];

for (const { search, replace } of seedPatterns) {
  if (content.includes(search)) {
    content = content.replace(search, replace);
    patched = true;
    seedHandled = true;
    console.log('  Patched: random seed initialization -> fixed value');
    break;
  }
}

if (
  content.includes('Workers disallow crypto during module initialization') ||
  content.includes('Patched for Cloudflare Workers (no global crypto)')
) {
  seedHandled = true;
}

if (!seedHandled) {
  throw new Error(`random seed pattern not found in ${file}; update the Cloudflare patch before building`);
}

// 2. run() の即時実行を削除
const runPattern = /^\(\(\) => \{\s*mizchi\$luna\$sol\$\$run\([^)]+\);\s*\}\)\(\);$/m;
if (runPattern.test(content)) {
  content = content.replace(
    runPattern,
    '// run() removed for Cloudflare Workers'
  );
  patched = true;
  console.log('  Patched: run() immediate execution removed');
}

// 3. ffi_serve 関数を no-op に置換
const ffiServePattern = /const mizchi\$luna\$sol\$\$ffi_serve = \(app, port\) => \{\s*import\('@hono\/node-server'\)\.then\(\(\{ serve \}\) => \{\s*serve\(\{ fetch: app\.fetch, port \}\);\s*\}\);\s*\};/g;
const hasNodeServerImport = content.includes("import('@hono/node-server')");
if (hasNodeServerImport) {
  content = content.replace(
    ffiServePattern,
    'const mizchi$luna$sol$$ffi_serve = (app, port) => { /* noop for Cloudflare Workers */ };'
  );
  patched = true;
  console.log('  Patched: ffi_serve function replaced with noop');
}

if (patched) {
  writeFileSync(file, content);
  console.log(`Patched: ${file}`);
} else {
  console.log(`No patches needed: ${file}`);
}
