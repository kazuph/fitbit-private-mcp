#!/usr/bin/env node
/**
 * Bundle Sol CLI generated client entry points for Cloudflare Workers
 */
import { build } from 'esbuild';
import { readdirSync, existsSync, mkdirSync } from 'fs';
import { join, basename } from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectRoot = join(__dirname, '..');

const solClientDir = join(projectRoot, '.sol/prod/client');
const outputDir = join(projectRoot, 'static');

// Ensure output directory exists
if (!existsSync(outputDir)) {
  mkdirSync(outputDir, { recursive: true });
}

// Check if there are any client files to bundle
if (!existsSync(solClientDir)) {
  console.log('No client entry points found (no island components)');
  process.exit(0);
}

const entryPoints = readdirSync(solClientDir)
  .filter(f => f.endsWith('.js'))
  .map(f => join(solClientDir, f));

if (entryPoints.length === 0) {
  console.log('No client entry points found in .sol/prod/client/');
  process.exit(0);
}

console.log(`Bundling ${entryPoints.length} client entry points...`);

for (const entry of entryPoints) {
  const outputFile = join(outputDir, basename(entry));

  try {
    await build({
      entryPoints: [entry],
      bundle: true,
      format: 'esm',
      outfile: outputFile,
      minify: process.env.NODE_ENV === 'production',
      sourcemap: process.env.NODE_ENV !== 'production',
      platform: 'browser',
      target: ['es2020'],
      external: [],
      logLevel: 'info',
    });

    console.log(`  Bundled: ${basename(entry)}`);
  } catch (error) {
    console.error(`  Failed to bundle ${basename(entry)}:`, error.message);
    process.exit(1);
  }
}

console.log('✓ Client bundling complete');
