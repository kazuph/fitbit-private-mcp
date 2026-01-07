#!/usr/bin/env node
/**
 * Patch Sol CLI generated types for Cloudflare Workers
 * Must run BEFORE moon build
 */
import { readFileSync, writeFileSync, existsSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectRoot = join(__dirname, '..');

const typesMbtPath = join(projectRoot, 'app/__gen__/types/types.mbt');

if (existsSync(typesMbtPath)) {
  let content = readFileSync(typesMbtPath, 'utf-8');

  // Check if it has /static/ prefix that needs to be removed
  if (content.includes('url: "/static/')) {
    content = content.replace(/url: "\/static\//g, 'url: "/');
    writeFileSync(typesMbtPath, content);
    console.log('Patched: types.mbt - Removed /static/ prefix from asset URLs');
  } else {
    console.log('types.mbt: No patches needed');
  }
} else {
  console.log('types.mbt: File not found (generate first with sol generate)');
}
