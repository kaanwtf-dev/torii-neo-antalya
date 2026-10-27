# Test harness

Loads the game headlessly in jsdom with a mock THREE, so tests can call real
game functions (`terrainY`, `updatePlayer`, `applySave`, ...).

    cd tests && npm install jsdom
    for t in regress levels inventory story migrate intro guide door tumble savefile uiscale chest coast horizon; do node $t.js; done

harness.js resolves the NEWEST `torii-neo-antalya-ALPHA-x.y.html` in the game
folder automatically, so a new version needs no test changes.

- `harness.js` — boot(): {w, errs, E, T, clear} for the newest build;
  boot(dir) boots the newest build in another folder (used for `backups/`)
- `regress.js` — core + save round-trip + old-save compatibility
- `migrate.js` — a REAL save made by the previous version (from `backups/`)
  loaded through CONTINUE: nothing she earned may change. Rewritten for 7.1:
  a 7.0 save must come through field-for-field (only `mid` may fill in, when
  CONTINUE starts the queued mission). It exits 1 on any ✗ — check for ✗
  lines, not just the last line, when running the suite.
- `levels.js` — 7.0 levels, XP curve, perk cards, milestones, monster levels
- `inventory.js` — gear, backpack, nazar beads, shops
- `story.js` — cutscenes, Hellspace scenes, mission step types, side quests
- `intro.js` — the 80s intro: VHS gate, skipping, hand-off to the game
- `guide.js` — PAUSE → 📘 GUIDE
- `door.js`, `tumble.js`, `savefile.js`, `uiscale.js`, `chest.js`,
  `coast.js`, `horizon.js` — earlier features, still checked every release

Gotchas learned the hard way:
- The save keys are `lvl` / `weap` / `unit`, NOT `level` / `weapons`.
- `loadGame()` only READS the JSON; `applySave(d)` applies it.
- A 7.0 save has `lvlv:2`; anything without it is migrated once on load.
- THREE's `traverse` works in the mock, but geometry attributes do not —
  anything that deforms geometry guards on `typeof p.count === 'number'`.
- The mock defines globals `V3`, `Tex`, `Obj`, `Col`, `__mk` — the game must
  not declare top-level names that clash with them.

## Files

The game is ONE self-contained file: `torii-neo-antalya-ALPHA-<version>.html`.
The previous version lives in `backups/`. The save key is fixed (`torii_save`,
with `_bak` / `_bak2` rolling backups), never derived from the file name.
