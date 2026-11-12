# AI hand-off — Claude ⇄ ChatGPT

Kaan switches between Claude (Claude Code) and ChatGPT when one runs out of credits.
**Whoever works on this project: read this first, and update it before you stop.**
Project rules live in `CLAUDE.md` (they apply to both of us). Newest entry on top.

## Current state (2026-11-09)

- **ONE version = the Godot 4 project in `godot/`** (Godot 4.7.2, GL Compatibility; run: `godot --path godot`).
  The HTML game is FROZEN at ALPHA 7.2 (`torii-neo-antalya-ALPHA-7.2.html`, still Torii's live link at
  https://kaanwtf-dev.github.io/torii-neo-antalya/). No HTML work. Web export is the last, optional step.
- **Kaan's goal (2026-11-06): "a game game"** — 7.2 is the concept; Godot ports all of it AND adds PS1-era depth
  (Medievil / Tenchu / Spyro / Ape Escape): light/heavy combos, dodge roll, lock-on, block + parry, stamina, jump
  with coyote time, ledge climb, roaming monsters (harder at night, minibosses), loot, skills, sound for everything.
- **Godot version is now ALPHA 8.1 · SERİ** (`Menus.GAME_VER`, from `assets/story/godot.json` "ver"). 8.1 = eight
  parallel branches merged on `build/8.1`, smoke-tested in a window, then fast-forwarded onto main and pushed (2026-11-09):
  kill streaks, bike parts + underglow, braid swing + bare-hand heavy kick, visible gear, TEXT SIZE, ambient scenery, auto
  quality governor, INT check.
  Patch notes are now a list: godot.json `"patches"` (newest first; Menus shows the newest in full, older Godot notes dimmer,
  then 3 one-liners from 7.x). 8.0 (20cdbb2 + 6c5082f) is on main and pushed. Kaan's reports so far: quit crash (fixed 11-08),
  paid quiz hints (done 11-08).
- **Quitting goes through `main._quit()`** (`auto_accept_quit = false`): save, `Audio.shutdown()` (stops players + TTS,
  waits for the render thread / intro task / every babble task), unpause, wait, `_drop_statics()`, quit. Don't call
  `get_tree().quit()` from game code; send `NOTIFICATION_WM_CLOSE_REQUEST` instead. Test runs MUST pass
  `--savedir=<scratch dir>` or they write Kaan's real Godot save on quit.
- **How it's wired:** `scripts/main.gd` builds the world, Torii, Bandit, the bike, loads her save, then creates
  every system as a child Node with `static var me` (order matters, see the comments in `_ready`). 8.1 systems: `Streaks`
  (streaks.gd), `GearLook` (gear_look.gd, Bus `gear_eq` {slot, item} from items.gd), `BikeLook` (bike_look.gd), `Quality`
  (quality.gd), `Ambient` (ambient.gd, from `_build_world`); `UiScale` (ui_scale.gd) is a static helper, Bus `ui_scale` {k}. Systems talk
  over `scripts/bus.gd` (`Bus.on` / `Bus.emit_ev`, reset at the top of `_ready`). Every screen that pauses her
  goes through `Overlay`. One E dispatcher in main (`_interact`, 7.2's interact() order); the bike and the gods
  read E themselves first.
- **Keys:** all of 7.2's keys keep their meaning. NEW: RIGHT mouse = heavy attack (hold to charge; with a gun =
  volley), Left Ctrl = dodge roll, hold Z = block (just before a hit = parry), Tab = lock-on / next target,
  ledge climb is automatic, 0 / 8 / 9 = skills 10 / 8 / 9 (extensions of 1..N). Who reads which key: main.gd
  `_inputs()` comment.
- **Save:** still 7.2's `torii_save` via `SaveBridge` (keeps unknown keys). New Godot-only fields: `gPatch`,
  `gGfx`, `gGlow`, `gGrade`, `side`, `npc.allmastered`, `musicOn` (7.2 runtime var, now persisted); `musVol`,
  `sfxVol`, `voiceOn` moved from 7.2's `torii_opts` into `torii_save`. 8.1 adds `gFs` (text size, default 1.0), `gView`
  (view distance FAR/MID/NEAR) and `gManual` (she picked GRAFİK/VIEW herself: the governor stops). NEW GAME keeps all three.
- **Open gaps:** `godot/PORT_GAPS.md` §0 (batch 8.1 entry on top): only PRG-24 (outfit per level) and CRT-02 (the Mac .app
  export) are left, both wait for Kaan. Machine-readable rows: `godot/port_gaps.json`. Don't re-audit.
- **Mac app (CRT-02, 2026-11-09):** `bash tools/export_mac.sh` → `godot/build/TORİİ NEO ANTALYA.app` + `godot/build/TORII-NEO-ANTALYA-<ver>-mac.zip`
  (build/ is git-ignored). Preset `godot/export_presets.cfg` "macOS": universal (Intel + Apple Silicon), `*.json` included,
  icon `godot/icon.png` (a `--iconshot=PATH` render of her model, never her photo), boot splash = plain dark purple. The
  script renames the inner binary/.pck to `Torii` / `Torii.pck` and re-signs ad-hoc with Apple's codesign: Godot names them
  after the game, and the Turkish İ in those inner names breaks the signature check ("app is damaged"). Templates are in
  `~/Library/Application Support/Godot/export_templates/4.7.2.stable` (SHA-512 checked). `import_etc2_astc=true` is needed
  for arm64. Not notarized (no Apple developer account): first launch on her Mac = System Settings → Privacy & Security →
  Open Anyway (older macOS: right-click → Open). Her saves go to `~/Library/Application Support/Godot/app_userdata/TORİİ: NEO ANTALYA/`.
- **In-game updater (8.2, `scripts/updater.gd` + `scripts/boot.gd`):** after the 8.2 zip, Torii never installs a zip again
  unless the ENGINE or `project.godot` changes. Hosting = GitHub Releases of `kaanwtf-dev/torii-neo-antalya`: the app reads
  `releases/latest/download/version.json` once while the title shows; newer `ver` + same engine → UPDATE / LATER panel
  (Overlay "update"); UPDATE downloads `releases/download/v<ver>/<pck>` to `user://updates/<pck>.part`, checks size + sha256,
  writes `user://updates/current.json`, saves, and starts the app again (`Updater.relaunch`, spawned at the end of
  `main._quit()`). Different engine → one line "ask Kaan 💌". 404 / no internet / timeout → nothing.
  **How the pack gets used:** `run/main_scene` is now `scenes/boot.tscn` (`boot.gd`): BEFORE any game script loads it does
  `ProjectSettings.load_resource_pack(pck, true)` when current.json names a pack that is newer than the bundled game, same
  engine, right size and sha256, then `change_scene_to_file(main.tscn)`. (The first plan, a restart with `--main-pack`, is
  impossible: official release templates abort with "compiled without support for path overrides".) `boot.gd` must never
  name a game class, and the app's own copy of it always runs (changing it = new app). Anti-brick: `boot_try_<ver>` counts
  starts, `Updater._mark_ok` writes `boot_ok_<ver>` + clears the count at the title, after 5 s running, or on an orderly
  quit (`main._quit()` → `Updater.mark_ok_on_quit()`); 2 starts without it → update deleted → bundled game, + `bad_<ver>`
  (never offered again) only if that ver never had a `boot_ok_<ver>`. Damaged pack → deleted, offered again. Any drop of
  an update newer than the bundled game first copies the save to `torii_save_from_<ver>.json` (the older code is about to
  run on it), and `SaveBridge.migrate()` parks weapon ids it doesn't know in `weap_later` / `dur_later` instead of
  deleting them (they come back once a build knows them). The download runs WITHOUT threads (`use_threads=false`, 1 MB
  chunks a frame): threaded, a dead link froze the game when the 30 s watchdog / CANCEL / quit joined the HTTP thread.
  The pack the game is playing from is never deleted by an install; `boot.gd` deletes other packs before mounting. Log:
  `user://updates/updater.log`. Only the exported app updates (`OS.has_feature("template")`); dev runs need
  `--updateurl=http://127.0.0.1:PORT/`. With `--savedir=DIR` the update files live in `DIR/updates` (tests never touch the
  real folder). Dev flags: `--updateurl=`, `--updatepress`, `--updateshot=PATH` (also writes PATH_dl.png), `--updatequit=SEC`,
  `--totitle` (main: skip the VHS intro, stay on the title).
- **Publishing an update (Kaan confirms, it's public):** bump `"ver"` in `godot/assets/story/godot.json` (+ patch notes; the
  number must be higher than the last release), commit, then `bash tools/publish_update.sh [--notes "one line for Torii"]`
  → `godot/build/torii-<ver>.pck` + `godot/build/version.json` and the exact `gh release create v<ver> ... --latest` command
  (run it, or re-run the script with `--publish`). Notes default to godot.json `"update_note"`, else the newest patch title.
  An engine upgrade or a change to `project.godot` (window, rendering, autoloads), `scripts/boot.gd` or `scenes/boot.tscn`
  can't ship as a pack: `tools/export_mac.sh` and send her the zip. The script refuses those (`--force` skips): it compares
  with `tools/app_base.sha256` + `tools/app_base.engine`, which `export_mac.sh` writes — COMMIT them with the app build you
  send her (they don't exist yet: the 8.2 app build creates them; until then publish_update.sh refuses). Test before publishing: serve `godot/build/` with `python3 -m http.server 8765 --bind 127.0.0.1` and run
  the exported app with `-- --updateurl=http://127.0.0.1:8765/ --savedir=<scratch> --totitle`.
- **Not done yet:** PRG-24 (outfits per level: Kaan decides).
  Seen but not fixed: "NAZAR SHIELD 12s" shows twice (left HUD list + right buff chip, from before 8.1); the club neon
  pulse / ferry / windmill motion and the visor (G on) were never watched on screen; the bare-hand kick only happens when
  her weapon list is just ['kick'] (an empty list migrates back to the katana).
- **Fresh checkout / new class_name script:** run `godot --headless --path godot --import` once, or main.gd fails to parse
  ("Identifier X not declared") until Godot rebuilds its class cache (the editor does this on open).

## Things Kaan wants every time
- Before doing anything: recommend which model/effort settings to use, and ask him first.
- Casual tone ("bro"). Interview + plan summary before big changes. No unrequested features.
- Never put Torii's real photo (`assets/screenshots/torii face.jpg`) in git — it's ignored on purpose.

## Log
- 2026-11-11 Claude (wf82/updater): **in-game updater** (see Current state). Proven against the EXPORTED app with a 9.9 test
  pack on a local server: download + sha256 → restart → `GAME_VER ALPHA 9.9 · TEST`, same save (lvl 5, 18 words); the next
  plain start goes straight into 9.9 (world shot from the pack); same-size corruption / truncated pack / wrong-sha download /
  two killed starts / newer bundled app all fall back to the bundled game; engine mismatch = toast only; 404 + no server =
  silent; the real GitHub URL answers 404 today (no release yet) and HTTPRequest follows GitHub's asset redirect (tested on a
  public release). Nothing was published.
  Review fixes: no-thread download (a stalled server: watchdog fires at 30 s, quit mid-stall exits at once, 30 MB local
  download < 1 s), orderly quit = boot ok (3 windowed 2 s quits on the VHS intro stay at try 1), proven ver dropped
  without `bad_`, save copy on drop, `weap_later`, running pack kept, publish guard (tools/app_base.*).
- 2026-11-09 Claude (parent session): **Mac app built (CRT-02).** Kaan OK'd the export templates (1.28 GB, SHA-512 checked,
  installed for 4.7.2). Added `godot/export_presets.cfg`, `godot/icon.png` (+ `--iconshot=PATH` dev flag), ETC2/ASTC import,
  dark boot splash, `tools/export_mac.sh` (export → ASCII inner names → ad-hoc re-sign → verify → zip). Checked: signature
  valid after unzipping, the exported app boots headless with no errors and renders the same as the editor build.
