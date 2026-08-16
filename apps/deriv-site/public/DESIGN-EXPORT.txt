DERIV.WTF — standalone site export
==================================

Each .html file in this folder is fully self-contained (runtime, styles, fonts config,
images inlined). No build step, no server-side anything — static hosting is enough.

DEPLOY
1. Upload every file in this folder to the web root (keep the exact filenames —
   pages cross-link by them, spaces included and URL-encoded automatically).
2. Point the domain's index at "Landing.dc.html" (or rewrite / -> /Landing.dc.html).
3. Done. Fonts (Archivo, Silkscreen) load from Google Fonts at runtime; everything
   else works offline.

PAGES
- Landing.dc.html         — front page (hat rain, live dual-territory map, risk modal)
- Root Space.dc.html      — Bitcoin Puppets Root Space, full lifecycle simulator
- Mint Tracker.dc.html    — buyer wizard + live settlement tracker
- Holder Console.dc.html  — holder consent wizard (BIP-322, cold-wallet first)
- Protocol.dc.html        — transparency console
- Mobile.dc.html          — mobile mockups (iPhone frames)

NOTES FOR THE PORT
- All numbers are the worked HoodPups demo scenario (10,001 / 1,487 / 1,204).
- localStorage keys used: rootfun_risk_ack_v1, rootfun_space_sim, rootfun_tracker_sim.
- Mandated copy (trust statements, banned-phrase rules) lives in the repo:
  zentoshi69/root-protocol — apps/web/src/copy.ts. Keep those strings verbatim.
- Split shown everywhere: 50 OG holder / 20 Root Treasury / 20 builder / 10 protocol.
