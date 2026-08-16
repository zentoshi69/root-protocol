#!/usr/bin/env node

import { existsSync, readFileSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const PUBLIC = join(ROOT, 'public');
const pages = [
  'index.html',
  'root-space/index.html',
  'mint/index.html',
  'holders/index.html',
  'protocol/index.html',
  'mobile/index.html',
];
const failures = [];

for (const relative of pages) {
  const file = join(PUBLIC, relative);
  if (!existsSync(file)) {
    failures.push(`${relative}: missing`);
    continue;
  }

  const html = readFileSync(file, 'utf8');
  const checks = [
    ['language', html.includes('<html lang="en">')],
    ['embedded language', html.includes('<html lang=\\"en\\"><head>')],
    ['title', html.includes('<title>') && !html.includes('<title>Bundled Page</title>')],
    ['description', occurrences(html, 'name=\\"description\\"') >= 1 && html.includes('name="description"')],
    ['canonical', html.includes('rel="canonical"') && html.includes('rel=\\"canonical\\"')],
    ['build marker', occurrences(html, 'deriv-build') === 2],
    ['clean source links', !html.includes('.dc.html')],
    ['risk language', html.includes('PRE-AUDIT') || html.includes('Pre-audit')],
    ['reduced motion', html.includes('prefers-reduced-motion')],
    ['no remote font dependency', !html.includes('fonts.googleapis.com') && !html.includes('fonts.gstatic.com')],
  ];
  for (const [label, ok] of checks) if (!ok) failures.push(`${relative}: ${label}`);
  if (statSync(file).size < 100_000) failures.push(`${relative}: unexpectedly small export`);
}

for (const relative of [
  '404.html',
  'favicon.svg',
  'og-image.png',
  'robots.txt',
  'site.webmanifest',
  'sitemap.xml',
  'healthz',
  'version.json',
  'build-manifest.json',
]) {
  if (!existsSync(join(PUBLIC, relative))) failures.push(`${relative}: missing production asset`);
}

if (failures.length > 0) {
  console.error(`Static release verification failed (${failures.length}):`);
  for (const failure of failures) console.error(`  - ${failure}`);
  process.exit(1);
}

console.log(`Static release verification passed: ${pages.length} pages + production assets`);

function occurrences(haystack, needle) {
  return haystack.split(needle).length - 1;
}
