# TORİİ: NEO ANTALYA

A browser game Kaan is making as a gift for his girlfriend Torii. It teaches Turkish from
*Teach Yourself Turkish* (16 units, 20 missions) inside a PS2-style neon city: Torii (braids),
her black dog Bandit, and Kaan on his balcony. Current version: **ALPHA 7.2 · POLYGON GIRL** (Torii as a real rigged model); her face is a 40x48 PS1-crunched photo (`TORII_FACE`).

Kaan likes a casual tone — "bro", swearing is fine.

## Hard rules (from Kaan — do not break)

- **One self-contained HTML file**: `torii-neo-antalya-ALPHA-<x.y>.html`. No launcher, no redirect,
  no side files. The only external script is three.js **r128** from cdnjs. Images, models, audio
  and extra libraries get inlined (base64 / pasted in). Torii opens the game by double-clicking it,
  and browsers won't let a `file://` page load separate model or texture files anyway.
- **Every release bumps the version**: the filename, `GAME_VER` (no apostrophes in it), the
  `#ver` div, and a new entry at the TOP of `PATCHES` written for Torii (what's new, in plain words).
- **Before shipping, move the previous version into `backups/`** so he can revert. Only the newest
  version stays in the folder root.
- **Never lose Torii's progress.** The save key is fixed: `torii_save` (+ `torii_save_bak`,
  `torii_save_bak2`). Never change it or derive it from the filename. New save fields need
  defaults, and old saves must load — `applySave()` migrates (7.0 saves carry `lvlv:2`).
  `MISSIONS` order is frozen (saves store the index): `avo` first, `kismet` last, 20 total.
- **Don't change existing controls without asking.** New keys only.
- **No unrequested features.** Ask when unsure. Interview him first on big updates and sum up the
  plan before building. In chat, show only the changed parts unless he asks for the full file.
- **Never ask Torii to run commands** — anything she has to do happens inside the game.
- **Textures must stay clean.** He rejected dark, noisy character textures before
  ("too black random stuff"). Canvas textures use mipmaps (`makeTex`, the `Atlas` class).

## Where things live (all in the one HTML file)

- `S` — the whole game state. `saveGame()` / `loadGame()` (reads JSON) / `applySave(d)` (applies it).
- Characters are built in code, not loaded: `buildGirl(P)` (Torii, and Lory her dark mirror),
  `person(top,skin,hair,o)` (every NPC and human monster; options: face, hairStyle, beard, stache,
  scarf, hat, hatStyle…), `dogHead()`, `kaanBody()`, the monster builders in `ENEMY`.
  Parts merge per joint with `MB` onto shared atlases: `PATL` (people, tinted by vertex colour),
  `MATL` (monsters/animals), `WATL` (world props). Shared materials carry `userData.shared` —
  clone them before tinting one character.
- Rig: `userData.legs[]` (`.kn` knee), `userData.arms[]` (`.el` elbow), `userData.head`. Animated by
  `walkPerson`, `idlePerson`, `sitPerson`, and `poseTorii` for Torii.
- Detail scales with the Graphics setting at build time via `DET()`.
- Levels/perks: `xpFor`, `gainXP`, `PERKS`, `MILESTONES`, `stat()`. Monster levels: `mobLevel`.
- Inventory: `RAR`, `SLOTS`, `GEARBASE`, `makeGear`, `FOOD`, `NZ_SPOTS` (50 nazar beads).
- Story: cutscenes `playCut` / `CUT`, mission phone calls `playCall`, Hellspace scenes `HELLSCENES`,
  mission step types `STEP.{race,chase,escort,deliver,photo,choice}`, side quests `QUESTS` / `QGIVERS`.
- Help for the player: first-time cards `TIPS` + `tip(id)`; the full guide `GUIDE` (PAUSE → 📘 GUIDE).
  Anything new and complicated gets a tip card and a guide section.
- Intro: `INTRO`, `introScene`, the synth track `IM` / `imBar`. Kaan's monster service: `HOTSPOTS`.
- PS1 look (7.1): `PS1TEX` (embedded AI textures, made by `assets/textures/ps1.py` from
  `assets/textures/raw/`), `ps1Img`/`ps1Ground`/`ps1Facade` repaint surfaces once pictures decode,
  `winEmit` + `BLDMATS` light windows by night, `drawFrame`/`PS1P` = dither pass (on with NIGHT GRADE).
  Night palette lives in `DAYK`; lamp light in `lamp()` (`_lampPool`, `_lampCone`).
- Torii's real model (7.2): `#torii-glb` (base64 glb) loaded by the inlined r128 `GLTFLoader`;
  `girlModel(R)` (called at the end of `buildGirl`) adds bones INTO the joint groups, so all the
  procedural poses drive it; `R.proc` = the code body it hides; on any failure the code body stays.
  Source + pipeline: `tools/torii_model/` (`retex_torii.py`, `torii.glb`). Skinned materials need
  `skinning=true` AND `needsUpdate=true` in r128. Credit model authors (patch notes + end credits).
- Blender MCP is set up for this folder (`.mcp.json`, add-on in `tools/blender-mcp/`). Blender must be
  open; tools only load in a session started after that.

## Testing

`tests/` boots the real game headlessly (jsdom + a mock THREE). Needs Node.js — if it's not
installed, ask Kaan before installing it.

    cd tests && npm install jsdom
    for t in regress levels inventory story migrate intro guide door tumble savefile uiscale chest coast horizon model; do node $t.js; done

- `migrate.js` loads a REAL save made by the version in `backups/` into the new one — it must pass
  before every release.
- The mock defines globals `V3`, `Tex`, `Obj`, `Col`, `__mk`: don't declare top-level names that clash.
- Check visuals in the real thing too: open the HTML in the Browser pane, press a key at the VHS
  "press any key" screen, then any key again to skip to the menu.

## Adding real 3D models

- Kaan drops source files in `assets/models/` and reference images in `assets/screenshots/`.
  They are sources only — the game never loads them from disk; whatever is used gets embedded.
- Prefer `.glb` with embedded textures. Embed as base64 in the HTML and load with three r128's
  `GLTFLoader` (inline `examples/js/loaders/GLTFLoader.js` from r128 — the non-module version).
- Keep the file sane: aim for a few MB per model, textures ≤ 1024px, PS2-ish poly counts.
- Rigged characters need their own animation path (`THREE.AnimationMixer`); every place that poses
  the procedural rig (walking, idle, riding the bike, phone calls, dancing, attacks, sitting)
  needs an equivalent clip or a fallback. Keep the procedural model as the fallback if a load fails.
- Scale and face models to match the current ones (+z forward, Torii's head top ≈ 2.2 units).

## Release checklist

1. All tests pass (`migrate.js` included). 2. Visual check in the Browser pane.
3. Bump the filename, `GAME_VER`, `#ver`, and add a `PATCHES` entry at the top.
4. Move the previous version to `backups/`. 5. Update `tests/README.md` if tests changed.
6. Commit + push `main`, then publish online: the public repo is `kaanwtf-dev/torii-neo-antalya`, and
   Torii plays at https://kaanwtf-dev.github.io/torii-neo-antalya/ (GitHub Pages from the `gh-pages`
   branch). On `gh-pages`, copy the new version in as `index.html` (plus the versioned file and `backups/`),
   commit, push. The gh token has no `workflow` scope, so no Actions — update the branch by hand.
   Online saves live in her browser for that site, separate from saves made by opening the file.