- 2026-11-09 Claude (parent session): **8.1 checked and shipped to main.** After the merge: the checkpoint pillars fade when
  she or the camera is close (she spawns inside the HOME one, and the opening call is filmed there); quest-giver and tutor
  signs hide within 6 m of the camera (`Shops.sign3d(text, col, size, hide_near)`: opt-in, 6.0 only for quests.gd's !/⏳/
  name and tutors.gd's 💬/UNIT/🔒). A windowed smoke test passed every feature (screenshots `tools/shots/81_*.png`) and a
  merged-diff review found 4 low bugs, all fixed: a new streak tier shows as a toast when an epic/boss/level-up banner
  took the banner the same frame, `--fs=N` no longer writes the save, the plane and birds fade before the shorter VIEW
  far plane. `tests/godot_save.js` (real 7.2 save round trip) re-run on 8.1. Dev flags added today: `--near=x,z,r` /
  `--near=cam,0,r` (lists the 3D things around a spot), `--brawlshot=PATH`, `--hit --heavy`, `--fakefps=N`, `--fs=N`,
  `--fsdemo`, `--ambientinfo`, `--hour=H`, `--at=x,z`, `--clear`, `--close`. Workflow lesson: resuming a workflow after
  editing ANY early prompt re-runs everything after it, so after a usage-limit cut-off write a small continuation script
  that hard-codes the finished results instead.
- 2026-11-08 Claude (integrator): **ALPHA 8.1 · SERİ on `build/8.1`.** Merged wf/intel, quality, ambient, streaks, bike, pose,
  gearlook, uiscale (`--no-ff`, in that order). One textual conflict: `hud.gd banner()` (streaks added a `dur` argument,
  uiscale wrapped the text in `UiScale.bb`) → kept both. Integration edits: `torii_pose.gd braids()` now clamps at `braid_max`
  (gearlook sets .08 under the backpack), the streak chip scales with TEXT SIZE, the patch-notes reader takes a list. Each new
  `class_name` needs one `godot --headless --path godot --import` before a boot sees it. New dev flags: `--clear` (close the
  opening call before a shot), `--close` (pose close-ups), `--gearshots=DIR`, `--gearlow`, `--bikelook=a,b`, `--fs=1.75`,
  `--fsdemo=DIR`, `--fakefps=N` (governor test), `--ambientinfo`, `--ambient_t=SEC`. Changed from 7.2 on purpose: the streak's
  7 s clock waits while an Overlay is up.
- 2026-11-08 Claude: **quit crash, quiz hints, smoke-test bugs.** Kaan's quit aborted with `recursive_mutex lock failed`
  (never reproduced here). Fix = orderly quit (see Current state): headless `--verbose` exits had leaked 2 audio
  playbacks on the Music bus (late `_got_stem` deferred calls started music after stop); now 0 leaks, windowed
  `--quittest=tts|reload` clean. New dev flags: `--quittest=tts|reload|close`, `--continue` (skip intro, press
  CONTINUE), `--toastlog` (print every toast), `--lessontest --hint`. **💡 İPUCU** in `quiz_ui.gd`: H or click, 15₺,
  one per question (MC: all but one wrong answer fade; typed: first third typed in + blanks; word order: first word
  placed, two in 5+ word sentences); guide line added. Smoke bugs: pin says FREE PLAY after the last mission
  (`Missions._idle_text`), lessons are a compact box low on screen with the title merged into page 1, monster bubbles
  sit above their Lv plates (`Enemy.say` / `head_point`, `Fx.label(..., lift)`), bar text outlines fade with the bar
  (the "dark STAMINA text"), a third toast makes the oldest fade within 1.2 s.
- 2026-11-07 Claude (parent session): **finished the paused full-game build** (ALPHA 8.0 · GAME GAME). The model session's 12-agent build had stopped on the usage limit with 8 systems written but none wired in; this session resumed the 2 cut-off builders (story+menus, sky+world), then an integrator wired every system into main.gd and a smoke agent fixed what broke. Proof: headless boots clean, `--brawl=SEC` combat bot (combos/rolls/blocks/lock-on/skills/faint, prints a BRAWL line) runs with no script errors, 3-mission autoplay from a fresh save, `tests/godot_save.js` ALL CHECKS PASS. New dev flags: `--brawl=SEC`, `--inv` (open the bag before a `--shot=`). Screenshots: `tools/shots/`. Known small bugs (smoke report): "Kaan is waiting" pin after the last mission, a lesson's first page is only the title, mob speech bubbles overlap their Lv plates, STAMINA label hard to read, 3 toasts stack at startup. Not playtested by hand yet.
- 2026-11-07 Claude (integrator): **batch 2+ "game game" wired into `main.gd`.** Ten systems built in parallel,
  then one integrator wired them, fixed the API mismatches and got a clean parse. New files in `godot/scripts/`:
  `bus.gd` (Bus), `combat.gd` (Combat: light/heavy chains, slam, dash), `lockon.gd` (LockOn), `arsenal.gd` (Arsenal:
  guns, ammo, durability, hold-Q wheel, drops) + `weapon_wheel.gd` + `projectile.gd`, `skills.gd` (Skills: 10 skills,
  buffs, boss battle quiz), `hotbar.gd` + `minimap.gd` (HUD parts), `audio.gd` (Audio: 117 synthesised sounds, music
  stems, TTS) + `fx.gd` (Fx: sparks, slashes, rings, hit-stop), `items.gd` (Items: nazars, food, gear, chests, loot),
  `stats.gd` (Stats: 7.2 stat()), `levelup.gd` (LevelUp: level-up show, perks, tip cards), `inventory_ui.gd` (I/J bag),
  `spawner.gd` (Spawner: roaming/night mobs, minibosses, stinky Cruze), `ally.gd` (Josh squad), `mob_models.gd`
  (code-built monsters), `shops.gd`, `quests.gd`, `tutors.gd`, `tavla.gd` + `tavla_ui.gd`, `hotspots.gd` (Kaan's
  door, contracts, airport), `cutscene.gd` (calls, boss intros, Hellspace, opening, credits), `menus.gd` (title,
  pause/options, guide, patch notes, toggle bar, E prompt line), `tips.gd` (new first-time cards), `sky.gd`
  (SkyCycle: day/night sky, PS1 dither + NIGHT GRADE pass), `world_life.gd` (cars, birds, blimp, plane),
  `interactables.gd` (Josh, fountains, simit carts, DJ booth), `intro.gd` (VHS intro + cast cards). Data:
  `assets/items/items.json`, `assets/side/*.json`, `assets/story/godot.json` + `story72.json`.
  **Keys (new):** RIGHT mouse heavy, Left Ctrl roll, hold Z block/parry, Tab lock-on, ledge climb automatic, 0/8/9
  skills. **Bus events:** enemy_died, enemy_hit, player_hit, player_attack, pickup, level_up, sfx, skill_used, lira,
  xp, faint, respawn, mission_start, mission_done, night, plus new: boss_quiz, ammo, weapon_equip, weapon_new,
  weapon_broke, weapon_gained, gear_gained, bag_changed, duel, dj, gfx, voice, enemy_tell, enemy_notice,
  enemy_attack, mob_talk, quiz_answer (listened to by Audio/Fx; nobody emits it yet), quest_done (same).
  **Save fields:** 7.2 names for everything 7.2 has (ammo, weap, wi, dur, bassD, gear, eq, gu, bag, nz, perks, pp,
  msd, tips, mh, mm, ms, lira, int, cigs, npc, q, qa, mastered, bounty, gate, next, mid, done, shades, kills...);
  new Godot-only: gPatch, gGfx, gGlow, gGrade, side, npc.allmastered, musicOn (+ musVol/sfxVol/voiceOn moved in
  from torii_opts). **Integrator fixes:** Fx.hitstop <-> player.hitstop infinite recursion (Fx now owns
  time_scale alone); Menus called SkyCycle gfx/glow functions that sky.gd dropped (Menus owns GRAFİK gGfx + NEON
  GLOW gGlow again, SkyCycle owns NIGHT GRADE gGrade; both read gGlow as "on unless false"); NEW GAME keeps gGrade;
  HUD clock reads SkyCycle.clock_text(); Tts.say goes through Audio.speak; mission pickups now run Items.effect
  (7.2 collect(): word/XP/heal) and emit Bus pickup kind 'mission'; cutscene skyline set_pixel out of bounds;
  `--autoplay` closes tip cards and picks perks so it doesn't stall; player step-up onto kerbs/ramp lips never
  fired (it used the velocity move_and_slide had already zeroed) so she was stuck at the foot of Tower Bridge —
  fixed; `--fxtest` / `--lessontest` / `--godkey` first clear the story's opening call scene (`_dev_clear`), and
  `--godkey` now uses a real shrine (gods are positional in the new missions.gd). Checks run (scratch saves):
  every script loads, normal boot to the title, `--autoplay=3` (missions 1-3 + gates, lvl 11→12), `--fxtest`
  (river, bridge, checkpoint, hit, faint all OK), `--godkey` (coin toss stays open), `--savecheck` (no keys lost). Arsenal.roll_damage already used `rdmg` as a
  multiplier. Dev: `--apdebug` prints the autoplay state every 100 ticks; roaming monsters are off in
  --shot/--lessontest/--fxtest/--godkey/--savecheck/--fps/--probe runs. Note: headless runs end with a libc++
  "recursive_mutex lock failed" abort on quit (it happened before the wiring too; harmless, after the run).
- 2026-11-05 Claude: **batch 1 "Safety net + controls back"** in `godot/` (details: PORT_GAPS.md §0). New: `scripts/overlay.gd` (`Overlay.open/close/any/just_closed` — the one gate for "a box is up": enemies, shots, her controls and damage, mission clocks), `scripts/rich.gd` (HTML ⇄ BBCode, `plain()` for key compares), `scripts/save_ui.gd` (BRING YOUR SAVE / SAVE & LOAD, drag-drop via `files_dropped`, native file dialog, Downloads export, transfer code). `SaveBridge`: `migrate()` (7.2 applySave repairs), `save_text()`, `import_text()` (freezes writes until the scene reloads), `export_text()`, `code()`, `file_name()`. Hud: `say()/next_line()/skip_say()` replace `call_box`; `choose()` cb gets -1 when closed; `toast(t, dur=6, bad=false)` stack. Player: camera is a top-level Camera3D driven by `_camera()` (port of updateCam), `heading` = bike direction, `yaw` = camera/her facing, new actions `turn_left/turn_right` (arrows). Dev flags: `--import=FILE` (same as dropping a file), `--savecheck` (load+repair+resume, write, print), `--welcome` (show BRING YOUR SAVE in a shot), `--godkey` (E at a god shrine via the real input path). Note: `--lessontest` needs a window (frame_post_draw never fires headless). Test: `tests/godot_save.js` (~6 min, needs `godot` on PATH).
- 2026-11-05 Claude: **gap audit done** → `godot/PORT_GAPS.md` + `godot/port_gaps.json`. Workflow: 6 area mappers (combat, progression/save, story, Turkish, UI, world/sound), an adversarial verifier per area, a completeness critic, a writer (14 agents, all at High). 222 gaps kept, 1 refuted, 5 critic-only, 10 blind spots. Hand spot-check confirmed CRT-01, CMB-01, PLY-01, UI-01, WLD-V01. Biggest risks: a desktop build cannot see her browser save; kill level-ups are not saved until the next mission/lesson write; pre-7.0 saves would get `lvlv:2` without their migration. Index files for re-auditing live only in that session's scratchpad (rebuild from the 7.2 file if needed).
- 2026-10-27 Claude: **all 20 missions ported** (generic engine). `tools/missions/convert_missions.py` turns 7.2's
  MISSIONS (exported with function source) + GATES/ZSPAWN/ZNAME/WEAPONS into `godot/assets/missions/missions.json`
  (spawn patterns, deliver timers, boss phase ops, choice options, rewards parsed out of the JS). Models exported
  from 7.2: 12 monsters/bosses (`assets/mobs/`, person-based ones have leg_/arm_/head joints named), 32 weapons
  (`assets/weapons/`), 12 mission pickups (`assets/pickups/`). `scripts/enemy.gd` (`Enemy.spawn`) = every monster
  with 7.2 stats: melee, archers/casters shoot (`scripts/shot.gd`), ghosts float, chargers wind up/dash/daze, boss
  phases (caster/charger/enrage/summon), elites (gold, ×2). `scripts/missions.gd` (`Missions`) = step types goto,
  collect, kill (waves until done), return, zone (+dance), deliver (timer, fast/late, fragile), travel (teleport to
  ZSPAWN), boss, god (heads-or-tails best of 3, sets npc.god_<id>), choice (`Hud.choose`), photo (T); Kaan's call
  per mission (ENTER), rewards (weapons+dur, mh, mm, lira, teach), HUNT GATE between missions (spawns the gate's
  monsters near her, 3 at a time), proceedTo/advanceUnit (forces the unit's 3 lessons first). Player: Q = next
  weapon (7.2 has a hold-Q wheel — simplified), weapons wear per hit and break, `ToriiPose.dance()`.
  mission1.gd/imp.gd removed (imp is an Enemy now). Dev: `--autoplay=N --savedir=DIR` plays N missions alone.
  Proof: 4 missions from a fresh 7.2 save → level 7, unit 4, 6 weapons; real 7.2 loads it (mission "park" next).
  FULL RUN: all 20 missions + every hunt gate autoplayed (fresh 7.2 save → level 18, unit 16, 27 weapons,
  6341 lira); the real 7.2 loads the final save with no errors. Fixes from the run: hunt gate counts are clamped
  (extra kills drove `left` negative and hid the epics still owed → gate never finished); `_st()` returns {}
  when no mission runs (after the last one). Autoplay loop limit 60000 (`main.gd`). Not committed yet.
  Note: tests/harness.js needs `TORII_DIR="/Users/kaan/Claude/Video Game Torii"` (its default path is stale).
  Not ported: Hellspace cutscenes between missions, the dawn sky, SKILLS cooldown rewards, ranged weapons/ammo,
  the gods' original game rules (simplified to best-of-3 coin toss), Josh/Stockton extras, bounty contracts.
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
