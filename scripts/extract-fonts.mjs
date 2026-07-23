#!/usr/bin/env node
// Extracts the Anthropic Sans TTFs bundled inside your OWN local install of
// Claude.app (app.asar) into ./fonts, so the overlay renders in the exact
// font Claude's own UI uses. Each user runs this against their own machine —
// the font files are never committed or redistributed (see LICENSE / README).
//
// asar layout: [u32 =4][u32 headerPickleSize][u32 stringPickle][u32 jsonLen][json][file data...]
import { openSync, readSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const ASAR = "/Applications/Claude.app/Contents/Resources/app.asar";
const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const OUT = join(REPO_ROOT, "fonts");

if (!existsSync(ASAR)) {
  console.error(`Claude.app not found at ${ASAR}.`);
  console.error("Install the Claude desktop app first, then re-run this script.");
  process.exit(1);
}

const fd = openSync(ASAR, "r");
const head = Buffer.alloc(16);
readSync(fd, head, 0, 16, 0);
const headerPickleSize = head.readUInt32LE(4);
const jsonLen = head.readUInt32LE(12);
const jsonBuf = Buffer.alloc(jsonLen);
readSync(fd, jsonBuf, 0, jsonLen, 16);
const index = JSON.parse(jsonBuf.toString("utf8"));
const dataStart = 8 + headerPickleSize;

const hits = [];
(function walk(node, path) {
  if (!node.files) return;
  for (const [name, child] of Object.entries(node.files)) {
    const p = path ? `${path}/${name}` : name;
    if (child.files) walk(child, p);
    else if (/AnthropicSans.*\.ttf$/i.test(name)) hits.push({ p, ...child });
  }
})(index, "");

if (!hits.length) {
  console.error("No AnthropicSans*.ttf entries found in app.asar.");
  console.error("Claude.app's internals may have changed — this script may need updating.");
  process.exit(1);
}

mkdirSync(OUT, { recursive: true });
const written = new Set();
for (const h of hits) {
  const clean = h.p.split("/").pop().replace(/-[A-Za-z0-9_]{8}(\.ttf)$/i, "$1");
  if (written.has(clean)) continue; // same file is bundled per-window; dedupe
  if (h.unpacked) {
    console.log(`skip (unpacked, not supported by this script): ${h.p}`);
    continue;
  }
  const buf = Buffer.alloc(h.size);
  readSync(fd, buf, 0, h.size, dataStart + Number(h.offset));
  writeFileSync(join(OUT, clean), buf);
  written.add(clean);
  console.log(`extracted: ${clean} (${h.size}b)`);
}

console.log(`\ndone — ${written.size} font file(s) in ${OUT}`);
console.log("These are Anthropic's fonts, extracted from your own local install.");
console.log("Do not commit or redistribute them (see .gitignore / LICENSE).");
