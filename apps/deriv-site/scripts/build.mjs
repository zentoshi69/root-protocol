#!/usr/bin/env node

import {
  copyFileSync,
  cpSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { rewriteEmbeddedTemplate } from './ux-transform.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SOURCE = join(ROOT, 'source');
const STATIC = join(ROOT, 'static');
const OUT = join(ROOT, 'public');
const ORIGIN = 'https://deriv.wtf';

const pages = [
  {
    source: 'Landing.dc.html',
    route: '/',
    output: 'index.html',
    title: 'HoodPups, approved by Bitcoin Puppets — DERIV.WTF',
    description:
      'Each HoodPup maps to one Bitcoin Puppet and can exist only with its matching holder approval. Explore the pre-audit Root Protocol demonstration.',
  },
  {
    source: 'Root Space.dc.html',
    route: '/root-space/',
    output: 'root-space/index.html',
    title: 'HoodPups ← Bitcoin Puppets — DERIV.WTF',
    description:
      'Explore how Bitcoin Puppet holders approve matching HoodPups one ID and one signature at a time.',
  },
  {
    source: 'Mint Tracker.dc.html',
    route: '/mint/',
    output: 'mint/index.html',
    title: 'Mint & Track — DERIV.WTF',
    description:
      'Walk through the HoodPups demo mint and settlement tracker. Pre-audit demonstration data; no mainnet deployment.',
  },
  {
    source: 'Holder Console.dc.html',
    route: '/holders/',
    output: 'holders/index.html',
    title: 'Holder Console — DERIV.WTF',
    description:
      'Review the cold-wallet-first holder consent flow. Your Bitcoin Puppet never leaves Bitcoin.',
  },
  {
    source: 'Protocol.dc.html',
    route: '/protocol/',
    output: 'protocol/index.html',
    title: 'Protocol Transparency — DERIV.WTF',
    description:
      'Read the Root Protocol trust model, verifier assumptions, settlement states, and pre-audit limitations.',
  },
  {
    source: 'Mobile.dc.html',
    route: '/mobile/',
    output: 'mobile/index.html',
    title: 'Mobile Product Preview — DERIV.WTF',
    description: 'Preview the DERIV.WTF mobile product experience and protocol flows.',
  },
];

const routeRewrites = new Map([
  ['Landing.dc.html', '/'],
  ['Root Space.dc.html', '/root-space/'],
  ['Mint Tracker.dc.html', '/mint/'],
  ['Holder Console.dc.html', '/holders/'],
  ['Protocol.dc.html', '/protocol/'],
  ['Mobile.dc.html', '/mobile/'],
]);

const buildId = cleanBuildId(process.env.BUILD_ID || 'local');

rmSync(OUT, { recursive: true, force: true });
mkdirSync(OUT, { recursive: true });
cpSync(STATIC, OUT, { recursive: true });

for (const page of pages) {
  const canonical = `${ORIGIN}${page.route}`;
  let html = readFileSync(join(SOURCE, page.source), 'utf8');

  for (const [from, to] of routeRewrites) html = html.replaceAll(from, to);

  html = html.replace('<html>', '<html lang="en">');
  html = html.replace('<html><head>', '<html lang=\\"en\\"><head>');

  const outerMeta = metadata(page, canonical, buildId, true);
  const innerMeta = metadata(page, canonical, buildId, false);

  const outerTitle = '<title>Bundled Page</title>';
  if (!html.includes(outerTitle)) fail(`${page.source}: outer title marker is missing`);
  html = html.replace(outerTitle, outerMeta);

  const embeddedCharset = '<meta charset=\\"utf-8\\">\\n';
  if (!html.includes(embeddedCharset)) fail(`${page.source}: embedded document marker is missing`);
  html = html.replace(embeddedCharset, `${embeddedCharset}${escapeJsonFragment(innerMeta)}\\n`);
  html = rewriteEmbeddedTemplate(html, page.source);

  const destination = join(OUT, page.output);
  mkdirSync(dirname(destination), { recursive: true });
  writeFileSync(destination, html);
}

writeFileSync(join(OUT, 'sitemap.xml'), sitemap(pages));
writeFileSync(
  join(OUT, 'version.json'),
  `${JSON.stringify({ buildId, status: 'ok' }, null, 2)}\n`,
);
writeFileSync(join(OUT, 'healthz'), 'ok\n');
copyFileSync(join(SOURCE, 'README.upstream.txt'), join(OUT, 'DESIGN-EXPORT.txt'));

const manifest = {};
for (const page of pages) {
  const bytes = readFileSync(join(OUT, page.output));
  manifest[page.route] = {
    file: page.output,
    bytes: bytes.byteLength,
    sha256: createHash('sha256').update(bytes).digest('hex'),
  };
}
writeFileSync(
  join(OUT, 'build-manifest.json'),
  `${JSON.stringify({ buildId, pages: manifest }, null, 2)}\n`,
);

console.log(`Built ${pages.length} pages for ${ORIGIN} (${buildId})`);

function metadata(page, canonical, id, includeViewport) {
  const jsonLd = JSON.stringify({
    '@context': 'https://schema.org',
    '@type': 'WebSite',
    name: 'DERIV.WTF',
    url: ORIGIN,
    description: page.description,
  }).replaceAll('</', '<\\/');

  return [
    `<title>${escapeHtml(page.title)}</title>`,
    includeViewport ? '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">' : '',
    `<meta name="description" content="${escapeHtml(page.description)}">`,
    '<meta name="robots" content="index,follow,max-image-preview:large">',
    '<meta name="theme-color" content="#131412">',
    '<meta name="color-scheme" content="dark">',
    `<meta name="deriv-build" content="${escapeHtml(id)}">`,
    `<link rel="canonical" href="${canonical}">`,
    '<link rel="icon" href="/favicon.svg" type="image/svg+xml">',
    '<link rel="manifest" href="/site.webmanifest">',
    '<meta property="og:type" content="website">',
    '<meta property="og:site_name" content="DERIV.WTF">',
    `<meta property="og:title" content="${escapeHtml(page.title)}">`,
    `<meta property="og:description" content="${escapeHtml(page.description)}">`,
    `<meta property="og:url" content="${canonical}">`,
    `<meta property="og:image" content="${ORIGIN}/og-image.png">`,
    '<meta property="og:image:width" content="1200">',
    '<meta property="og:image:height" content="630">',
    '<meta property="og:image:alt" content="DERIV.WTF — cross-chain community consent protocol">',
    '<meta name="twitter:card" content="summary_large_image">',
    `<meta name="twitter:title" content="${escapeHtml(page.title)}">`,
    `<meta name="twitter:description" content="${escapeHtml(page.description)}">`,
    `<meta name="twitter:image" content="${ORIGIN}/og-image.png">`,
    `<style id="production-accessibility-patch">${productionCss()}</style>`,
    `<script type="application/ld+json">${jsonLd}</script>`,
  ]
    .filter(Boolean)
    .join('\n  ');
}

function productionCss() {
  return `
:root {
  --ux-bg: #11120f;
  --ux-surface: #191a17;
  --ux-surface-raised: #1e201b;
  --ux-text: #f4f4ee;
  --ux-muted: rgba(233,233,227,.68);
  --ux-line: rgba(233,233,227,.16);
  --ux-lime: #c8f135;
  --ux-orange: #de8c4f;
  --ux-ease: cubic-bezier(.16,.8,.24,1);
}
html {
  background: var(--ux-bg);
  scroll-behavior: smooth;
}
body {
  background: var(--ux-bg);
}
::selection {
  background: var(--ux-lime);
  color: #131412;
}
[data-screen-label] {
  background:
    radial-gradient(circle at 78% 7%, rgba(200,241,53,.055), transparent 28rem),
    radial-gradient(circle at 16% 32%, rgba(222,140,79,.035), transparent 24rem),
    var(--ux-bg) !important;
}
header {
  background: rgba(17,18,15,.88) !important;
  backdrop-filter: blur(18px) saturate(125%);
  -webkit-backdrop-filter: blur(18px) saturate(125%);
  box-shadow: 0 1px 0 rgba(255,255,255,.035), 0 12px 38px rgba(0,0,0,.24);
}
header a,
header button {
  min-height: 44px;
  display: inline-flex !important;
  align-items: center;
  justify-content: center;
  transition: color .2s var(--ux-ease), border-color .2s var(--ux-ease), background .2s var(--ux-ease), transform .2s var(--ux-ease);
}
header nav a {
  position: relative;
}
header nav a::after {
  content: "";
  position: absolute;
  left: 0;
  right: 0;
  bottom: 4px;
  height: 2px;
  background: currentColor;
  transform: scaleX(0);
  transform-origin: left;
  transition: transform .2s var(--ux-ease);
}
header nav a:hover::after,
header nav a:focus-visible::after,
header nav a[style*="color:#C8F135"]::after,
header nav a[style*="color:#DE8C4F"]::after {
  transform: scaleX(1);
}
button {
  min-height: 44px;
}
a[style*="background:#C8F135"],
button[style*="background:#C8F135"] {
  box-shadow: 0 0 0 1px rgba(200,241,53,.2), 0 10px 30px rgba(200,241,53,.09);
  transition: transform .2s var(--ux-ease), background .2s var(--ux-ease), box-shadow .2s var(--ux-ease);
}
a[style*="background:#C8F135"]:hover,
button[style*="background:#C8F135"]:hover {
  transform: translateY(-2px);
  box-shadow: 0 0 0 1px rgba(200,241,53,.28), 0 14px 34px rgba(200,241,53,.15);
}
[style*="color:rgba(233,233,227,.48)"] {
  color: rgba(233,233,227,.68) !important;
}
[style*="color:rgba(233,233,227,.4)"] {
  color: rgba(233,233,227,.6) !important;
}
:where(a,button,input,select,textarea,summary):focus-visible {
  outline: 3px solid #fff !important;
  outline-offset: 3px !important;
}
[data-ux-section="hero"] {
  display: grid !important;
  grid-template-columns: minmax(0,1.08fr) minmax(360px,.82fr) !important;
  column-gap: clamp(32px,5vw,72px) !important;
  row-gap: 48px !important;
  align-items: start;
  padding-top: clamp(56px,7vw,88px) !important;
}
.ux-hero-copy {
  min-width: 0;
  padding-top: 8px;
}
.ux-hero-copy h1 {
  max-width: 17ch;
  font-size: clamp(34px,4vw,58px) !important;
  line-height: 1.08 !important;
}
.ux-hero-copy > p:first-of-type {
  max-width: 60ch !important;
}
.ux-approval-card {
  position: relative;
  isolation: isolate;
  overflow: hidden;
  border: 1px solid rgba(200,241,53,.28);
  background:
    linear-gradient(145deg, rgba(200,241,53,.075), transparent 42%),
    linear-gradient(180deg, #1d1f1a, #171815);
  box-shadow:
    -9px 9px 0 rgba(222,140,79,.11),
    9px 9px 0 rgba(200,241,53,.11),
    0 26px 70px rgba(0,0,0,.26);
  padding: 28px;
  animation: rise .7s var(--ux-ease) .2s backwards;
}
.ux-approval-card::after {
  content: "";
  position: absolute;
  inset: 0;
  z-index: -1;
  pointer-events: none;
  opacity: .16;
  background-image:
    linear-gradient(rgba(233,233,227,.08) 1px, transparent 1px),
    linear-gradient(90deg, rgba(233,233,227,.08) 1px, transparent 1px);
  background-size: 24px 24px;
  mask-image: linear-gradient(to bottom, #000, transparent 74%);
}
.ux-card-kicker,
.ux-card-foot {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 16px;
  font-family: 'Silkscreen', ui-monospace, monospace;
  font-size: 9px;
  letter-spacing: .13em;
  color: var(--ux-muted);
}
.ux-live-chip {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  color: var(--ux-lime);
  white-space: nowrap;
}
.ux-live-chip i {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--ux-lime);
  box-shadow: 0 0 14px rgba(200,241,53,.75);
  animation: pulseDot 1.6s ease-in-out infinite;
}
.ux-approval-card h2 {
  display: grid;
  gap: 7px;
  margin: 44px 0 22px;
  font-family: 'Silkscreen', ui-monospace, monospace;
  font-size: clamp(25px,2.7vw,38px);
  line-height: 1.08;
  letter-spacing: -.015em;
}
.ux-hoodpup { color: var(--ux-lime); }
.ux-puppet { color: var(--ux-orange); }
.ux-approved-by {
  font-size: 10px;
  letter-spacing: .16em;
  color: rgba(244,244,238,.72);
}
.ux-approval-card > p {
  max-width: 49ch;
  margin: 0 0 28px;
  color: rgba(244,244,238,.72);
  font-size: 15px;
  line-height: 1.65;
}
.ux-proof-grid {
  display: grid;
  grid-template-columns: repeat(3,1fr);
  gap: 1px;
  border: 1px solid var(--ux-line);
  background: var(--ux-line);
}
.ux-proof-grid > div {
  min-width: 0;
  background: rgba(11,12,10,.78);
  padding: 14px 12px;
}
.ux-proof-grid strong,
.ux-proof-grid span {
  display: block;
  font-family: 'Silkscreen', ui-monospace, monospace;
}
.ux-proof-grid strong {
  margin-bottom: 5px;
  color: var(--ux-text);
  font-size: 18px;
}
.ux-proof-grid span {
  color: var(--ux-muted);
  font-size: 7.5px;
  line-height: 1.45;
  letter-spacing: .08em;
}
.ux-card-foot {
  margin-top: 18px;
  color: rgba(233,233,227,.58);
}
.ux-card-foot span:first-child { color: var(--ux-orange); }
.ux-card-foot span:last-child { color: var(--ux-lime); text-align: right; }
.ux-live-map {
  grid-column: 1 / -1;
}
.ux-live-map > div,
[data-screen-label="Participation map"] > div {
  box-shadow:
    -10px 10px 0 rgba(222,140,79,.12),
    10px 10px 0 rgba(200,241,53,.12),
    0 28px 70px rgba(0,0,0,.22) !important;
}
main section[data-screen-label] {
  scroll-margin-top: 96px;
}
main section[data-screen-label] > div[style*="border:1px"],
main section[data-screen-label] > div > div[style*="border:1px"] {
  transition: border-color .22s var(--ux-ease), transform .22s var(--ux-ease), background .22s var(--ux-ease);
}
main section[data-screen-label] > div[style*="border:1px"]:hover,
main section[data-screen-label] > div > div[style*="border:1px"]:hover {
  border-color: rgba(233,233,227,.25) !important;
}
.ux-root-summary {
  position: relative;
}
.ux-root-header {
  border: 1px solid rgba(233,233,227,.13);
  background:
    linear-gradient(105deg, rgba(200,241,53,.035), transparent 46%),
    rgba(25,26,23,.72);
  box-shadow: 0 22px 58px rgba(0,0,0,.18);
  padding: 22px;
}
.ux-root-art {
  width: 124px !important;
  height: 124px !important;
  border-color: rgba(200,241,53,.32) !important;
  box-shadow: 0 0 0 6px rgba(200,241,53,.035), 0 18px 40px rgba(0,0,0,.32);
}
.ux-root-title {
  font-size: clamp(34px,3.5vw,50px) !important;
  line-height: 1.08 !important;
  text-wrap: balance;
}
.ux-root-arrow {
  display: inline-block;
  margin: 0 .08em;
}
.ux-root-explainer {
  max-width: 74ch;
  margin: 13px 0 15px;
  color: rgba(244,244,238,.72);
  font-size: 14px;
  line-height: 1.6;
}
@media (max-width: 600px) {
  header > div:first-child {
    padding-left: 16px !important;
    padding-right: 16px !important;
    column-gap: 12px !important;
    row-gap: 8px !important;
  }
  header > div:first-child > nav {
    order: 3;
    width: 100%;
    margin-left: 0 !important;
    justify-content: space-between;
    gap: 9px !important;
    font-size: 9px !important;
  }
  header > div:first-child > div:last-child {
    width: auto;
    margin-left: auto !important;
    display: flex !important;
    gap: 10px !important;
  }
  header > div:first-child > div:last-child > span {
    display: none !important;
  }
  header > div:first-child > div:last-child > a,
  header > div:first-child > div:last-child > button {
    max-width: 100%;
    min-height: 40px;
    font-size: 8.5px !important;
    padding: 10px 12px !important;
  }
  [data-screen-label="Landing"] main > section,
  [data-screen-label="Root Space — Bitcoin Puppets"] main > section:not([data-screen-label="Lifecycle simulator"]) {
    padding-left: 16px !important;
    padding-right: 16px !important;
  }
  [data-ux-section="hero"] {
    display: grid !important;
    grid-template-columns: minmax(0,1fr) !important;
    gap: 34px !important;
    padding-top: 42px !important;
    padding-bottom: 44px !important;
  }
  .ux-hero-copy {
    padding-top: 0;
  }
  .ux-hero-copy h1 {
    max-width: none;
    font-size: clamp(31px,10.4vw,42px) !important;
    line-height: 1.1 !important;
  }
  .ux-hero-copy > p:first-of-type {
    font-size: 16px !important;
    line-height: 1.58 !important;
  }
  .ux-hero-copy > p:nth-of-type(2) {
    width: 100%;
    box-sizing: border-box;
    font-size: 9px !important;
    line-height: 1.5;
  }
  .ux-hero-copy > div:last-child {
    display: grid !important;
    grid-template-columns: 1fr;
  }
  .ux-hero-copy > div:last-child > a {
    width: 100%;
    min-height: 50px;
    box-sizing: border-box;
    display: flex !important;
    align-items: center;
    justify-content: center;
    text-align: center;
  }
  .ux-approval-card {
    padding: 22px 18px;
  }
  .ux-card-kicker {
    align-items: flex-start;
    flex-direction: column;
  }
  .ux-approval-card h2 {
    margin: 30px 0 18px;
    font-size: clamp(24px,8.5vw,33px);
  }
  .ux-proof-grid > div {
    padding: 12px 8px;
  }
  .ux-proof-grid strong { font-size: 16px; }
  .ux-proof-grid span { font-size: 7px; }
  .ux-card-foot {
    align-items: flex-start;
    flex-direction: column;
  }
  .ux-card-foot span:last-child { text-align: left; }
  .ux-live-map > div {
    padding: 17px 14px 15px !important;
  }
  .ux-live-map > div > div:first-child,
  [data-screen-label="Participation map"] > div > div:first-child {
    align-items: flex-start !important;
  }
  .ux-live-map > div > div:first-child > span:last-child,
  [data-screen-label="Participation map"] > div > div:first-child > span:last-child {
    width: 100%;
    margin-left: 0 !important;
    white-space: normal !important;
    line-height: 1.55;
  }
  .ux-live-map > div > div:nth-child(2),
  [data-screen-label="Participation map"] > div > div:nth-child(2) {
    grid-template-columns: minmax(0,1fr) !important;
    gap: 10px !important;
  }
  .ux-live-map > div > div:nth-child(2) > div:nth-child(2),
  [data-screen-label="Participation map"] > div > div:nth-child(2) > div:nth-child(2) {
    text-align: left !important;
  }
  .ux-live-map > div > div:nth-child(2) > div:last-child,
  [data-screen-label="Participation map"] > div > div:nth-child(2) > div:last-child {
    text-align: left !important;
  }
  .ux-root-summary {
    padding-top: 26px !important;
  }
  .ux-root-header {
    gap: 16px !important;
    padding: 17px;
  }
  .ux-root-art {
    width: 82px !important;
    height: 82px !important;
  }
  .ux-root-title {
    font-size: clamp(28px,9.4vw,38px) !important;
    line-height: 1.16 !important;
  }
  .ux-root-explainer {
    font-size: 13.5px;
    margin-top: 16px;
  }
  [data-screen-label="Lifecycle simulator"] {
    position: relative !important;
    top: auto !important;
  }
  [data-screen-label="Lifecycle simulator"] > div {
    gap: 10px !important;
    padding-left: 16px !important;
    padding-right: 16px !important;
  }
  [data-screen-label="Lifecycle simulator"] > div > div {
    order: 5;
    width: 100%;
    overflow-x: auto;
    padding-bottom: 4px;
  }
  [data-screen-label="Lifecycle simulator"] > div > div > span {
    flex: none;
  }
  [data-screen-label="Lifecycle simulator"] input[type="range"] {
    order: 4;
    flex-basis: 100%;
  }
  [data-screen-label="Participation map"] > div {
    padding: 17px 14px 15px !important;
  }
  [data-screen-label="Live counters"] > div {
    grid-template-columns: repeat(2,minmax(0,1fr)) !important;
  }
  [data-screen-label="Vote, terms, truth"],
  [data-screen-label="Feed and modes"] {
    grid-template-columns: minmax(0,1fr) !important;
  }
  [data-screen-label="Mobile designs"] {
    padding: 24px 16px 40px !important;
    overflow-x: hidden;
  }
  [data-screen-label="Mobile designs"] > div:nth-child(3) {
    width: 100%;
    max-width: 100%;
    gap: 20px !important;
    overflow-x: auto;
    overscroll-behavior-x: contain;
    scroll-snap-type: x mandatory;
    scrollbar-width: thin;
    padding-bottom: 16px;
  }
  [data-screen-label="Mobile designs"] > div:nth-child(3) > div {
    flex: 0 0 100% !important;
    width: 100%;
    min-width: 0;
    overflow: hidden;
    scroll-snap-align: start;
  }
  [data-screen-label="Mobile designs"] > div:nth-child(3) > div > div:last-child {
    transform-origin: top left;
  }
}
@media (max-width: 380px) {
  [data-screen-label="Mobile designs"] > div:nth-child(3) > div > div:last-child {
    zoom: .815;
  }
}
@media (min-width: 381px) and (max-width: 410px) {
  [data-screen-label="Mobile designs"] > div:nth-child(3) > div > div:last-child {
    zoom: .89;
  }
}
@media (prefers-reduced-motion: reduce) {
  html { scroll-behavior: auto !important; }
  *, *::before, *::after {
    transition-duration: .001ms !important;
    animation-duration: .001ms !important;
    animation-iteration-count: 1 !important;
  }
}`.trim();
}

function escapeJsonFragment(value) {
  // This fragment lives inside a <script> element containing a JSON string. A literal closing
  // script tag would terminate the outer element before JSON.parse sees it, so encode the slash as
  // a JSON unicode escape after the ordinary string escaping pass.
  return value
    .replaceAll('\\', '\\\\')
    .replaceAll('"', '\\"')
    .replaceAll('\n', '\\n')
    .replaceAll('</', '<\\u002F');
}

function escapeHtml(value) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
}

function cleanBuildId(value) {
  if (!/^[A-Za-z0-9._-]{1,80}$/.test(value)) fail('BUILD_ID must be 1-80 safe filename characters');
  return value;
}

function sitemap(entries) {
  const urls = entries
    .filter((entry) => entry.route !== '/mobile/')
    .map((entry) => `  <url><loc>${ORIGIN}${entry.route}</loc></url>`)
    .join('\n');
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>\n`;
}

function fail(message) {
  throw new Error(message);
}
