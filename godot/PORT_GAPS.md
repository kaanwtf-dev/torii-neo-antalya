# Godot port: gap audit

Audited 2026-11-04 against **ALPHA 7.2 · POLYGON GIRL** (`torii-neo-antalya-ALPHA-7.2.html`). Six area mappers (combat, progression, story, Turkish, UI, world/sound) each listed what 7.2 does and what Godot does. An adversarial verifier per area then re-checked every claim against the code, and a completeness critic looked for whatever all six missed.

**Counts:** 222 verified gaps kept · 5 critic gaps (not separately verified) · 1 claim refuted · 109 features already covered in Godot.

**Spot-checked by hand afterwards (2026-11-05):** CRT-01 (no save after kill level-ups), CMB-01 (0 HP), PLY-01 (arrow keys strafe), UI-01 (raw `[b]` tags: 36 in missions.json, toasts are plain Labels) and WLD-V01 (`main.gd _solidify` gives every city mesh trimesh collision) all hold in the code. CMB-01 is worse than listed: `take_hit` just clamps HP at 0, and `lessons.gd:55` refuses to start a lesson at 0 HP, so she stays stuck at 0. Full gap rows with evidence: `godot/port_gaps.json`.


## 0. Progress

**Batch 2+ "Game game" (all systems) — built + wired 2026-11-07, not committed, no window playtest yet.** Ten systems in parallel,
then one integrator (main.gd wiring, API fixes, clean parse, `--autoplay` runs). Kaan's goal: port all of 7.2 AND add PS1-era depth.
- **Combat & movement** (player.gd, combat.gd, lockon.gd, torii_pose.gd): light 3-hit chains + heavy (RIGHT mouse, hold to charge),
  slam, dash, dodge roll with i-frames (Left Ctrl), block + parry (hold Z), lock-on (Tab), stamina, coyote jump + buffer, ledge climb,
  fainting/respawn → PLY-01..06, CMB-01/02/03/08, CAM-01..04, BIK-01..04/06, CRT-04, PRG-19 (faint part), UI-12.
- **Monsters** (enemy.gd, shot.gd, spawner.gd, mob_models.gd, ally.gd, bandit.gd): 8 archetypes with tells, wind-ups, stagger,
  roaming + night packs, minibosses, elites, boss phases/enrage, stinky Cruze, Bandit bites, Josh squad → ENM-01..13, BND-01..03,
  ALY-01, HAZ-01, CMB-V01, STY-12, STY-37, UI-23.
- **Weapons** (arsenal.gd, weapon_wheel.gd, projectile.gd): guns + one ammo pool, heavy volley, durability/breaking, hold-Q wheel,
  weapon/ammo drops, bassD in melee too → WPN-01..08, CMB-06, UI-34, PRG-28.
- **Skills** (skills.gd): 10 skills on R / 1..0, buffs/debuffs, cooldown rewards, boss battle quiz, mana from right answers →
  SKL-01..03, BND-02, BUF-01/02, CMB-07, TRK-03, TRK-20, STY-11.
- **Progression** (items.gd, stats.gd, levelup.gd, inventory_ui.gd): 50 nazars, food + H, gear + rarities, chests + keeper duels,
  kill coins/XP labels, perks, milestones, tip cards, I/J bag → PRG-01..08/11..16/20/22/23/30, UI-15/25/26/27, CRT-01, CMB-05.
- **HUD** (hud.gd, minimap.gd, hotbar.gd): bars (HP/mana/stamina/XP), stats block + clock, minimap, compass, objective marker, boss bar,
  lock reticle, buff chips, weapon panel → HUD-01/02, UI-16/17/18/20/29/33, DN-04, TRK-18 (status lines).
- **Sound + juice** (audio.gd, fx.gd): every sound synthesised, music stems day/night/combat + intro theme, TTS, M/V keys; sparks,
  slashes, shockwaves, hit-stop, flashes, labels → SND-01..05, UI-10, UI-38, PFX-01, FX-04, FX-05 (no drunk blur), HUD-03/04, UI-22,
  UI-36, TRK-14.
- **Side stuff** (shops.gd, quests.gd, tutors.gd, tavla.gd, tavla_ui.gd, hotspots.gd, lessons.gd, quiz_ui.gd, npc.gd): Five Sips +
  Kuyumcu, 5 quest chains, 11 grammar tutors + Old Soul, 7 tavla tables, Kaan's door/contracts/airport, zone words → PRG-17/18/21,
  STY-17..28, STY-30, STY-35/36, TRK-01/02/04..11/15/16/17/21/22, WLD-01/05/06/07, CRT-03.
- **Story + menus** (missions.gd, cutscene.gd, menus.gd, tips.gd): calls as cutscenes, boss intros, Hellspace scenes, opening + credits,
  gods with 7.2's rules, deliver/photo polish, title (CONTINUE / NEW GAME with a Downloads safety copy), pause/options, guide, patch
  notes, sunglasses (G), fullscreen (X), E prompt line → STY-01..09/13..16/31, UI-02/04/08/09/11/13/14/19/21/28/32, UI-V01, PRG-10,
  ENM-09, CMB-V02.
- **World** (sky.gd, world_life.gd, interactables.gd, intro.gd): day/night sky (DAYK), sun/moon/stars/clouds, lamp pools + halos by
  the hour, PS1 dither + NIGHT GRADE pass, cars/birds/blimp/plane, Josh, fountains, simit carts, DJ booth, VHS intro → DN-01..03,
  SKY-01..04, FX-01..03, WLD-03, STY-29, STY-32, STY-33, UI-03, UI-05 (GRAFİK in Menus), UI-06.
