import { readFile, stat } from "node:fs/promises";

const MIN_BUNDLE_BYTES = 1024;
const REQUIRED_MARKERS = [
  { needle: "/api/cron", reason: "manual cron endpoint" },
  { needle: "scheduled", reason: "Cloudflare scheduled handler" },
];

const target = process.argv[2];
if (!target) {
  console.error("usage: check-worker-bundle.ts <path-to-bundle.js>");
  process.exit(2);
}

let info;
try {
  info = await stat(target);
} catch (error) {
  console.error(`worker bundle check: cannot stat ${target}: ${String(error)}`);
  process.exit(1);
}

if (!info.isFile() || info.size < MIN_BUNDLE_BYTES) {
  console.error(
    `worker bundle check: ${target} is not a valid worker bundle (${info.size} bytes)`,
  );
  process.exit(1);
}

const content = await readFile(target, "utf8");
const invalidControlByte = content.indexOf("\x1f");
if (invalidControlByte >= 0) {
  console.error(
    `worker bundle check: unexpected \\x1f at offset ${invalidControlByte} in ${target}`,
  );
  process.exit(1);
}

for (const marker of REQUIRED_MARKERS) {
  if (!content.includes(marker.needle)) {
    console.error(
      `worker bundle check: missing ${marker.reason} marker (${marker.needle}) in ${target}`,
    );
    process.exit(1);
  }
}

console.log(`worker bundle check: ok (${target}, ${info.size} bytes)`);
