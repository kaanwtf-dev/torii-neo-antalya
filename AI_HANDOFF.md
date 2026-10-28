# AI hand-off — Claude ⇄ ChatGPT

Kaan switches between Claude (Claude Code) and ChatGPT when one runs out of credits.
**Whoever works on this project: read this first, and update it before you stop.**
Project rules live in `CLAUDE.md` (they apply to both of us). Newest entry on top.

## Current state (2026-10-27)

- **HTML game is FROZEN at ALPHA 7.2** (`torii-neo-antalya-ALPHA-7.2.html`, live at
  https://kaanwtf-dev.github.io/torii-neo-antalya/). Fixes only.
- **Moving to Godot 4** (Godot 4.7.2 installed: `/Applications/Godot.app`, CLI `godot`).
  Plan agreed with Kaan: a vertical slice in `godot/` (not created yet) — city chunk, Torii on her new
  model, Bandit, bike, mission 1 (Avocado Run), saving that reads/writes the same `torii_save`
  localStorage key on the Pages site. Web export goes to `…/torii-neo-antalya/godot/` for testing.
  Art direction: Kaan's PS1 reference screenshots in `assets/screenshots/` ("Pasted 2026-10-26 at …").
- **In progress (Claude): Torii's new model** in Blender (Blender MCP), built to match
  `assets/screenshots/Retro Low-Poly Character Turnaround Sheet.png` exactly: black crop top,
  light wide-leg jeans, red/white/black jacket tied at the waist, white sneakers with black stripes,
  dark-to-honey ombre box braids. Low-poly (~1.5k tris) T-pose mesh, texture = the sheet's own
  views projected + baked; then rigged (arms-down rest) and exported as GLB for Godot.
  Pipeline script: `tools/torii_model/` (sheet model script coming).

## Things Kaan wants every time
- Before doing anything: recommend which model/effort settings to use, and ask him first.
- Casual tone ("bro"). Interview + plan summary before big changes. No unrequested features.
- Never put Torii's real photo (`assets/screenshots/torii face.jpg`) in git — it's ignored on purpose.

## Log
- 2026-10-27 Claude: **Turkish lessons ported.** `godot/assets/lessons/turkish.json` = 7.2's UNITS (16 units × 3 lessons),
  POOLS (288 extra questions), WORDS (259), GQ (26 grammar) exported from the running game, HTML → BBCode.
  `scripts/quiz_ui.gd` (`QuizUI`, static `open` pauses Torii): lesson page (ENTER), then 10-question sessions — mc
  (click / 1-4, options reshuffled), fill (accent-insensitive `norm()`), word order; dots, ✅/❌ + explanation.
  `scripts/lessons.gd` (`Lessons.me`): lessonTick every 5 kills (imp.gd calls it), starts when safe (no enemy within
  √150 m, not biking > 4), K = 3-question skip test, revision after a unit's 3 parts, +25 XP + random reward
  (HP/lira/beads), +15 XP per right answer, −6 HP + `missed` list per wrong one, perfect = +40 XP, teach() + vocab
  quiz every 4 new words (+ grammar from level 4). Walkers greeting her teach "merhaba"; mission 1 teaches
  "avokado". `scripts/tts.gd` speaks Turkish if the OS has a Turkish voice (project: audio/general/text_to_speech).
  Save fields like 7.2: lesson, lk, unit, ul, words, missed. Proof: `--lessontest --shots=DIR --savedir=DIR` on a
  real 7.2 save → 7.2 loads it as unit 1, ul 1, lesson 1, lvl 2, zero errors. Not yet: unit advancement (comes with
  missions 2-20), mana (no mana bar yet), Old Soul tutors/tavla replay of missed questions.
- 2026-10-27 Claude: **all NPCs replaced** (Kaan's rule: EVERY person = one of the two NPC bases + an outfit texture).
  `godot/assets/npc/people.json` = all 62 person() people from 7.2 (position, facing, scale, seated, walker loop
  cx/cz/t/sp, NPC name): 20 walkers, 28 standing, 13 seated, Kaan. City re-exported with every person hidden (the
  old export had ~22 baked-in people = 131k tris; city now 218k tris, 350 materials, 144 chunks, 25 MB).
  `scripts/npc.gd` (`Npc`): base + outfit texture (material_override), scaled to 7.2's ~2.06 m × its scale (kids .65);
  arms-down angle measured from the A-pose rig and fed to `ToriiPose` (now takes `down` as a parameter); ports of
  walkPerson / idlePerson / sitPerson / updatePeds (square loop, h 17) / updateKaan (waves within ~18 m); not animated
  beyond 90 m. `main.gd _people()`: unnamed people alternate male/female, named ones by name (TEYZE, DEFNE → female),
  outfit = (i·7+3) % 6; Kaan = male base in the sheet's base outfit on the balcony (-23, 5.85, -17.6). 120 FPS.
  Dev flags: `--at=x,z,yaw[,pitch]`, `--npcinfo`. Not yet: NPC dialogue/quests/greeting labels.
- 2026-10-27 Claude: **NPC bases built** from `assets/screenshots/PS1-Style NPC Base Model Reference Sheet.png`
  (Kaan: one male + one female base, outfits = texture swaps, no extra detail). `tools/npc_model/npc_base.py`
  (Blender/MCP): `build(kind)` reads each figure's outline row by row (front + side views; sensitive threshold
  because dark hair/black tops ≈ background) into low-poly rings: torso+head (10 sides; above the armpits the full
  span, below it everything between the arms), two legs (innermost run, so hanging hands aren't mistaken for legs),
  two A-pose arms following the arm outline; neck fixed at .86·height, shoulders .14 below; shoulder/sleeve verts
  partly weighted to the arm. Same joint names as Torii (body, head, arm/elb/leg/kn _m/_p), bones up, no roll,
  REST = A-POSE. `bake_base` projects front/back + side views (sides only on head and legs — on the torso they
  show the hanging arms) → 256px; `bake_variants` = each outfit's front picture wrapped round the body, head from
  the base. A colour-bled sheet was tried and made it worse (stripes) — reverted. Output in `godot/assets/npc/`:
  `npc_male.glb` (1,380 tris), `npc_female.glb` (1,632 tris), `male_base/0-5.png`, `female_base/0-5.png`.
  Previews: `tools/npc_model/compare_npc_bases.png`, `compare_npc_outfits.png`. Not in Godot yet (next step:
  spawn 7.2's peds + named NPCs on these bases; remove the baked tavla "statues" from the city).
- 2026-10-27 Claude: committed everything to `main` as 6f60d95 (not pushed). Kaan's decision: ONE version
  from now on = Godot; no HTML work; web export last and maybe never (desktop build may ship — then her
  browser save needs an import step).
- 2026-10-27 Claude: **mission 1 + her save in Godot.** `scripts/save_bridge.gd` (`SaveBridge`): reads `torii_save`
  → `_bak` → `_bak2` (web: browser localStorage via JavaScriptBridge = the SAME save as 7.2 on the same site;
  desktop: `user://torii_save.json`, override with `--savedir=`), keeps the WHOLE dict and only edits fields it
  owns, writes with 7.2's rolling backups, new saves carry `lvlv:2`. `gain_xp()` = port of 7.2 `gainXP`
  (lvlMul, INT; per level +12 mh, +3 mm, +2 ms, +1 pp; `need` = xpFor). `scripts/mission1.gd` = MISSIONS[0]
  'avo': Kaan's call (ENTER) → goto (60,-54) → 3 imps → 3 avocados → back to (-24,-12); writes `mid:'avo'` at
  start, then `next:1`, flail in `weap`+`dur`, kills, XP. Free roam if her save is already past mission 1.
  Combat: `player.gd` LMB (mouse captured) or F = 7.2 katana swing (26 dmg, .45 cd, 2.6 reach, 1.1 arc;
  `ToriiPose.swing()` = 7.2 attack pose), weapon on a BoneAttachment at `elb_p` (+ARMS_DOWN undo, −0.3 offset),
  HP + `take_hit`; down at 0 HP = back at Kaan's, full HP. `scripts/imp.gd` (7.2: 20 HP, 5.1 speed, 6 dmg).
  `scripts/hud.gd` (`Hud`): HP bar, objective, call box, banner, toast. `scripts/tint.gd` (`Tint.apply`).
  Assets exported from 7.2: imp, avocado, katana, avoflail. **Proof:** `--m1test --savedir=` auto-plays the
  mission on a copy of a real fresh 7.2 save; diff shows only dur/kills/next/weap/xp/lvl/need/mh/mm/ms/pp change,
  nothing lost, backups roll; that save loads in real 7.2 (jsdom) as level 2, 19/183 XP, both weapons, 321 lira,
  mission 2 next, zero errors. Not yet: kick/other weapons, imp death puffs, Turkish lesson bits, sounds.
- 2026-10-27 Claude: **Bandit + bike in Godot.** Both exported from the running 7.2 with three's GLTFExporter after
  naming their joints (bandit: head, tail, leg_0..3; bike: wheel_f, wheel_b, crank) and clearing userData
  → `godot/assets/bandit/bandit.glb`, `godot/assets/bike/bike.glb`. `scripts/bandit.gd` = port of
  `updateBandit` follow (behind-and-beside her, 10.5 m/s on foot / 30 on the bike, teleport if >24 m, raycast to
  the ground, tail wag, leg swing; no barking/fights yet). `player.gd`: E (new `interact` action, same key as 7.2)
  gets on/off the bike within 2.6 m; riding = 7.2 numbers (W +15/s, S brake 27 / reverse 9, drag 4.2+0.11v,
  clamp −5.5..27, steer tf = clamp(1.75−0.028v, .6, 1.75), Space boost +7.5 cd 1.15, lean −st·0.24); walls cut
  speed (no tumble yet). `ToriiPose.ride()` = the 7.2 onBike pose. `main.gd` `_tints()` turns on vertex-colour
  albedo for every 7.2 export (Bandit's black fur is a vertex tint). Dev flags: `--bike [--turn] [--side]`.
  Run Godot checks with a time limit (a script error leaves the window open forever):
  `perl -e 'alarm 60; exec @ARGV' godot --path godot -- --shot=...`.
- 2026-10-27 Claude: **signs + tiling + lamps fixed.** `merge_city.py` material key now includes every image
  in the node tree (unlit sign materials feed emission/background, not Base Color — that had merged all signs
  into one blank material) and the Mapping node values (the game's `map.repeat` → KHR_texture_transform; that
  had merged facades with different tiling: Midtown showed 6 window rows instead of 3). Now 364 materials,
  29.7 MB `city.glb`. The dark slab above Midtown's door is Kaan's balcony — it's dark in 7.2 too.
  Lamps: `main.gd` keeps all 192 OmniLights but only the nearest 12 within 40 m of Torii are on (re-checked
  every 0.5 s) → ~118-120 FPS on Kaan's Mac. Dev FPS probe: `godot --path godot -- --fps`.
  Still open: additive lamp cones/pools render as plain translucent (glTF has no additive), tavla NPCs baked
  in as statues, no sea/sky/day-night, web export not set up.
- 2026-10-27 Claude: **real city in Godot.** Exported the static 7.2 world from the running game in the
  browser with three r128 `GLTFExporter` (excluded player/bandit/kaan/bike/sky/marker + the arrays NPCS,
  peds, cars, pickups, nzObjs, parts, clouds, glowSprites, checkpoints + anything with userData.legs/baseY),
  stripped the exporter's huge `extras` (208 MB of userData JSON), then `tools/city/merge_city.py` in
  Blender: 2,702 → 193 materials, 4,812 meshes → 141 chunks of 60 m, 349k tris, 17 MB →
  `godot/assets/city/city.glb`. `city_data.json` = 264 collider boxes, 192 lamp posts, spawn (-24,0,-8).
  `main.gd` instances it, makes every chunk a trimesh collider, forces nearest filtering + vertex colours,
  adds a sodium OmniLight per lamp, spawns Torii at the 7.2 spawn. Known gaps: shop/neon signs come out
  as blank slabs (their text canvases/labels were skipped), some static NPCs (tavla players) are baked
  in, no water shader/sky, no day/night yet, 192 lights untested for web performance.
- 2026-10-27 Claude: **Godot slice step 1 runs** (`godot/`, Godot 4.7.2, GL Compatibility). `scenes/main.tscn`
  → `scripts/main.gd` builds everything in code: SubViewportContainer at 1/3 res + nearest = PS1 pixels,
  blue-hour night env/fog, test plaza (checker ground, 10 window blocks, 6 sodium lamps), input actions
  (WASD/arrows, Shift sprint, Space jump — same as 7.2), player. `scripts/player.gd` = CharacterBody3D,
  mouse-look third-person camera. `scripts/torii_pose.gd` (`ToriiPose`) = port of 7.2 `poseTorii` idle /
  walk / run / airborne onto the GLB's Skeleton3D (T-pose rest: arms get ARMS_DOWN=1.28 first, elbows are
  conjugated into the turned-down frame). Model: `godot/assets/torii/torii.glb` (= tools/torii_model/torii_sheet.glb).
  Dev screenshot: `godot --path godot -- --shot=/abs/out.png [--walk] [--front]`. Headless import/run clean.
  Not yet: Bandit, bike, mission 1, 7.1 city/PS1 textures, save bridge, web export (needs export templates).
- 2026-10-27 Claude: **Torii's sheet model is built** → `tools/torii_model/torii_sheet.glb` (1,500 tris,
  512px nearest-filtered texture packed in, 596 KB) + `torii_sheet_tex.png`; side-by-side in
  `tools/torii_model/compare_sheet_vs_model.png`. Pipeline (run in Blender via MCP, exec the file):
  `sheet_torii.py` build() → `bake_sheet.py` bake(obj, sheet_bleed.png) [projects the sheet's front/back/side
  views + the head close-ups, blended by normal, Cycles EMIT bake] → `sheet_torii.py` rig() → export GLB.
  `silhouette.py` renders ortho silhouettes at sheet scale (IoU vs sheet: front .81 / side .85 / back .81;
  the rest is the filled leg gap + floor shadow in the sheet mask).
  Rig: bones `body, head, arm_m/p, elb_m/p, leg_m/p, kn_m/p` (m = her right/-x, p = her left/+x), all
  pointing up with no roll ⇒ identity rest rotations; REST POSE IS T-POSE. Standing arms-down = rotate
  `arm_p` z −1.25…−1.32 and `arm_m` z +1.25…+1.32 in code. Game pose numbers (three.js Euler XYZ per
  joint, from `poseTorii`) apply directly on top. Known: side views baked a bit of arm/hand colour onto
  the torso/jacket sides (hidden when the arms are down).
  Next: Godot 4 vertical slice in `godot/` (import the GLB, port poseTorii to Skeleton3D, PS1 look).
- 2026-10-27 Claude: wrote `tools/torii_model/sheet_torii.py` (build(): T-pose low-poly Torii from the
  sheet measurements — torso, tied jacket + knot, wide jeans, sneakers, T-pose arms + thumbs, head, hair
  cap / back curtain / shoulder clumps; vertex groups = body, head, arm_*/elb_*, leg_*/kn_*). NOT run yet:
  Blender closed. Next: run build(), compare silhouette to the sheet, then project+bake the sheet
  (`sheet_bleed.png` = sheet with figure colours bled outward, made in the scratchpad — regenerate from
  the sheet if missing), rig with arms-down rest, export GLB.
- 2026-10-27 Claude: Godot installed; sheet measured (shoulders y≈1.71 at 2.2 height scale, arm
  thickness .116→.044, wide jeans legs splay to x≈±.2 at the ankle); `AI_HANDOFF.md` + `AGENTS.md` added.
- 2026-10-26 Claude: shipped ALPHA 7.2 (Torii as Vinrax's PSX model, rigged into the HTML game).
