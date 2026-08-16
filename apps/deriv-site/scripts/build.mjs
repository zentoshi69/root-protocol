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
    title: 'DERIV.WTF — Cross-chain consent for NFT derivatives',
    description:
      'Original NFT communities approve derivatives one holder signature at a time. Explore the pre-audit Root Protocol demonstration.',
  },
  {
    source: 'Root Space.dc.html',
    route: '/root-space/',
    output: 'root-space/index.html',
    title: 'Puppets Root Space — DERIV.WTF',
    description:
      'Explore the Bitcoin Puppets Root Space lifecycle and see how community consent reveals derivative supply.',
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
:where(a,button,input,select,textarea,summary):focus-visible {
  outline: 3px solid #fff !important;
  outline-offset: 3px !important;
}
@media (max-width: 600px) {
  header > div:first-child {
    padding-left: 16px !important;
    padding-right: 16px !important;
    column-gap: 12px !important;
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
    width: 100%;
    margin-left: 0 !important;
    display: grid !important;
    grid-template-columns: minmax(0, 1fr) auto;
    gap: 10px !important;
  }
  header > div:first-child > div:last-child > span {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    font-size: 8px !important;
    padding: 7px 8px !important;
  }
  header > div:first-child > div:last-child > a,
  header > div:first-child > div:last-child > button {
    max-width: 100%;
    font-size: 9px !important;
    padding: 10px 12px !important;
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
