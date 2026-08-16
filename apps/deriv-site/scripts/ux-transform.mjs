const TEMPLATE_OPEN = '<script type="__bundler/template">';
const TEMPLATE_CLOSE = '</script>';

export function rewriteEmbeddedTemplate(html, source) {
  const openAt = html.indexOf(TEMPLATE_OPEN);
  if (openAt < 0) fail(`${source}: embedded template start marker is missing`);

  const jsonAt = openAt + TEMPLATE_OPEN.length;
  const closeAt = html.indexOf(TEMPLATE_CLOSE, jsonAt);
  if (closeAt < 0) fail(`${source}: embedded template end marker is missing`);

  let template;
  try {
    template = JSON.parse(html.slice(jsonAt, closeAt));
  } catch (error) {
    fail(`${source}: embedded template is not valid JSON (${error.message})`);
  }

  template = transformSharedNavigation(template);

  if (source === 'Landing.dc.html') template = transformLanding(template);
  if (source === 'Root Space.dc.html') template = transformRootSpace(template);
  if (source === 'Mobile.dc.html') template = transformMobilePreview(template);

  const encoded = JSON.stringify(template).replaceAll('</', '<\\u002F');
  return `${html.slice(0, jsonAt)}${encoded}${html.slice(closeAt)}`;
}

function transformSharedNavigation(template) {
  return template
    .replaceAll('>ROOT SPACES<', '>ROOT SPACE<')
    .replaceAll('>HOLDERS<', '>FOR HOLDERS<')
    .replaceAll('ROBINHOOD CHAIN · PRE-AUDIT', 'ROBINHOOD CHAIN · PRE-AUDIT DEMO')
    .replaceAll('>LAUNCH APP<', '>LIVE MINT<')
    .replaceAll('>MINT A HOODPUP<', '>OPEN MINT DEMO<');
}