- **Still open:** BIK-05 (bike gear parts, level-15 underglow), PLY-07 (braid swing — no braid bones), CMB-04 (kill streaks: only
  `Stats.streak_tier` exists, nobody sets it), PRG-09 (visible gear), PRG-24 (outfit per level), UI-07 (UI scale slider), FX-06
  (ambient scenery animation), WLD-08 (auto quality governor / decor thinning), TRK-19 (INT sources, partial), CRT-02 (the Mac .app
  export itself). Nobody emits `quiz_answer` / `quest_done` yet (quiz_ui and quests play their own sounds, so it's fine).
- **Integrator notes:** see AI_HANDOFF.md log 2026-11-07 for the API fixes. Checks: clean script load of every file, a normal boot to
  the title, `--autoplay` on a scratch copy of the dev save.

**Batch 1 "Safety net + controls back" — done 2026-11-05** (Kaan: macOS desktop build, she drags her 7.2 save file in).
- **Save in:** first launch with no save shows 💾 BRING YOUR SAVE (drag the file 7.2 makes with SAVE & LOAD → SAVE TO A FILE onto
  the window, LOAD FROM A FILE, or a transfer code); 💾 SAVE & LOAD panel (bottom right) saves to Downloads, loads, drag-drop any
  time, transfer code. Import goes through `SaveBridge.import_text` (7.2's applySaveText formats), the replaced save is also filed
  in Downloads as `…-before-loading.json`, writes are frozen until the game restarts on the import. → CRT-02 (import side; the Mac
  .app export itself still needs Godot's export templates), UI-24, PRG-25.
- **Never worse:** level-ups and weapon breaks save at once, closing the window saves (CRT-01); `SaveBridge.migrate` = 7.2's applySave
  repairs incl. the pre-7.0 conversion before `lvlv:2`, xp clamp, need from the curve, weapon filter + durability, unit from `next`
  (PRG-26); resumed hunt gates take their type from the gate table (STY-V01); the missed list is stored in 7.2's own HTML format and
  keys compare without markup, so both games clear each other's entries (TRK-10's save part; the replay itself is batch 12).
- **Overlays:** `Overlay` gate: monsters and shots freeze and nothing hurts her during quizzes, calls, choices and the save screens;
  mission clocks and hunt gates pause; calls wait for a free screen like 7.2's whenFree (CMB-02, UI-30).
- **Text:** toasts are a stack of 3 rich-text boxes styled like 7.2 (red for warnings), the call box, banner and objective render
  [b]/[i] (UI-01, PRG-V01, TRK-13, UI-31).
- **Controls exactly like 7.2:** arrows turn, A/D strafe, 7.2 walk speeds (7.3 / 4.3 / 6.2, sprint ×1.62/×1.34, dance ×.25) (PLY-01);
  7.2's camera (7.4 m behind, over the right shoulder, eased; 9.4 m on the bike, mouse looks around freely, re-centres after 1.3 s)
  (CAM-01); calls page with E / Enter / Space, ESC skips (UI-37); choices take 1-9, E or Enter closes, answers shuffled, the reply
  comes in the dialogue box, +20 XP (STY-15, UI-V02); lesson text pages one line at a time with E / Enter / Space, Enter checks word
  order, QUİZİ GEÇ on revision, ⏭ SKIP THIS LESSON button (under the HP bar — 7.2's spot is covered by the quiz panel) (TRK-12, UI-35).
- **Proof:** `tests/godot_save.js` (real 7.2 ⇄ Godot round trip, pre-7.0 conversion identical to 7.2's, transfer codes, one mission
  played in Godot and loaded back into 7.2); `--godkey` (E at a god shrine keeps the coin toss open). A 3-lens review found a
  god-shrine soft-lock (E opened and closed the coin toss on one press), an import race, a quit-save gap, a stale transfer code and
  K over a live call — all fixed before commit.
- **Still open from batch 1's list:** none, except the desktop build itself (export templates ~1 GB, ask Kaan first).
- **Noticed in screenshots:** the bike camera sits inside buildings when the bike is parked against one (same as 7.2, which has no
  camera collision) — check in a playtest.

Area ids: CMB/ENM/WPN/SKL/BND/PLY/CAM/BIK/BUF/HUD/PFX/ALY/HAZ/CTL = combat & movement · PRG = progression, gear, money · STY = story, missions, NPCs · TRK = Turkish course, tavla, Old Soul · UI = menus & HUD · SND/DN/SKY/FX/WLD = sound, sky, world · CRT = critic. Where two areas found the same thing, both ids share one row. Impact = how much Torii notices it. Effort: S = hours, M = about a session, L = more than a session.

---

## 1. TL;DR

- **The skeleton is in, most of the game around it isn't.** Godot has the city, Torii's sheet model, Bandit, the bike, all 20 missions with hunt gates, the 16-unit course and a save bridge that keeps `torii_save` intact. Almost everything that happens *between* missions is still missing: perks, gear, food, nazars, skills, shops, coins, NPC tutors, side quests, Old Soul, tavla, cutscenes, sound and the day/night sky.
- **What Torii would hit in the first five minutes:** she can't see her level, XP or lira. Kaan's very first call shows raw `[b]`/`[i]` tags. The game is silent. Monsters keep hitting her during quizzes and calls, and at 0 HP nothing happens. Her perks, gear, food and nazar beads do nothing. Ranged weapons she won can't hit anything.
- **Biggest risk is her save, not the code.** A desktop build can't see the browser save her progress lives in (CRT-02). Level-ups earned by killing monsters aren't written until the next mission or lesson event (CRT-01). A pre-7.0 save would lose its migration for good (PRG-26). Batch 1 fixes all of this first.
- **Existing controls changed, against Kaan's rule:** arrow keys strafe instead of turning, the mouse steers the bike, Kaan's calls page only with ENTER, choices are mouse-only, and lesson text ignores E. Hold-Q wheel → tap-Q cycling was a stated simplification, and Kaan still has to confirm it.
- **Plan:** 12 batches (section 6). Batches 1-5 make the switch safe and give her back everything she earned. Batches 6-12 bring back sound, menus, story scenes, the sky, city life, tutors, quests, Old Soul and tavla.

---

## 2. Save safety

The save key stays `torii_save` (+ `_bak`, `_bak2`). SaveBridge keeps the whole dict and only edits fields it owns, so nothing from 7.2 gets deleted. The risks are fields Godot **writes differently or not at all**, plus a lot of earned stuff Godot **carries but never reads**.

### 2a. Written differently or not written (can lose or bend data)

| Field(s) | What Godot does | Risk | Fix |
|---|---|---|---|
| whole save | Desktop build reads `user://torii_save.json`. Her real save is in browser localStorage (file:// copy and the Pages site each have their own). No export preset exists yet. | **Highest.** A desktop build opens at level 1. | CRT-02 + UI-24/PRG-25 (import file / transfer code, through SaveBridge so backups roll) |
| lvl, xp, need, mh, mm, ms, pp, kills, dur, weap, wi, gate | Not written after a kill level-up, weapon break or faint. The only writes come from mission/lesson/gate events. | Closing the game loses kill-earned levels, perk cards and weapon wear. | CRT-01 |
| lvlv | `_defaults` stamps `lvlv:2` on the first write without running 7.2's pre-7.0 conversion | Permanent: owed perk cards and stat growth can never be granted later | PRG-26 (run the conversion before stamping, or refuse to stamp) |
| unit | Missing unit defaults to 1 | Puts her back on unit-1 lessons | PRG-26 (derive from `next` like 7.2) |
| gate | Godot adds `type`. A 7.2 save has no `type`, so Godot resumes it as "any monsters". | The hunt she was on quietly changes | STY-V01 (read type from `gates[next-1]`) |
| missed | Godot writes BBCode text + extra keys. 7.2 entries hold HTML, and their keys never match. | Old misses never clear and would show raw `<b>` if replayed. Mixed formats in one list. | TRK-10 (convert HTML → BBCode and rebuild keys on load) |
| weap | An empty list stays empty and she kicks forever. 7.2 restores the katana on load. | Soft-lock on fun between missions | CRT-05 |
| bounty | A contract she already paid for (up to 2,760₺) is never spawned, shown or refunded | Lira she spent is gone | PRG-21 (at least refund on load; ask Kaan) |
| dur | Writes 9999 where 7.2 had Infinity (JSON null) | Harmless | keep |
| pp | +1 per level, never spent | Not corruption. She'll have a pile of cards waiting once PRG-02 lands. | PRG-02 |
| msd | Never written | None: 7.2's checkMilestones catches up once ported | PRG-06 |
| numbers | Godot JSON round-trip turns ints into floats | Not re-checked in this audit | Re-run the "real 7.2 loads the Godot save" proof every batch |

### 2b. Carried untouched but never read (earned stuff she can't see or use)

`perks` · `gear` / `eq` / `gu` · `bag` · `nz` · `q` / `qa` · `mastered` · `npc` (tutor states, `tavla_<id>`, `tavlaWeapon`, `fivesips`, `met_*`) · `bassD` · `resp` · `shades` · `cigs` · `tips` · `gods`.
Written but never shown or used: `lira` (never shown or spent), `ammo` (+2 from lessons, never consumed), `mm` / `ms` (no mana or stamina exist), `kills`, `done` (Godot uses `next>=20`). `int` is read for the XP multiplier only.

### 2c. Rules for whoever ports these

1. **Never recompute `mh` / `mm` / `ms` / `int` from `perks`, `gear`, `nz` or `msd`.** 7.2 already baked those bonuses in (applyFlat, takePerk, nzMilestone, checkMilestones). Equip/unequip adds or subtracts deltas only.
2. Settings are **not** in `torii_save`. 7.2 uses `torii_opts`, `torii_gfx` and `torii_patch`. On desktop use something like `user://settings.cfg`, and never mix them into the save.
3. `eq` values are gear uids, not indexes. Drop `eq` entries whose uid isn't in `gear`, and keep `gu` = max of all uids.
4. 7.2 never saved some things: the active tutor task (`S.side`), Josh's device recharge, skill-cooldown rewards, chests. Persisting any of them is new behaviour, so ask Kaan.
5. Every batch ends with the migrate proof: a real 7.2 save goes through Godot and comes back loadable by real 7.2 with nothing lost.

---

## 3. Backlog

### P0: blocks switching Torii from 7.2 to Godot

| ID | Feature | Status | What's missing | Impact | Effort | 7.2 ref | Godot ref |
|---|---|---|---|---|---|---|---|
| CRT-02 (critic) | Her real 7.2 progress in the build she plays | missing | There's no export preset. A desktop build can't see her browser save, and nothing imports a 7.2 save file or transfer code. Kaan has to decide desktop or web first. | high | M | loadGame 14445, downloadSave/applySaveText 14556-14606 | save_bridge.gd:16-31 |
| UI-24, PRG-25 | Save & Load panel (save to file, load file / drag-drop / transfer code, persist request) | missing | No way to export, import or restore a save. Import must check that `lvl` is a number and must go through SaveBridge. | high | M | #saveBox 401-415, downloadSave 14563, applySaveText 14574 | none |
| CRT-01 (critic) | Save right after level-up, weapon break, faint, perk pick | missing | Kill-earned levels, perk cards, kills and weapon wear live only in memory until the next mission/lesson write | high | S | levelUpShow 9042, die 8969/8977, useDurability 7538 | lessons.gd:41-46, enemy.gd:61-69, player.gd:116-128 |
| PRG-26 | applySave migrations and validation | partial | Stamps `lvlv:2` without the pre-7.0 conversion (permanent loss), doesn't derive `unit` from `next`, no xp clamp or weapon filtering | medium | S | applySave 14462-14530 | save_bridge.gd:51-54, lessons.gd:38 |
| STY-V01 (verifier) | Resuming a typed hunt gate from a 7.2 save | changed | A 7.2 gate has no `type`, so Godot resumes it as "any monsters" | low | S | saveGame 14421, applySave 14516-14518 | missions.gd:332-343 |
| CMB-02, UI-30 | Overlay/pause manager; no damage while a quiz, call, choice or menu is up | missing | Monsters keep moving, shooting and hitting during lessons, calls and choices. She's frozen (quiz) or free to walk (call). HP can reach 0 mid-quiz, and then lessons refuse to start. No IMMUNE during level-up, no KALKAN shield. Every panel needs this first. | high | M | damagePlayer 8940-8947, loop 17885, anyOverlay 9340, UIKEYS 9183 | enemy.gd:87-108, shot.gd:24-28, quiz_ui.gd:7, hud.gd:71 |
| CMB-01 (+ faint part of PRG-19, UI-36) | Fainting at 0 HP | missing | Nothing happens at 0 HP. 7.2: YOU FAINTED screen, -10% lira, -30% of this level's XP, save, respawn at `resp` with 70% HP after 2.4 s, clears nearby non-boss mobs. AI_HANDOFF's "back at Kaan's" is stale. | high | M | die 8957-8980 | player.gd:97-100 |
| PRG-27, STY-34, WLD-04 | Checkpoints + respawn point | missing | No 5 cyan pillars (heal, save, set respawn, teach ev/plaj/deniz/market). `resp` is never read, so she always loads at the city spawn. | medium | S | checkpoints 6246, updateCheckpoints 10848-10860, applySave 14510 | main.gd:29, 219 |
| WLD-V01 (verifier) | Everything in city.glb is solid | changed | Trimesh collision on every chunk very likely puts an invisible ~4.8 m wall around every street lamp (haze cones), plus water, pools, blimp and birds. Use the 264 collider boxes + ground, or skip translucent/unlit materials. Confirm in game. | medium | S | resolveCol 8819-8845, lamp 6083-6096 | main.gd:213, 221-223 |
| PLY-04, WLD-02 | World bounds; river only crossable on the bridge | missing | She can walk on the river and the sea, and past the horizon plane she falls forever. Needs the ZB clamp + river block. | medium | S | ZB 9781, riverBlocks 9783-9786 | main.gd:221-223 |
| UI-01, PRG-V01 (verifier) | Raw `[b]`/`[i]` tags in toasts and Kaan's calls | changed | Shows from the very first call (23 call lines, 26 reward messages, the gate call). Toast and call lines must become RichTextLabel. | high | S | toast 5233, banner 5238 | hud.gd:24-34, missions.gd:299, 330 |
| PLY-01 | Walking speeds; arrow keys turn | changed | Arrows strafe instead of turning (a control change). She's ~37% slower and backs up at full speed. No dance/drunk/hex/buff multipliers. | high | S | updatePlayer 10266-10291 | player.gd:6, 156-164; main.gd:192 |
| CAM-01 | Camera framing and bike camera | changed | The mouse steers the bike (control change). Camera is rigid at 3.4 m, where 7.2 is smoothed at 7.4 m (9.4 on the bike). No auto-recentre. | high | S | updateCam 17827-17876 | player.gd:57-59, 137-139, 202 |
| UI-37 | Call keys: E/Enter/Space next, ESC skips | changed | Only ENTER pages, and ESC can't skip | medium | S | cutKey 13411-13414 | missions.gd:66, hud.gd:36 |
| STY-15, UI-V02 (verifier) | Dialogue box + choices (1-4 keys, E closes) | changed | Mouse-only buttons that can't be closed. She's frozen while monsters hit. No option shuffle, trader reply shows as a toast, +25 XP instead of 20. No general NPC dialogue box (NPCs, quests, Josh and gods all need one). | medium | S | dlgChoices 13341, STEP.choice 12467-12487 | hud.gd:56-72, missions.gd:233 |
| TRK-12, UI-35 | Lesson controls + skip buttons | changed | Lesson text is one block and E doesn't advance it (the guide says E). Enter doesn't check word order. No SKIP THIS LESSON / QUİZİ GEÇ buttons, and revision can't be skipped. | medium | S | keydown 5135-5166, #skipBtn 390, quizSkipAll 11738 | quiz_ui.gd:69-73, 168-177; lessons.gd:66 |
| PRG-01, UI-17, TRK-18, WPN-06 | Stats HUD: level, XP, lira, INT, words, ammo, food, weapon, unit/lesson, outfit | missing | She can't see anything she has earned | high | M | updateHUD 10888-10902, applyWeapon 7660 | hud.gd:16-37 |
| HUD-01, UI-16 | HP number, XP, mana and stamina bars | partial | HP bar only, no number. Mana and stamina bars arrive with SKL-01 / PLY-02. | high | S | updateHUD 10879-10887 | hud.gd:17-22 |
| PRG-03, PLY-06 | stat() layer: level damage, perks, gear, crit, armour, nazar +8% | missing | Her perks and equipped gear do nothing. At level 18 she hits ~34% softer than in 7.2. No crit, armour, İkinci Nefes, Şifalı Vuruş, Öfke or post-30 bonus. | high | L | stat 9090-9122, takePerk 9123, damagePlayer 8946-8954 | player.gd:83-112, 97-100 |
| PRG-02, UI-26 | Perk cards: pick 1 of 3, SONRA keeps them | missing | `pp` grows every level and nothing spends it. 21 perks can't be picked. | high | M | PERKS 9076, openPerks/pickPerk 9140-9184 | save_bridge.gd:84 |
| PRG-06 | Every-5th-level milestones + post-30 prestige | missing | Bag size, rarity caps, neon bike at 15, skill 6/7 unlocks, +50 HP per 5 levels after 30. `msd` never written. | medium | S | MILESTONES 9304-9333 | none |
| PRG-07 | Gear data model: slots, rarity, rolls, equip/unequip/sell, 30-piece cap | missing | All her gear is inert (only the flat hp/mana/stam already baked into mh/mm/ms counts) | high | L | RAR 13879 … gainGear 14005, loadExtra 14408 | carried in save_bridge.gd:35-43 |
| PRG-08, UI-25 | Inventory (I, J) and shop panels | missing | Gear, food, cards, nazars, quests and stats sheet can't be seen | high | L | INVTABS 14227-14320, keys 5174-5180 | none |
| PRG-12 | Backpack of Turkish food + eating (H) | missing | Stored food is invisible. Godot has no healing item at all. | high | M | FOOD 14036-14093 | none |
| BUF-01, PRG-13 (+ buff list of UI-33) | Timed buffs + #buffs HUD | missing | Food, pickups, gods and nazar shield all need them. Matcha focus XP ×2 missing. | medium | S | BUFFS 9485-9505 | none |
| PRG-22 | 50 nazar beads + rewards | missing | Beads she found are invisible, none exist in the world, and the 30-bead +8% isn't applied | high | M | NZ_SPOTS 14116-14213 | none |
| CMB-05, PRG-16 | Lira coins from kills | missing | Kills pay nothing, so 7.2's main income loop is gone | high | M | killEnemy 9722-9736, dropCoins/updateCoins 10710-10745 | enemy.gd:65-69 |
| WPN-01 | Ranged weapons + nazar ammo | missing | Ranged weapons have reach 0, so equipping one (5 are mission rewards she owns) means she can't hit anything. No ammo cost, no dry fallback, no ammo HUD. | high | M | tryAttack 9419-9433, projs 9648-9661, dryFallback 7499-7507 | player.gd:83-113 |
| CMB-06 (+ kill-loot part of PRG-14) | Kill drops (ammo, food, cocktails, tavla boards) + kill words | missing | Nothing drops. Ranged weapons need the ammo drops. | medium | M | killEnemy 9737-9757 | none |
| STY-08, WPN-08, PRG-28 | Pena reward: bass +10 damage (`bassD`) | missing | Bass hits 42 instead of 52, and her saved bonus is ignored | medium | S | 11913, saveGame 14425, applySave 14509 | player.gd:83-88, missions.gd:281-299 |
| SKL-01 (+ skill bar of UI-33) | Skills 1-7 + R, mana, cooldowns, skill bar | missing | Keys 1-7/R do nothing. No mana, no level 10/25 locks. | high | M | SKILLS 13698-13783, keys 5181-5182 | none |
| SKL-02 | Skill effects (Dance Blast, Cocktail Splash, Bass Drop, Battle Cry, Nazar Kalkanı, Yıldız Yağmuru) | missing | All six effects, their toasts and their bursts | medium | L | 9383-9392, 13720-13766 | none |
| BND-02 | Bandit Strike (skill 2) | missing | Bandit sprints, bites for 60 and stuns 2 s. With no target, mana is refunded. | medium | S | banditStrike 13742, updateBandit 10585-10596 | bandit.gd:22-42 |
| ENM-13 | Enemy stun / slow / fear / knockback | missing | Shared base for skills, Bandit Strike, bike ram, Josh's device, battle quiz and melee knockback | medium | S | spawnEnemy 8293-8297, updateEnemies 9946-10040 | none |
| STY-01 | Cutscene engine | missing | Letterbox, camera shots, subtitles, freeze + invulnerable, E/Enter/Space next, ESC skip, whenFree | high | L | playCut 13367-13451 | hud.gd:49 |
| STY-03 | Hellspace "MEANWHILE…" scenes | missing | Karen's office set, actors, HR monitor and 8 scenes: the story's through-line | medium | L | HELLSCENES 13621, buildHellSet 13530, playHell 13660 | missions.gd:301 |
| STY-05 | Ending: SHE MADE IT, finishGame, credits, Karen epilogue | partial | Godot shows one banner. The credits must name the sheet model's author instead of Vinrax. | high | M | 13017-13020, finishGame 13868, playEnding 13679 | missions.gd:316-319 |

### P1: clearly noticeable while playing

| ID | Feature | Status | What's missing | Impact | Effort | 7.2 ref | Godot ref |
|---|---|---|---|---|---|---|---|
| TRK-13, UI-31 | Toast stack (3 at once) + red "bad" toasts | changed | One toast slot, so new word cards wipe each other out right away | medium | S | toast 5231-5237 | hud.gd:52 |
| STY-02, UI-V01 (verifier) | Mission phone-call cutscene | partial | No GELEN ARAMA card, close-ups, phone pose, Torii's "Alo?" + Turkish reply, title card or fanfare. She's hittable during the call. | high | M | playCall 13474-13504, REPLIES 13458 | missions.gd:60-87 |
| SND-01, CMB-08 | Sound effects (45 synth sfx + every hook) | missing | Godot is completely silent. Each 7.2 sound is a live WebAudio recipe, so it has to be rebuilt or pre-rendered to .wav. | high | L | audioBoot/tone/nz/fx 4873-4943 | none |
| SND-02 | In-game music loop (+ DJ layer) | missing | No music at all | high | M | musicStart/schedBar 4944-4981 | none |
| SND-04, ENM-11 | Monster talk: Turkish lines, bubbles, formant babble + TTS | missing | Monsters never speak. This is a big part of the Turkish flavour in fights. | medium | M | MOBTALK/VOICE/mobSpeak 8846-8937 | none |
| SND-05, UI-38, UI-10 | M key, music/SFX sliders, monster-voice toggle + self-test (torii_opts) | missing | No audio settings. Her old values sit in `torii_opts` on the web. | medium | S | applyOpts/loadOpts 18079-18103, setVoice 18112 | none |
| TRK-14 | TTS behaviour | changed | No fallback voice. Caches "no voice" forever (web goes mute). Half volume, different pitch/rate, no warm-up. | medium | S | TTS 4983-5122 | tts.gd:7-14 |
| HUD-03, UI-22 | Floating world labels + speech bubbles (Label3D pool) | missing | No damage numbers, +XP, +₺, IMMUNE or bubbles. Most feedback rows need this. | medium | S | label 5243-5256, updateLabels 10866 | none |
| PFX-01, FX-04 | Particles: puffs, confetti, fireworks | missing | No dust, sparks, death bursts, confetti or smoke | medium | S | puff/updateParts 8797-8818, fireworkBurst 9001 | none |
| CAM-03, HUD-04, UI-36, FX-05 | Screen feedback: shake, hurt/heal vignette, drunk blur, fades | missing | Hits are easy to miss. Travel cuts instantly. | medium | M | shakeT 17873, vig 5240, #deadO 14614 | player.gd:97-100 |
| CMB-03 | Hit feedback on monsters | partial | No red flash, knockback, damage numbers or sparks (only a scale pop) | high | S | hitEnemy 9662-9679 | enemy.gd:61-63, 102 |
| CMB-04 | Kill streaks | missing | Tier banners, XP/lira multiplier, HUD counter | medium | S | STREAK 9686-9721 | none |
| ENM-02, UI-23 | Monster levels, Lv tags, level colours | missing | A level-18 Torii fights level-1 monsters, so late missions are trivial and XP isn't scaled | high | M | mobLevel 9346-9381, spawnEnemy 8287-8291 | enemy.gd:39-44 |
| ENM-03 | Elite (EPIC) stats, crown, kill banner | changed | Godot elites have half the toughness, normal damage and half the XP, with no crown or EPIC DOWN banner | medium | S | spawnEnemy 8280-8294, killEnemy 9758 | enemy.gd:42-55 |
| PRG-04 | XP gain formula and +XP feedback | partial | No Çalışkan/gear XP, focus ×2, streak, mob-level scaling or elite ×4 | medium | S | gainXP 8987-8996 | save_bridge.gd:75-86 |
| PRG-05, UI-27, CAM-04 | Level-up show (+ drunk camera roll) | partial | Banner only. No shockwave, 5.2 s immunity, fireworks, 360° orbit, stats toast, 'seviye' word or milestone card. | medium | M | levelUpShow 9010-9045, updateCam 17833-17874 | lessons.gd:41-45 |
| PLY-02 | Stamina: sprint cost, winded, bar | missing | Sprint is free and unlimited | medium | S | updatePlayer 10292-10310 | player.gd:158 |
| WPN-02 | Josh's Device (shock) | missing | Zero-width arc, so it practically never hits | low | S | tryAttack 9396-9418 | player.gd:105-113 |
| WPN-04 | Durability rules | changed | Wears per enemy hit, not per swing. Skips weapons missing from `dur`. No 10-uses warning, broken banner or best-DPS switch. | medium | S | useDurability 7531-7544 | player.gd:113-127 |
| WPN-05 | Auto-equip best DPS on a new weapon | missing | Keeps her on the old weapon | medium | S | giveWeapon 7508-7522 | missions.gd:288-296 |
| WPN-03, UI-34 | Hold-Q weapon wheel + mouse-wheel cycling | changed | Tap-Q only, and it doesn't skip dry weapons. With 27 weapons she cycles forever. (Kaan to confirm, section 5.) | medium | M | wheel 7695-7869, keys 5157-5192 | player.gd:90-95 |
| WPN-07 | Random weapon drops in the city | missing | Every 26-46 s, rarity-weighted | medium | M | weaponDirector 7454-7476 | none |
| CRT-05 (critic) | Katana back when every weapon broke | changed | Godot leaves her kicking until a mission reward | low | S | applySave 14485-14487 | player.gd:76-81 |
| CMB-07, TRK-03 | Battle quiz at 66% / 33% boss HP | missing | Right = boss stunned, crit next, +10 HP. Wrong = boss heals, she takes 10. | medium | S | battleQuiz 11849-11858, hitEnemy 9673 | enemy.gd:61-69 |
| TRK-20 | Mana rewards from Turkish | missing | The 4th lesson reward, +10 mana per right answer, perfect = full mana, skip-test dance | low | S | lessonReward 11683, finishQ 11813 | lessons.gd:103-107 |
| TRK-11 | Quiz summary + perfect bonus on every quiz | partial | Only after lessons, and then overwritten at once. Revision and skip test lose the +40 XP. | medium | S | nextQ 11752-11760 | lessons.gd:96-109 |
| TRK-10 | Missed-question review | partial | Godot records misses but never replays them. Old 7.2 HTML entries never clear (see save safety). | medium | S | rememberMiss 11708, tvQuizSet 17598, soulFinal 16431 | lessons.gd:157-168 |
| TRK-16 | Other teach() word sources (~60 of 87 words) | missing | Bike, cars, pickups, food, DJ, kills, gods, props… none call teach. Port each with its owning feature. | medium | M | many (collect 10791-10845 etc.) | missions.gd:83/229/297/309 |
| PRG-11 | Gear drops from monsters/elites/bosses | missing | No new gear at all. Bosses always dropped a piece in 7.2. | medium | M | lootDrop 14025-14034 | enemy.gd:61-69 |
| PRG-14 | World pickups scattered round the city | missing | Cocktails, tavla sets, cigarettes, glasses (+INT), simits, shells, ammo, weapons, nazar shields | medium | L | scatterPickups 6470-6501, collect 10798-10846 | missions.gd:132-139 |
| PRG-15 | Mission pickup effects | partial | Items only count. No word taught, no XP, heal or buff. | medium | S | collect 10816-10838 | missions.gd:168-174 |
| PRG-17, STY-20 | Five Sips café shop | missing | Nowhere to spend lira (opens after the owner's simit task) | high | M | CAFE 14330-14388, npcTalk 16005 | none |
| PRG-18 | Kuyumcu Zeynep, gear jeweller | missing | Gear shop + NPC + sign; the late-game lira sink | medium | M | VENDORS 14391, openShopUI('jewel') | none |
| PRG-10, UI-11 | Sunglasses (G) | missing | G does nothing and saved `shades` is ignored. The sheet model needs a glasses mesh. | medium | M | setShades 18036-18043 | none |
| ENM-04 | Ambient monster spawning (spawnDirector) | partial | Outside gates and kill steps the city is empty. No level-gated pool, zone pools, elites, minibosses or despawn. | medium | M | spawnDirector 9905-9940 | missions.gd:335-353 |
| ENM-01 | Models for Lory, Vergi, Kapıcı, Öküz, Kara Çarşı Ağası | missing | They would fall back to imp.glb once their spawns are ported | medium | L | makeLory 8170, makeAga 8264 | enemy.gd:45-46 |
| ENM-05 | Free-roam minibosses + rewards | missing | Lory, Vergi, Kapıcı from level 6: banner, lira, weapon drop | medium | S | spawnDirector 9926-9931, killEnemy 9759-9765 | none |
| ENM-06 | Monster chase basics | changed | Monsters walk through buildings, sit at y=0, aggro 30 m for all, wrong reach and cooldown | medium | M | updateEnemies 9955-10118 | enemy.gd:93-101 |
| ENM-09 (+ summon part of STY-09, CMB-V02) | CEO Karen summons thots/zombies | missing | Every 8 s ("MEETING, NOW!"), every 3 s after her overtime phase. Affects missions 12 and 16. | medium | S | updateEnemies 10058-10062, 12045 | enemy.gd:44 |
| STY-09 | Boss extras: Cruze prop, phase tip, DEFEATED banner | partial | Mission 6 may show two Cruzes. No phases tip card or "Boss down!" banner. | medium | S | advanceStep 12980-12985, TIPS.phases 12507, 9761 | missions.gd:113-118 |
| BIK-01 | Bike crash and tumble | missing | Godot only slows down. No wobble, flying off, slide, get-up, damage or 'düşmek'. | medium | L | bikeCrash 10344-10377, 10129-10176 | player.gd:207 |
| STY-06, UI-20 | Mission marker + nav arrow over her head | partial | Godot has only a beam, hidden on kill/boss/travel steps. No arrow toward far targets. | medium | S | updateMission 13024-13060 | missions.gd:44-48, 98-104 |
| UI-02 | Title screen: NEW GAME / CONTINUE + controls card | missing | Boots straight into the city. No safe erase-with-confirm. | high | M | #tMenu 479-489, 18504-18513 | main.gd:14-56 |
| UI-03, SND-03 | Intro (VHS gate, Bir Kaan yapımı, sunset, logo, cast cards) + theme | missing | The whole opening sequence and its synthwave track. The VHS gate also unlocks audio on the web. | high | L | INTRO 18215-18500 | none |
| UI-04 | Pause / options menu (P) | missing | Can't pause. No sliders, graphics, glow/grade, voices, guide or backup buttons. | high | M | #optCard 449-462, openOpts 18101 | player.gd:135 |
| UI-13 | WHAT'S NEW patch notes | missing | Breaks Kaan's every-release-has-notes rule. The 7.2 notes credit Vinrax. | medium | S | PATCHES 8620, showPatch 8762 | none |
| UI-14 | The Guide (REHBER) | missing | The in-game manual with her personal numbers | medium | M | GUIDE 9243-9301 | none |
| UI-15, PRG-30 | First-time tip cards | missing | No how-it-works cards. Saved `tips` not read. | medium | M | TIPS 9195-9239, TIPS2 12199 | none |
| UI-18 | Minimap | missing | Only the beam helps her find her way | medium | L | drawMinimap 14720-14811 | none |
| UI-21 | Context prompt line ("E: …") + one E dispatcher in 7.2's priority order | missing | No hint when something is usable. Today E only reaches the bike. | medium | M | setPrompt 10905, interact 10908-10950 | player.gd:143 |
| DN-01 | Day/night on her real clock (sky colours, fog, sun/moon light) | missing | Always night. Fog much thicker than 7.2 and never changes. | high | L | DAYK 5343-5355, updateDayNight 14646-14691 | main.gd:199-208 |
| DN-02 | Lit windows, neon and lamps follow the hour | changed | Frozen at the night state the city was exported in | medium | M | updateDayNight 14670-14689 | city.glb emissive mats, main.gd:225-242 |
| SKY-01 | Sky dome: gradient, stars, moon, sun, nebula ribbons | missing | Flat dark-blue colour | high | M | paintSky 5610-5677 | main.gd:202 |
| SKY-04 | Blimp, birds and plane move | changed | Baked frozen into city.glb (blimp hangs still, birds stuck mid-flap). Cut the baked copies first. | medium | S | updateSky 5721-5728, plane2 17889 | city.glb chunk_3_-2 etc. |
| FX-01 | Neon glow halos | missing | Lost in the export (no point primitives). Positions have to be re-exported. | medium | M | addGlow/bakeGlows 5945-5990 | none |
| WLD-01, STY-30 | Kaan's door to the balcony + talking to Kaan | missing | She can't reach Kaan at all (5.8 m deck, ~1.2 m jump). No balcony chat or contracts. | high | S | updateDoor 7927-7956, interact 10920 | npc.gd:112 |
| STY-17, WLD-05 | Airport gate travel + fly home | missing | After missions 10-12 she can never go back to Cameroon, Arizona or Livermore | medium | S | openTravel 14623, 10936-10943 | missions.gd:223 |
| STY-33 (+ carts/fountain part of PRG-19) | Fountains and simit carts | missing | Her only healing spots outside checkpoints | medium | S | buildProps/propInteract 16467-16541 | none |
| STY-16 (+ gods part of PRG-19) | Trickster gods: stake, rewards, greetings, free-play shrines | changed | Free best-of-3 only during the mission. No 40₺ stake, +120₺/+60 XP/lucky buff, greetings, or skip of a god already beaten. (Section 5.) | medium | M | godFlip 16048-16073, 10930-10934 | missions.gd:244-262 |
| STY-29 | Josh in Stockton (rants drain HP, slow, gives Josh's Device) | missing | Why mission 9 says "SURVIVE Josh". joshdev.glb exists but can't be earned. | medium | M | updateJosh 13306, joshTalk 13281 | none |
| STY-28 | NPC identity: names, genders, markers, props | changed | Base chosen by list index: DJ Cool Cat gets the male base, Kaptan Rıza/Hakan the female base, two moustached simit vendors become women. No names or markers. | medium | S | buildNPCs 15921, QMODELS 12581 | main.gd:126-136 |
| CRT-03 (critic) | Non-human NPC bodies: Dinozor Efendi, gold dog, Humanoid Bandit, Kuşum, Kaan with guitar | missing | No models and no plan. Needed by the tutors and Old Soul. | medium | M | makeDino 15818, makeGoldDog 15852, SOULNPC 16092-16138 | none |
| STY-19 | NPC grammar tutors with side tasks (11 NPCs) | missing | None talk. LESSONS not exported. Cocktail/bone pickups missing. | high | L | LESSONS 15766, npcTalk 15995 | none |
| STY-21 | Side-quest engine (5 givers, chains, J log, resume) | missing | Her `q`/`qa` wait safely in the save, unused | high | L | QGIVERS 12574 … questLoad 12937 | none |
| STY-22 | Quest step kinds: race, chase, escort, pickup-deliver, talk | missing | The main story never uses these, so none exist | medium | L | STEP.race 12249, chase 12322, escort 12346 | missions.gd:100-128 |
| STY-23 | Chain: PAMUK NEREDE? (Fatma Teyze) | missing | 3 parts. Needs a cat model. | medium | M | QUESTS kedi 12588-12618 | none |
| STY-24 | Chain: ÇARŞI HİKAYESİ (Halıcı Ahmet) | missing | 3 parts. Boss Ağa needs aga.glb. | medium | M | QUESTS carsi 12619-12663 | none |
| STY-25 | Chain: KAPTAN RIZA + Nermin Hanım | missing | 3 parts. Nermin doesn't exist. | medium | M | QUESTS kaptan 12665-12695 | none |
| STY-26 | Chain: MERT'İN DEFTERİ | missing | 3 parts. Needs sayfa pickups. | medium | M | QUESTS defter 12696-12720 | none |
| STY-27 | Chain: DAĞIN KRALI (Hızlı Hakan) | missing | 3 parts. Needs okuz.glb and the rival rider. | medium | M | QUESTS dag 12721-12756 | none |
| TRK-01 | Old Soul tutors (16 unit NPCs: review / practice) | missing | Regulars sit there anonymously. Needs names, tags and menus. | high | L | SOULNPC 16081, soulTalk 16399 | people.json seated entries |
| TRK-02 | Old Soul final test + unit mastery (+16/16 reward) | missing | Her saved mastery is invisible and she can't earn more | high | M | soulFinal 16431-16458 | none |
| TRK-04 | Tavla engine + AI opponents | missing | ~180 lines of pure logic. Port as a tested GDScript class. | high | L | 16553-16732, TVNPC 17674 | none |
| TRK-05 | Tavla table UI (board, dice, undo, clock, auto-roll) | missing | All of it | high | L | tvDraw 17110 … tvSetAuto 17704 | none |
| TRK-06 | Tavla betting, payouts, beaten opponents, tavlaw, gate kill | missing | Stake screen, match length, payouts, `npc.tavla_<id>` | high | M | tvOpenBet 17712, tvMatchOver 17559 | none |
| TRK-07 | Tavla pre-game Turkish quiz (re-rolls) | missing | The main way her missed words come back | high | M | tvQuizSet 17598, tvPreGameQuiz 17614 | none |
| TRK-08 | Tavla trash talk, Kaan's cheating, Turkish dice names | missing | ~50 glossed lines. Tables not exported. | medium | M | TRASH 16745, KAANTALK 16798, ZAR 16733 | none |
| TRK-09 | Tavla tables in the city + opponent intros | missing | 5 opponents stand as random humans, the imp is missing, Kaan is anonymous. Replace those people.json entries. | high | M | buildTavlaTables 17769, tavlaInteract 17800 | people.json, main.gd:136-145 |

### P2: polish

| ID | Feature | Status | What's missing | Impact | Effort | 7.2 ref | Godot ref |
|---|---|---|---|---|---|---|---|
| CAM-02, UI-12 | Look behind (C) + button | missing | Camera flip toggle | medium | S | setLook 18044, 17851 | none |
| HUD-02, UI-29 | Crosshair, click-to-look hint, mouse feel | missing | Hint, crosshair, sens .0022 vs .0028, pitch limits | medium | S | initMouseLook 5193-5229 | player.gd:129-139 |
| PLY-03 | Jump / landing feel | partial | Dust, landing thud, jump sound, no jumping while dancing | low | S | 10321-10336 | player.gd:165-168 |
| PLY-05 | Dancing as a real state | changed | Slow, no sprint/jump/attack, dances while moving | low | S | dance 9382, 10275-10326 | player.gd:172-175 |
| PLY-07 | Kick pose, aim lean, braid swing | missing | Leg kick, torso pitch, braids (sheet model may need braid bones) | low | M | poseTorii 10126, 10561-10567 | torii_pose.gd:71-79 |
| BIK-02 | Ramming monsters with the bike | missing | Damage, knock, stun, then her own crash roll | medium | S | bikeRam 10379-10398 | none |
| BIK-03 | Drift (Space while turning) + XP/lira | missing | Space always boosts in Godot | medium | M | 10181-10207 | player.gd:200-201 |
| BIK-04 | Boost costs stamina, pedalling refills it | missing | Free boost | low | S | 10217-10237 | player.gd:199-201 |
| BIK-05 | Hills, stat('bike'), neon bike at 15, bike parts | missing | Fixed numbers | low | M | 10209-10216, applyBikeLook2 7282-7307 | player.gd:195-198 |
| BIK-06 | Ride rules + prompt | partial | Prompt, can't dismount above 5 m/s, city only, first-mount toast, "can't fight on the bike" toast | low | S | interact 10908-10920 | player.gd:143-145, 178-187 |
| ENM-07 | Archers/witches kiting + shots | changed | Range, rate, wall stops, hex slow, toasts | medium | S | 10037-10044, 9447-9484 | enemy.gd:95-100, shot.gd |
| ENM-08 | Charge behaviour (öküz + boss charge phases) | changed | Wind-up label, range, cooldown, wall daze, gore shove | medium | S | 9988-10034 | enemy.gd:111-128 |
| ENM-10 (+ vergi part of PRG-19) | Vergi Memuru steals lira | missing | 8-25₺ per hit, teaches vergi | low | S | 10049-10052 | none |
| ENM-12 | Per-species gaits + stunned wobble | partial | One gait for all | low | M | 10064-10111 | enemy.gd:101-106 |
| BND-01 | Bandit barks + danger warnings | missing | "hav hav", "HAV HAV!! ⚠️" near monsters | medium | S | updateBandit 10630-10638 | bandit.gd |
| BND-03 | Bandit holds off the crowd in chest duels | missing | Needs chests | low | S | 10600-10616, 9956-9973 | none |
| BUF-02 | Debuffs: hex slow, drunk, Josh slow | missing | Speed and camera effects | low | S | 9480, 10122-10288 | none |
| STY-12, STY-37, CMB-V01 (verifier) | Kill counting for steps and hunt gates; gate details | changed | Only Godot's own spawns count. Epics come after regulars. Gate call doesn't wait for a free moment. No bounty line or every-3rd-gate save reminder. Kill XP not level-scaled. | low | S | 9763-9771, startGate 13788-13810 | missions.gd:141-152, 323-361 |
| CMB-V02 (verifier) | Boss phase-change feedback | partial | Rev sound, shake, red flash, burst | low | S | checkPhases 12497-12505 | enemy.gd:71-85 |
| CTL-02 | Other 7.2 keys with no binding | missing | Reference only: G V X M P I J H Z 1-6 E. Each one is tracked in its own row. | medium | S | keydown 5126-5183 | main.gd:191-197 |
| SKL-03, STY-11 | Skill-cooldown rewards | missing | Reward toasts promise shorter cooldowns. 7.2 never saved them, so re-derive from progress. | low | S | 12124, 12138, 15948 | none |
| PRG-09 | Visible gear on Torii and the bike | missing | Every slot changed her look. Needs BoneAttachment pieces on the sheet model. | medium | L | applyGearLook 7230-7287, applyBikeLook2 7290-7307 | player.gd:43-59 |
| PRG-20 | Guarded chests (12, keeper duel) | missing | Money/ammo/weapon/book chests, guaranteed gear. Not saved in 7.2, so no save risk. | medium | L | CHESTLOOT 8279-8375 | none |
| PRG-23, TRK-19 | INT stat: shown and raised | done | All 7.2 sources raise it (glasses, Kitap chest, ÖĞRENCİ perk, Mert's 3 quest parts, the dino) with 7.2's toasts; HUD stats shows 🧠 INT. Checked 2026-11-08. | low | S | glasses 10802, Kitap 8290, ogrenci 9128 | items.gd effect/_chest_won, levelup.gd take_perk, quests.gd/tutors.gd _reward, hud.gd _stats_text |
| STY-04 | Opening cutscene for a brand-new game (+ WELCOME BACK banner) | missing | Only seen on a new game; Torii is past it | medium | M | playOpening 13665, 18021-18031 | missions.gd:56 |
| STY-07, TRK-22 | Mission/unit-complete celebration | partial | Kaan's "Aferin bebeğim!" + TTS, confetti, sfx, "Son adım" toast, tutor-unlocked toast, weapon stats line | low | S | missionComplete 12997-13013, advanceUnit 13855 | missions.gd:292-311, 375-383 |
| STY-10, DN-03 | Dawn sky for mission 8 | missing | `start.dawn=true` already exported but ignored. Needs DN-01. | low | S | skyDawn 14632-14644, 11953 | missions.gd:82-83 |
| STY-13 | Deliver step details | partial | Start toast, instant late/squished messages, bday texts, words, tip, TESLİM banner | low | S | STEP.deliver 12375-12407 | missions.gd:117-122, 198-216 |
| STY-14, UI-28 | Photo hunt + T anywhere | partial | Camera-based check, live ghosts, 📸 icons, flash, shutter, word, tip, "Güzel fotoğraf!" | low | S | STEP.photo 12409-12466, takePhoto 12516 | missions.gd:73, 126-131, 264 |
| STY-18, WLD-06 | Travel presentation + zone state | partial | Fade, whoosh, Boarding toast, bike parked at the airport, Bandit beside her, bike locked abroad | low | S | travelTo 14611-14622 | missions.gd:223-231 |
| STY-31 | Kaan's balcony idle (smoking, phone in calls) | partial | Drag + smoke, phone pose; props lost with the base | low | S | updateKaan 10640-10653 | npc.gd:112 |
| STY-32 | DJ booth at Club Holo | missing | 12 s set, dance, confetti, hi-hats, +30 XP | low | S | interact 10944-10949 | none |
| STY-35, WLD-07, TRK-15 | Place words (beach, club, music store) + start-of-game words | missing | She likely knows them already from 7.2 | low | S | zoneTeach 10861-10866 | none |
| STY-36, TRK-17 | Walker greetings with English gloss | changed | Floating label with 5 glossed lines vs a toast with 4 unglossed ones | low | S | GREET 10670, updatePeds 10703-10708 | npc.gd:22, 76-80 |
| TRK-21 | Lesson/quiz sounds + red flash + banner subtitle | missing | Needs SND-01 | low | M | 11622, 11813-11821 | none |
| UI-05, WLD-08 | Graphics levels, auto quality governor, glow toggle | missing | Matters mostly for a web export. Also check whether the export dropped thinned decor. | low | M | GFX 5260, applyGfx 18047-18066, autoGfx 17973 | main.gd:5, player.gd:56 |
| UI-06, FX-03 | NIGHT GRADE: 15-bit dither, grade vignette, scanlines | missing | On by default in 7.2. Art-direction call (section 5). | medium | M | PS1P/drawFrame 5296-5335, optGrade 18108 | main.gd:5, 16-22 |
| UI-07 | UI scale slider (TV play) | partial | No user control. Default font instead of the Courier neon look. | medium | S | optFs 456, applyOpts 18087 | project.godot stretch |
| UI-08 | Fullscreen (X) + widescreen aspect | missing | 4:3 letterboxed. Set aspect to expand before building more UI. | medium | S | toggleFullscreen 18170 | project.godot |
| UI-09 | Toggle button bar + version label | missing | No `GAME_VER` at all (Kaan's version rule needs one) | low | S | #btns 391-399, #ver 400 | none |
| UI-19 | Mission box layout + side lines + FREE PLAY | partial | One cyan line instead of three styled lines. No quest, side-job or bounty lines. FREE PLAY only flashes. | medium | M | #missionBox 382 | missions.gd:210, hud.gd:23 |
| UI-32 | Load messages | missing | Welcome back, progress restored, backup-used warning | low | S | 14444, 14530, 18021 | save_bridge.gd:43 |
| DN-04 | HUD clock with Turkish part of day | missing | Teaches gece/şafak/sabah… | medium | S | partOfDay 14692-14701 | none |
| SKY-02 | Drifting clouds | missing | 12 planes | low | S | 5662-5671, 5715-5720 | none |
| SKY-03 | Shooting stars | missing | Every 7-22 s | low | S | shootStar 5694-5742 | none |
| FX-02 | Additive lamp pools and haze cones | partial | Draw as dark translucent shapes. Set BLEND_MODE_ADD at load. | low | S | 6080-6095 | Material_665/666 |
| FX-06 | Ambient scenery animation (club pulse, ferry, water, windmill, gods' coins) | changed | All frozen in the merged chunks | low | M | loop 17889-17964 | city.glb |
| WLD-03 | Traffic cars | missing | 6 neon cars, 8 damage, teach araba. Model to export. | medium | M | updateCars 10655-10669 | none |
| CRT-04 (critic) | Torii's blob shadow | missing | Bandit and the monsters have one, she doesn't | low | S | blobShadow 5992, 7196 | player.gd:43-59 |

### Cut candidates (Kaan decides)

| ID | Feature | Why it may not be worth porting | Effort if kept |
|---|---|---|---|
| ALY-01 | Josh's conspiracy squad (alien / drone bird allies) | Triggers on 1% of monster hits and needs three new models (Josh, alien, drone) for a rare gag | M |
| HAZ-01 | The roaming stinky Cruze | Small hazard, low impact. cruze.glb exists, so it's cheap if he likes it. | S |
| PRG-21 | Kaan's contracts / bounties | Godot's hunt gate already spawns the right monsters next to her, so the wall contracts were made to fix is gone. If cut, refund a saved paid `bounty` on load so she doesn't lose that lira (ask). | M |
| PRG-24 | New outfit every level (COSTUMES) | Kaan's sheet-model decision means she always wears the turnaround outfit. Keeping it = new outfit textures for the sheet model. | M |
| UI-05, WLD-08 | Graphics options + auto governor | Probably unneeded for a desktop build on Kaan's/Torii's Mac. Keep it if the web export happens. | M |
| UI-09 | Toggle button bar | Every button is also a key. Keep the version label regardless. | S |

---

## 4. Intentional changes already made (confirm or revert)

Some of these are Kaan's own decisions, and some just happened while porting. Each needs a yes or no from him. Rows marked "looks accidental" break his "don't change controls" rule.

| # | Change in Godot | 7.2 did | Who decided | Suggestion | Gap id |
|---|---|---|---|---|---|
| 1 | Tap Q = next weapon | Hold Q > 220 ms opens a weapon wheel. Mouse wheel cycles. | Claude ("simplified" in AI_HANDOFF) | **Kaan 2026-11-05: bring the wheel back (batch 4).** Revert (bring the wheel back) or confirm | WPN-03, UI-34 |
| 2 | Gods: free best-of-3 coin toss, only during the mission step | 40₺ stake per flip, +120₺ / +60 XP / lucky buff on a win, -40₺ and 12 dmg on a loss, shrines open any time, greetings | Claude ("simplified") | Revert | STY-16 |
| 3 | Every human NPC = one of two bases + outfit texture | person() with props (Josh's tinfoil hat, the Diskotek King's crown, DJ's cat ears, Nuri's spade, Kaan's cigarette/phone) | Kaan | Keep. Fix genders by name/role (STY-28). Decide whether Lory, Vergi, Kapıcı and Ağa use the bases. | STY-28, ENM-01 |
| 4 | Torii = the turnaround-sheet model | Vinrax PSX model + PS1 photo face, new outfit per level | Kaan | Keep. Decide on level outfits (PRG-24). Sunglasses and gear need new attachments. Update credits. Check her face. | PRG-24, PRG-09, PRG-10, STY-05 |
| 5 | One version = Godot; HTML frozen; web export "last and maybe never" | Browser game | Kaan | **Kaan 2026-11-05: macOS desktop build; she drags her 7.2 save file in.** Keep, but pick desktop or web before batch 1: a desktop build needs a save import | CRT-02 |
| 6 | 3D rendered at 1/3 resolution (240 lines), no dither/scanlines | 480 lines, dither + grade + scanlines on by default | Claude, following Kaan's PS1 screenshots | Kaan to look at it on her screen | FX-03, UI-06 |
| 7 | Hunt gate spawns its own monsters 3 at a time near her; only those count; epics after the regulars | Ambient spawns + Kaan's contracts; any matching kill counts; epics mixed in | Claude | Keep (it's simpler and it works). Mix the epics in. | STY-37, CMB-V01, PRG-21 |
| 8 | Kill steps respawn waves on the spot; only the step's own mobs count | Spawned once + extras; any matching kill counts | Claude | Keep | STY-12 |
| 9 | Weapons wear per enemy hit (misses free) | Once per swing, hit or miss | Claude ("wear per hit") | Revert to per swing | WPN-04 |
| 10 | Elites ×2 HP / ×2 XP, normal damage | ×3 HP, ×1.7 dmg, ×4 XP, crown | Claude | Revert | ENM-03 |
| 11 | Choice step gives +25 XP, options not shuffled | +20 XP, shuffled | Claude | Revert | STY-15 |
| 12 | Photo-hunt ghosts harmless; facing cone decides a hit | Real ghosts, camera-on-screen check | Claude | Revert | STY-14 |
| 13 | Fragile delivery = touching a wall above speed 6 | Bike wipe-out | Claude | Revert once BIK-01 exists | STY-13 |
| 14 | Arrow keys strafe; mouse steers the bike | Arrows turn; mouse looks around on the bike | Looks accidental | **Kaan 2026-11-05: revert.** Revert (control rule) | PLY-01, CAM-01 |
| 15 | Calls page with ENTER only; ESC doesn't skip | E / Enter / Space, ESC skips | Looks accidental | **Kaan 2026-11-05: revert.** Revert | UI-37 |
| 16 | Choices only clickable; lesson text ignores E | 1-6 keys, E closes; E pages lessons | Looks accidental | **Kaan 2026-11-05: revert.** Revert | UI-V02, TRK-12 |
| 17 | Only the nearest 12 lamp lights are on | No real lights | Claude (performance) | Keep | — |
| 18 | Unlimited durability saved as 9999 | Infinity (null) | Claude | Keep (harmless) | — |
| 19 | Godot writes `gate.type` into the save | Derived from GATES | Claude | Keep (harmless), but read old saves right | STY-V01 |

---

## 5. Port batches

One batch = one session. Settings are for Opus 5.5 with **Ultracode off**. Ask Kaan's OK before starting each one. Every batch ends with the 7.2 round-trip save proof and an update to AI_HANDOFF.md.

| # | Batch | Goal | Gap ids | Settings |
|---|---|---|---|---|
| 1 | **Safety net + controls back** | Her save comes in safely and never gets worse. Overlays are safe. Text renders. Controls match 7.2. Ask Kaan first: desktop or web? | CRT-02, UI-24/PRG-25, CRT-01, PRG-26, STY-V01, TRK-10 (convert old misses), CMB-02/UI-30, UI-01/PRG-V01, TRK-13/UI-31, PLY-01, CAM-01, UI-37, STY-15/UI-V02, TRK-12/UI-35 | Opus 5.5 · Medium · Ultracode off |
| 2 | **Core loop + feedback base** | She can faint and respawn, can't walk on water or into invisible lamp walls, and hits feel like hits. Builds the shared label/particle/shake tools. | CMB-01, PRG-27/STY-34/WLD-04, WLD-V01, PLY-04/WLD-02, CRT-05, HUD-03/UI-22, PFX-01/FX-04, CAM-03/HUD-04/UI-36/FX-05, CMB-03, CAM-02/UI-12, HUD-02/UI-29, PLY-03, PLY-05, PLY-07, CRT-04 | Opus 5.5 · High · Ultracode off |
| 3 | **The numbers she earned** | She sees her level, XP, lira and weapon. Her perks/gear/level power apply. Monsters match her level. Kills pay. | PRG-01/UI-17/TRK-18/WPN-06, HUD-01/UI-16, PRG-03/PLY-06, PRG-04, PRG-06, ENM-02/UI-23, ENM-03, CMB-05/PRG-16, CMB-04, STY-08/WPN-08/PRG-28, PRG-23/TRK-19, DN-04 | Opus 5.5 · Medium · Ultracode off |
| 4 | **Combat kit** | Skills, mana, stamina, ranged weapons with ammo, buffs, status effects and the battle quiz all work | ENM-13, WPN-01, CMB-06, BUF-01/PRG-13, BUF-02, SKL-01/UI-33, SKL-02, BND-02, PLY-02, BIK-04, TRK-20, CMB-07/TRK-03, WPN-02, WPN-04, WPN-05, WPN-03/UI-34 (if Kaan wants the wheel), SKL-03/STY-11 | Opus 5.5 · Medium · Ultracode off |
| 5 | **Gear, perks, inventory, food, nazars** | She can open her cards, wear/sell gear, eat, and see and keep collecting beads. The level-up show is back. | PRG-07, PRG-02/UI-26, PRG-08/UI-25, PRG-12, PRG-22, PRG-11, PRG-14, PRG-15, PRG-05/UI-27/CAM-04, WPN-07, PRG-10/UI-11, UI-15/PRG-30 (cards for these) | Opus 5.5 · Medium · Ultracode off (do PRG-09 visible gear later on High if Kaan wants it) |
| 6 | **Sound, music, voices** | The game isn't silent. Pre-render 7.2's synth recipes to .wav, music loop, monster voices, audio settings, TTS fallback. | SND-01/CMB-08, SND-02, SND-04/ENM-11, SND-05/UI-38/UI-10, TRK-14, TRK-21 | Opus 5.5 · Medium · Ultracode off |
| 7 | **Menus, help, prompts, E-interactions** | Title, pause, patch notes, guide, tips and prompts, plus one E dispatcher in 7.2's order. Kaan's door, airport, fountains/carts, DJ booth. | UI-02, UI-04, UI-13, UI-09, UI-14, UI-15/PRG-30, UI-21, UI-32, UI-08, UI-07, UI-19, TRK-11, STY-06/UI-20, WLD-01/STY-30, STY-17/WLD-05, STY-18/WLD-06, STY-33, STY-32 | Opus 5.5 · Medium · Ultracode off |
| 8 | **Story presentation** | Cutscene engine, then Kaan's calls as scenes, Hellspace, opening, ending + credits, and boss extras | STY-01, STY-02/UI-V01, STY-03, STY-04, STY-05, STY-07/TRK-22, STY-09, ENM-09, CMB-V02, STY-13, STY-14/UI-28, STY-31 | Opus 5.5 · High · Ultracode off |
| 9 | **Sky, day/night, look, intro** | Her real clock drives the sky, fog, windows and lamps. Stars, moon, glow halos, moving blimp and birds. PS1 grade. The VHS intro. | DN-01, DN-02, STY-10/DN-03, SKY-01, SKY-02, SKY-03, SKY-04, FX-01, FX-02, FX-06, UI-06/FX-03, UI-05/WLD-08, UI-03/SND-03 | Opus 5.5 · High · Ultracode off |
| 10 | **Monsters, city life, bike** | The city fights back between missions: spawn director, minibosses, the missing monster models, monsters that collide, Josh, cars, minimap, bike crash/drift/ram | ENM-04, ENM-05, ENM-01, ENM-06, ENM-07, ENM-08, ENM-10, ENM-12, BND-01, STY-12/STY-37/CMB-V01, STY-29, STY-35/WLD-07/TRK-15, STY-36/TRK-17, WLD-03, UI-18, BIK-01, BIK-02, BIK-03, BIK-05, BIK-06, PRG-20, BND-03 | Opus 5.5 · High · Ultracode off (likely 2 sessions) |
| 11 | **Tutors, shops, side quests** | The 11 grammar tutors talk, Five Sips and the jeweller open, the quest engine + 5 chains resume her saved `qa` | STY-28, CRT-03, STY-19, PRG-17/STY-20, PRG-18, STY-21, STY-22, STY-23, STY-24, STY-25, STY-26, STY-27, TRK-16 (sweep of remaining teach calls) | Opus 5.5 · Medium · Ultracode off (High for the creature/cat models; likely 2 sessions) |
| 12 | **Old Soul + tavla** | The 16 unit tutors with review/practice/final test and mastery. Tavla engine (tested first), table UI, bets, pre-game quiz, trash talk, real opponents at the tables. | TRK-01, TRK-02, TRK-04, TRK-05, TRK-06, TRK-07, TRK-08, TRK-09, TRK-10 (replay) | Opus 5.5 · Medium · Ultracode off |

Batch 1 goes first because nearly every later panel needs the overlay manager, rich text and toast stack, and because nothing else matters if her save doesn't come through. Cut candidates and leftover P2s get a sweep after batch 12, or ride along whenever a batch has time.

---

## 6. Blind spots and what needs a real playtest

**Not checked by this audit (from the critic):**
- **Emoji and Turkish letters.** 7.2 leans on browser colour emoji in nearly every toast, banner, prompt and quiz picture. Godot's default font falls back to system emoji on desktop but not in a web export (they'd become boxes). Check that ı/İ/ş/ğ render cleanly in the chosen font.
- **Render resolution.** Godot renders 3D at 320×240. 7.2 went up to 480 because diagonals "turn into a staircase". Whether it's too chunky on her screen takes a look.
- **Performance.** 218k tris, 350 materials, 144 trimesh chunks, up to 12 omni lights, GL Compatibility. Unknown on Torii's machine (especially web), and nothing like 7.2's autoGfx is there to rescue it.
- **Feel.** Walk/run speed, jump arc, bike handling, camera lag, mouse sensitivity (.0022 vs .0028) and swing timing can't be judged from code.
- **Her face.** Does the sheet model still show her real face (7.2's TORII_FACE)? The sheet texture wasn't inspected visually.
- **Web-only behaviour.** TTS voice availability, localStorage through JavaScriptBridge, pointer lock, Safari/WebGL2 (7.2 had Safari workarounds). There's no export yet, so none of it can be tested.
- **Baked dynamic objects.** Did city.glb freeze things that should react (the dirty Cruze prop, god shrines, fountains, simit carts, chests, nazar glows, the VIP-bench cocktail)? Neon signs export as blank slabs, which also hurts finding mission spots.
- **Save round-trip.** The float/int JSON round-trip proof in AI_HANDOFF wasn't re-run here (read-only audit).
- **Dev hooks.** `--autoplay`, `--lessontest`, `--shot` and `--fps` are gated on user args. Looks safe, but nobody checked whether a launcher or export could pass them.

**Also note:** the 5 critic gaps (CRT-01..05) were not separately verified. Several verifier-found gaps rest on "very likely" reasoning, especially WLD-V01 (invisible walls around lamps), so confirm them in the game before fixing. AI_HANDOFF has two stale claims: "down at 0 HP = back at Kaan's" (that lived in the deleted mission1.gd) and "weapons wear per hit" (7.2 is per swing).

**Playtest checklist (side by side with 7.2 where possible):**
1. Import her real save. Check level, lira, weapons, words, unit and mission all match.
2. Level up by killing monsters, quit without finishing a mission, reload. Is the level still there?
3. Walk along a sidewalk past lamps; walk to the river, the sea and the map edge.
4. Let monsters close in, then trigger a lesson and a call. Does she take damage?
5. Drop to 0 HP.
6. Read Kaan's first call: tags, keys (E, Space, ESC).
7. Equip a ranged weapon and attack.
8. Compare walking, sprinting, jumping, the bike and the camera with 7.2.
9. Check FPS in the busiest part of the city, on her machine if possible.
10. Look at emoji and Turkish letters in toasts, banners and quizzes.

---

## 7. Refuted claims (don't re-audit)

| ID | Feature | Why Godot is already fine |
|---|---|---|
| PRG-29 | Gods-won counter (`gods`) | 7.2's `S.godsWins` is only initialised, incremented, saved and loaded, never shown or used. The `god_<id>` flags Godot writes are what 7.2 actually checks. Nobody can notice the drift. |

The 109 features already covered (city, Torii's model and poses, Bandit follow, bike riding, all 20 missions and their step types, hunt gates, boss phases, the 16-unit course with quizzes, the walkers and NPC bodies, SaveBridge with rolling backups, and the rest) are not repeated here.
