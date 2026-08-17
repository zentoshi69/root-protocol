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
  const template = embeddedTemplate(html, relative);
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
    ['valid embedded template', template !== null],
    ['no dead fragment links', template !== null && !template.includes('href="#"')],
  ];
  for (const [label, ok] of checks) if (!ok) failures.push(`${relative}: ${label}`);
  if (statSync(file).size < 100_000) failures.push(`${relative}: unexpectedly small export`);
}

const landingTemplate = embeddedTemplate(readFileSync(join(PUBLIC, 'index.html'), 'utf8'), 'index.html');
const rootTemplate = embeddedTemplate(
  readFileSync(join(PUBLIC, 'root-space/index.html'), 'utf8'),
  'root-space/index.html',
);
const mobileTemplate = embeddedTemplate(
  readFileSync(join(PUBLIC, 'mobile/index.html'), 'utf8'),
  'mobile/index.html',
);

if (landingTemplate !== null) {
  const landingChecks = [
    ['whitepaper title', landingTemplate.includes('Whitepaper - DERIV.WTF')],
    ['whitepaper hero', landingTemplate.includes('The machine, with the covers off.')],
    ['trust model copy', landingTemplate.includes('An attested settlement system, not a custody system.')],
    ['verifier quorum copy', landingTemplate.includes('INDEPENDENT VERIFIERS MUST AGREE')],
    ['old marketing hero removed', !landingTemplate.includes('Derivatives</span> are approved by <span style="color:#DE8C4F">OG holders.</span>')],
    ['old landing card removed', !landingTemplate.includes('class="ux-approval-card"')],
    ['old founder-first headline removed', !landingTemplate.includes("Founders don't choose the supply")],
  ];
  for (const [label, ok] of landingChecks) if (!ok) failures.push(`index.html: ${label}`);
}

if (rootTemplate !== null) {
  const rootChecks = [
    ['canonical approval direction', rootTemplate.includes('>HoodPups</span> <span class="ux-root-arrow"') && rootTemplate.includes('>←</span> <span style="color:#DE8C4F">Bitcoin Puppets</span>')],
    ['holder approval badge', rootTemplate.includes('PUPPET HOLDERS APPROVED')],
    ['plain-language explainer', rootTemplate.includes('class="ux-root-explainer"')],
    ['accessible simulation slider', rootTemplate.includes('aria-label="Simulation day"')],
    ['accessible lifecycle map', rootTemplate.includes('aria-label="One-to-one lifecycle map of Bitcoin Puppets')],
    ['old title direction removed', !rootTemplate.includes('>Bitcoin Puppets</span> <span style="color:rgba(233,233,227,.4)">→</span>')],
  ];
  for (const [label, ok] of rootChecks) if (!ok) failures.push(`root-space/index.html: ${label}`);
}

if (mobileTemplate !== null) {
  const mobileChecks = [
    ['mobile generic approval headline', mobileTemplate.includes('Derivatives</span> are approved by <span style="color:#DE8C4F">OG holders.</span>')],
    ['mobile reversed title', mobileTemplate.includes('>HoodPups</span> <span style="color:rgba(233,233,227,.4)">←</span> <span style="color:#DE8C4F">Bitcoin Puppets</span>')],
    ['accessible mobile maps', occurrences(mobileTemplate, 'role="img" aria-label="Mobile') === 2],
  ];
  for (const [label, ok] of mobileChecks) if (!ok) failures.push(`mobile/index.html: ${label}`);
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

function embeddedTemplate(html, relative) {
  const open = '<script type="__bundler/template">';
  const start = html.indexOf(open);
  const end = start < 0 ? -1 : html.indexOf('</script>', start + open.length);
  if (start < 0 || end < 0) {
    failures.push(`${relative}: embedded template markers`);
    return null;
  }
  try {
    return JSON.parse(html.slice(start + open.length, end));
  } catch (error) {
    failures.push(`${relative}: embedded template JSON (${error.message})`);
    return null;
  }
}