function transformLanding(template) {
  template = replaceRequired(
    template,
    '<section style="max-width:1280px;margin:0 auto;padding:72px 32px 56px;display:flex;flex-direction:column;gap:48px">\n  <div>',
    '<section data-ux-section="hero" style="max-width:1280px;margin:0 auto;padding:72px 32px 56px;display:flex;flex-direction:column;gap:48px">\n  <div class="ux-hero-copy">',
    'landing hero shell',
  );
  template = replaceRequired(
    template,
    "ROOT PROTOCOL · CROSS-CHAIN CONSENT LAYER",
    'DERIV.WTF · OG HOLDER APPROVAL LAYER',
    'landing hero kicker',
  );
  template = replaceRequired(
    template,
    '<h1 data-rise="2" style="animation:rise .7s cubic-bezier(.16,.8,.24,1) .08s backwards;margin:0 0 24px;font-family:\'Silkscreen\',ui-monospace,monospace;font-size:clamp(30px,3.6vw,56px);line-height:1.14;letter-spacing:0;font-weight:700;text-wrap:balance;color:#FFFFFF">Founders don\'t choose the supply. The community <em style="font-style:italic;color:#C8F135">reveals</em> it.</h1>',
    '<h1 data-rise="2" style="animation:rise .7s cubic-bezier(.16,.8,.24,1) .08s backwards;margin:0 0 24px;font-family:\'Silkscreen\',ui-monospace,monospace;font-size:clamp(30px,3.6vw,56px);line-height:1.14;letter-spacing:0;font-weight:700;text-wrap:balance;color:#FFFFFF"><span style="color:#C8F135">Derivatives</span> are approved by <span style="color:#DE8C4F">OG holders.</span></h1>',
    'landing hero headline',
  );
  template = replaceRequired(
    template,
    "DERIV.WTF is where original NFT communities approve their derivatives instead of merely being copied by them. The community governs the proposal, every single ID needs its own holder's signature, and the final supply is discovered by participation — never picked by a founder.",
    "DERIV.WTF is where derivative collections earn approval from the holders of their OG collections. Each derivative ID maps to one original ID, and no mint can open unless the matching holder signs. The original stays where it belongs.",
    'landing hero explanation',
  );
  template = replaceRequired(
    template,
    'Your Bitcoin Puppet never leaves Bitcoin.',
    'NO BRIDGE · NO TRANSFER · THE OG NEVER LEAVES ITS HOME CHAIN',
    'landing custody assurance',
  );
  template = replaceRequired(
    template,
    'ENTER THE PUPPETS ROOT SPACE&nbsp;&nbsp;→',
    'EXPLORE THE APPROVAL MAP&nbsp;&nbsp;→',
    'landing primary action',
  );
  template = replaceRequired(
    template,
    'HOW SETTLEMENT WORKS',
    'HOW APPROVAL WORKS',
    'landing secondary action',
  );

  const approvalCard = `
  <aside class="ux-approval-card" data-rise="6" aria-label="Live HoodPups mint approval by Bitcoin Puppet holders">
    <div class="ux-card-kicker"><span>LIVE MINT NOW</span><span class="ux-live-chip"><i></i> PRE-AUDIT DEMO</span></div>
    <h2><span class="ux-hoodpup">HoodPups</span> <span class="ux-approved-by">← APPROVED BY</span> <span class="ux-puppet">Bitcoin Puppets</span></h2>
    <p>The active mint is HoodPups. Each HoodPup can exist only if the holder of its matching Bitcoin Puppet approves it. Every ID is matched one-to-one.</p>
    <div class="ux-proof-grid" role="list" aria-label="Approval guarantees">
      <div role="listitem"><strong>1:1</strong><span>MATCHED IDS</span></div>
      <div role="listitem"><strong>1</strong><span>HOLDER SIGNATURE</span></div>
      <div role="listitem"><strong>0</strong><span>ORIGINALS MOVED</span></div>
    </div>
    <div class="ux-card-foot"><span>BITCOIN · ORIGINAL</span><span>ROBINHOOD · APPROVED BRANCH</span></div>
  </aside>`;

  template = replaceRequired(
    template,
    '    </div>\n  </div>\n\n  <div data-rise="6" style="animation:rise .7s cubic-bezier(.16,.8,.24,1) .2s backwards;position:relative">',
    `    </div>\n  </div>\n${approvalCard}\n\n  <div class="ux-live-map" data-rise="7" style="animation:rise .7s cubic-bezier(.16,.8,.24,1) .2s backwards;position:relative">`,
    'landing approval card insertion',
  );
  template = replaceRequired(
    template,
    '<img src="{{ hatSrc }}" alt="" style="width:200px;filter:drop-shadow(0 0 26px rgba(200,241,53,.9)) drop-shadow(0 0 64px rgba(200,241,53,.45))">',
    '<img src="1d505b69-12d5-4846-8be8-a582097cb205" alt="" style="width:200px;filter:drop-shadow(0 0 26px rgba(200,241,53,.9)) drop-shadow(0 0 64px rgba(200,241,53,.45))">',
    'landing hat modal source',
  );
  template = replaceRequired(
    template,
    'const burst = 1 + Math.floor(Math.random() * 2);',
    'const burst = 1;',
    'landing hat density',
  );
  template = replaceRequired(
    template,
    'const w = 34 + depth * 62;',
    'const w = 26 + depth * 36;',
    'landing hat size',
  );
  template = replaceRequired(
    template,
    "el.style.cssText = 'position:absolute;left:0;top:0;width:' + w.toFixed(0) + 'px;pointer-events:auto;cursor:pointer;will-change:transform;filter:drop-shadow(0 0 ' + (6 + depth * 11).toFixed(0) + 'px rgba(200,241,53,' + (0.3 + depth * 0.45).toFixed(2) + '))';",
    "el.style.cssText = 'position:absolute;left:0;top:0;width:' + w.toFixed(0) + 'px;pointer-events:auto;cursor:pointer;will-change:transform;opacity:.72;filter:drop-shadow(0 0 ' + (5 + depth * 8).toFixed(0) + 'px rgba(200,241,53,' + (0.25 + depth * 0.3).toFixed(2) + '))';",
    'landing hat presentation',
  );
  template = replaceRequired(
    template,
    'this.hats.push({ el, x: 20 + Math.random() * Math.max(60, vw - 130), t0: now + i * 700, dur: 10500 - depth * 4600, sway: 26 + Math.random() * 54, spin: (Math.random() < 0.5 ? -1 : 1) * (0.09 + Math.random() * 0.17), depth });',
    'const edgeX = Math.random() < .5 ? 18 : Math.max(18, vw - w - 18);\n        this.hats.push({ el, x: edgeX + (Math.random() - .5) * 16, t0: now + i * 700, dur: 10800 - depth * 3600, sway: 9 + Math.random() * 13, spin: (Math.random() < 0.5 ? -1 : 1) * (0.07 + Math.random() * 0.11), depth });',
    'landing hat edge lane',
  );
  template = replaceRequired(
    template,
    'this.nextHat = now + 3200 + Math.random() * 5800;',
    'this.nextHat = now + 6800 + Math.random() * 6400;',
    'landing hat cadence',
  );
  template = replaceRequired(
    template,
    'this.hats = []; this.nextHat = performance.now() + 900;',
    'this.hats = []; this.nextHat = performance.now() + 5200;',
    'landing initial hat delay',
  );

  return template
    .replaceAll('LIVE — OG APPROVALS, ONE SIGNATURE AT A TIME', 'LIVE DEMO - OG HOLDER APPROVALS')
    .replaceAll('BITCOIN — 10,001 PUPPETS', 'OG COLLECTION - ORIGINAL IDS')
    .replaceAll('THE ORIGINALS. THEY NEVER MOVE.', 'ORIGINALS STAY PUT.')
    .replaceAll('SIGNATURE<br>BYTES ONLY →', 'ONE HOLDER<br>SIGNATURE →')
    .replaceAll('ROBINHOOD — HOODPUPS ', 'DERIVATIVE - APPROVED SLOTS ')
    .replaceAll('DERIVATIVES APPROVED BY THEIR OG', 'ONLY MATCHING APPROVED IDS CAN MINT')
    .replaceAll('OG — NOT SIGNED', 'NOT YET APPROVED')
    .replaceAll('CONSIDERING AN OFFER', 'REVIEWING AN OFFER')
    .replaceAll('>CONSENT SIGNED</span>', '>HOLDER APPROVED</span>')
    .replaceAll('>SLOT AWAITING CONSENT</span>', '>MINT SLOT PENDING</span>')
    .replaceAll('>HOODPUP APPROVED</span>', '>DERIVATIVE SLOT OPEN</span>')
    .replaceAll('>OG APPROVALS · LIVE</div>', '>HOLDER APPROVALS · LIVE</div>')
    .replaceAll('>UNIQUE OG HOLDERS</div>', '>UNIQUE HOLDERS</div>')
    .replaceAll('It can never move, spend or encumber your Puppet — the protocol holds no Bitcoin key.', 'It can never move, spend, or encumber the original asset - the protocol holds no source-chain key.')
    .replaceAll('Your Bitcoin Puppet never leaves Bitcoin, and no signature this site asks for can spend it.', 'The original asset never leaves its home chain, and no signature this site asks for can spend it.')
    .replaceAll('Nothing here is an endorsement by the Bitcoin Puppets project or Robinhood.', 'Nothing here is an endorsement by any OG collection, derivative collection, or destination chain.')
    .replaceAll('THE BITCOIN PUPPETS PROJECT OR ROBINHOOD', 'ANY OG COLLECTION, DERIVATIVE COLLECTION, OR DESTINATION CHAIN')
    .replaceAll('A collection-wide vote can approve the road. It can never force a single Puppet onto it.', 'A collection-wide vote can approve the road. It can never force a single original asset onto it.')
    .replaceAll('one whale holding 2,000 Puppets can never be "the community."', 'one whale holding 2,000 originals can never be "the community."')
    .replaceAll("After the vote passes, an activation window opens. HoodPup #123 can exist only because the holder of Bitcoin Puppet #123 signed for it — one BIP-322 message, from the wallet that controls the inscription. #6969's holder stays silent, so #6969 can never exist.", "After the vote passes, an activation window opens. Derivative #123 can exist only because the holder of original #123 signed for it - one wallet message from the address that controls the original. If #6969's holder stays silent, derivative #6969 can never exist.")
    .replaceAll('The HoodPups launch, worked end to end:', 'A live branch, worked end to end:')
    .replaceAll('One verified HoodPup may be minted per protocol Root.', 'One verified derivative may be minted per protocol root ID.')
    .replaceAll('The Puppet itself never moves.', 'The original asset itself never moves.')
    .replaceAll('Bitcoin Puppet #123', 'Original #123')
    .replaceAll('mint HoodPup · route 50 / 20 / 20 / 10', 'mint derivative · route 50 / 20 / 20 / 10')
    .replaceAll('Your Puppet is not converted into a token on another chain, and nobody holds it on your behalf. It stays exactly where it is, under your key.', 'Your original is not converted into a token on another chain, and nobody holds it on your behalf. It stays exactly where it is, under your key.')
    .replaceAll('HOODPUPS LAUNCH SPLIT — EVERY PAID MINT, FROM GROSS ESCROW', 'LIVE BRANCH SPLIT - EVERY PAID MINT, FROM GROSS ESCROW')
    .replaceAll('ROOT TREASURY — PUPPETS COMMUNITY', 'ROOT TREASURY - OG COMMUNITY')
    .replaceAll('BRANCH BUILDER — HOODPUPS TEAM', 'BRANCH BUILDER - DERIVATIVE TEAM')
    .replaceAll('WORKED — HOODPUP #123 SELLS FOR 0.10 ETH', 'WORKED - DERIVATIVE #123 SELLS FOR 0.10 ETH')
    .replaceAll('holder of Bitcoin Puppet #123', 'holder of original #123')
    .replaceAll('A HoodPup mints to the wrong recipient', 'A derivative mints to the wrong recipient')
    .replaceAll("Move anyone's Bitcoin Puppet.", "Move anyone's original asset.")
    .replaceAll('Mint a second HoodPup for a Root', 'Mint a second derivative for a root ID')
    .replaceAll('HoodPups sits here.', 'A community-approved branch sits here.')
    .replaceAll('FIRST BRANCH · BITCOIN PUPPETS → ROBINHOOD CHAIN', 'LIVE BRANCH · OG COLLECTION → DESTINATION CHAIN')
    .replaceAll('10,001 Bitcoin Puppets were invited. Their holders are deciding, one signature at a time, how many HoodPups get to exist. The mint supply is not announced — it is watched live.', '10,001 originals are eligible. Their holders decide, one signature at a time, how many derivatives get to exist. The mint supply is not announced - it is watched live.')
    .replaceAll('I HOLD A PUPPET', 'I HOLD AN OG')
    .replaceAll('Puppets Root Space', 'Live Root Space')
    .replaceAll('spend or encumber your Puppet', 'spend or encumber your original')
    .replaceAll('Your Bitcoin Puppet never leaves Bitcoin', 'Your original never leaves its home chain')
    .replaceAll('<canvas ref="{{ mapRef }}" style="width:100%;display:block;margin:0 0 14px;image-rendering:pixelated"></canvas>', '<canvas ref="{{ mapRef }}" role="img" aria-label="Live one-to-one map of OG holder approvals and matching derivative slots" style="width:100%;display:block;margin:0 0 14px;image-rendering:pixelated"></canvas>');
}

function transformRootSpace(template) {
  template = replaceRequired(
    template,
    '<section style="max-width:1280px;margin:0 auto;padding:34px 32px 26px">',
    '<section class="ux-root-summary" style="max-width:1280px;margin:0 auto;padding:34px 32px 26px">',
    'root summary shell',
  );
  template = replaceRequired(
    template,
    '<a href="/" style="color:rgba(233,233,227,.4)" style-hover="color:#E9E9E3">ROOT SPACE</a> / <span style="color:#E9E9E3">BITCOIN-PUPPETS</span>',
    '<a href="/" style="color:rgba(233,233,227,.4)" style-hover="color:#E9E9E3">ROOT SPACE</a> / <span style="color:#E9E9E3">BITCOIN PUPPETS</span>',
    'root breadcrumb',
  );
  template = replaceRequired(
    template,
    '<div style="display:flex;gap:26px;align-items:center;flex-wrap:wrap">\n    <img src="30912c33-0812-42e6-af7b-53feb52d1654" alt="HoodPups branch artwork" style="width:104px;height:104px;object-fit:cover;border:1px solid rgba(233,233,227,.2);flex:none">',
    '<div class="ux-root-header" style="display:flex;gap:26px;align-items:center;flex-wrap:wrap">\n    <img class="ux-root-art" src="30912c33-0812-42e6-af7b-53feb52d1654" alt="HoodPups branch artwork" style="width:104px;height:104px;object-fit:cover;border:1px solid rgba(233,233,227,.2);flex:none">',
    'root header artwork',
  );
  template = replaceRequired(
    template,
    '<h1 style="margin:0;font-size:clamp(30px,3.2vw,44px);font-weight:600;letter-spacing:-.02em;line-height:1"><span style="color:#DE8C4F">Bitcoin Puppets</span> <span style="color:rgba(233,233,227,.4)">→</span> <span style="color:#C8F135">HoodPups</span></h1>',
    '<h1 class="ux-root-title" style="margin:0;font-size:clamp(30px,3.2vw,44px);font-weight:600;letter-spacing:-.02em;line-height:1"><span style="color:#C8F135">HoodPups</span> <span class="ux-root-arrow" style="color:rgba(233,233,227,.4)">←</span> <span style="color:#DE8C4F">Bitcoin Puppets</span></h1>',
    'root relationship title',
  );
  template = replaceRequired(
    template,
    '>COMMUNITY APPROVED</span>\n        <span style="font-family:\'Silkscreen\'',
    '>PUPPET HOLDERS APPROVED</span>\n        <span style="font-family:\'Silkscreen\'',
    'root approval badge',
  );
  template = replaceRequired(
    template,
    '      </div>\n      <div style="display:flex;gap:22px;flex-wrap:wrap;font-family:\'Silkscreen\'',
    '      </div>\n      <p class="ux-root-explainer">A matching HoodPup slot opens only when that Bitcoin Puppet holder signs. The original stays on Bitcoin; only approval crosses chains.</p>\n      <div style="display:flex;gap:22px;flex-wrap:wrap;font-family:\'Silkscreen\'',
    'root explainer insertion',
  );

  return template
    .replaceAll('<span>MINT: <span style="color:#E9E9E3">', '<span>DEMO MINT: <span style="color:#E9E9E3">')
    .replaceAll('EVERY CELL IS ONE OF 10,001 IDS — SAME POSITION, BOTH SIDES', 'SAME ID ON BOTH SIDES · ONLY APPROVED IDS CROSS')
    .replaceAll('THEY NEVER MOVE. ONLY SIGNATURES LEAVE.', 'ORIGINALS STAY ON BITCOIN.')
    .replaceAll('SIGNATURE<br>BYTES ONLY →', 'HOLDER<br>APPROVES →')
    .replaceAll('A SLOT EXISTS ONLY IF ITS OG SAYS SO', 'A MATCHING SLOT OPENS ONLY WITH HOLDER APPROVAL')
    .replaceAll('>OG — SILENT</span>', '>NOT YET APPROVED</span>')
    .replaceAll('>VOTED</span>', '>VOTED IN ROOT POLL</span>')
    .replaceAll('>CONSIDERING OFFER</span>', '>REVIEWING OFFER</span>')
    .replaceAll('>CONSENT SIGNED</span>', '>HOLDER APPROVED</span>')
    .replaceAll('>SLOT APPROVED</span>', '>MINT SLOT OPEN</span>')
    .replaceAll('>PURCHASED BY RH BUYER</span>', '>CLAIMED BY BUYER</span>')
    .replaceAll('>CLAIMED BY OG</span>', '>CLAIMED BY HOLDER</span>')
    .replaceAll('>ABSENT FOREVER</span>', '>CLOSED WITHOUT APPROVAL</span>')
    .replaceAll('>IDS VOTED</div>', '>PUPPETS IN ROOT VOTE</div>')
    .replaceAll('>CONSENTS SIGNED</div>', '>HOLDER APPROVALS</div>')
    .replaceAll('>CLAIMED BY OG</div>', '>CLAIMED BY HOLDERS</div>')
    .replaceAll('>PURCHASED BY RH</div>', '>CLAIMED BY BUYERS</div>')
    .replaceAll('<input type="range" min="1" max="46" step="0.1" value="{{ dayVal }}" sc-camel-on-change="{{ scrub }}"', '<input type="range" aria-label="Simulation day" min="1" max="46" step="0.1" value="{{ dayVal }}" sc-camel-on-change="{{ scrub }}"')
    .replaceAll('<canvas ref="{{ mapRef }}" style="width:100%;display:block;margin:0 0 14px;image-rendering:pixelated"></canvas>', '<canvas ref="{{ mapRef }}" role="img" aria-label="One-to-one lifecycle map of Bitcoin Puppets and matching HoodPup approval slots" style="width:100%;display:block;margin:0 0 14px;image-rendering:pixelated"></canvas>');
}

function transformMobilePreview(template) {
  return template
    .replaceAll('ROOT PROTOCOL · CONSENT LAYER', 'OG HOLDER APPROVAL LAYER')
    .replaceAll("Founders don't choose the supply. The community <em style=\"color:#C8F135\">reveals</em> it.", '<span style="color:#C8F135">Derivatives</span> are approved by <span style="color:#DE8C4F">OG holders.</span>')
    .replaceAll('Original communities approve their derivatives instead of merely being copied by them.', 'Each derivative opens only when the matching original holder approves it.')
    .replaceAll('YOUR PUPPET NEVER LEAVES BITCOIN.', 'NO BRIDGE · THE OG STAYS HOME.')
    .replaceAll('ROOT SPACES / BITCOIN-PUPPETS', 'ROOT SPACE / BITCOIN PUPPETS')
    .replaceAll('<span style="color:#DE8C4F">Puppets</span> <span style="color:rgba(233,233,227,.4)">→</span> <span style="color:#C8F135">HoodPups</span>', '<span style="color:#C8F135">HoodPups</span> <span style="color:rgba(233,233,227,.4)">←</span> <span style="color:#DE8C4F">Bitcoin Puppets</span>')
    .replaceAll('>COMMUNITY APPROVED</span>', '>PUPPET HOLDER APPROVED</span>')
    .replaceAll('ENTER THE PUPPETS ROOT SPACE →', 'EXPLORE THE APPROVAL MAP →')
    .replaceAll('<canvas ref="{{ mapA }}" style="width:100%;display:block;image-rendering:pixelated"></canvas>', '<canvas ref="{{ mapA }}" role="img" aria-label="Mobile approval map preview" style="width:100%;display:block;image-rendering:pixelated"></canvas>')
    .replaceAll('<canvas ref="{{ mapB }}" style="width:100%;display:block;image-rendering:pixelated"></canvas>', '<canvas ref="{{ mapB }}" role="img" aria-label="Mobile Root Space map preview" style="width:100%;display:block;image-rendering:pixelated"></canvas>');
}

function replaceRequired(value, from, to, label) {
  if (!value.includes(from)) fail(`UX transform marker missing: ${label}`);
  return value.replace(from, to);
}

function fail(message) {
  throw new Error(message);
}
