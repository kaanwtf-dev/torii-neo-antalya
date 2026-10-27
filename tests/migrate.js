// ALPHA 7.2 — her REAL 7.1 save, made by the real 7.1 game (newest in backups/), loaded by 7.2
// through CONTINUE. 7.2 is a visual update: nothing in the save may change at all.
// (The 6.0 -> 7.0 conversion is still covered by regress.js's old-save checks.)
const {boot}=require('./harness');
const path=require('path');
const wait=ms=>new Promise(r=>setTimeout(r,ms));
let fails=0;
const ok=(l,c)=>{if(!c)fails++;console.log('  '+(c?'✓':'✗')+' '+l);};
const NEW=process.env.TORII_DIR||path.resolve(__dirname,'..');
const OLD=process.env.TORII_OLD||path.join(NEW,'backups');
(async()=>{
 // ---- 1. play a while in 7.1 ----
 let A=boot(OLD);let g=k=>A.w.eval(k);
 await wait(1600);
 A.w.document.getElementById('startBtn').click();await wait(1500);
 A.T(`S.level=14;S.xpNeed=xpFor(14);S.xp=Math.round(S.xpNeed*.4);S.maxhp=298;S.hp=250;S.maxmana=180;S.int=4;
  S.lira=5555;S.ammo=17;S.kills=777;S.weapons=['katana','oklava','bass'];S.wi=2;S.dur={katana:40,oklava:12,bass:30};
  ['ev','su','köpek','gece','ay','güneş'].forEach(w=>teach(w));S.npc={diskoking:'done',tavla_cin:'beat',dino:'done'};
  S.unit=11;S.unitLesson=2;S.mastered={1:true,2:true,3:true};S.godsWins=3;S.cigs=5;S.shades=true;S.lessonIdx=7;S.lessonKills=3;
  const pk=Array.isArray(PERKS)?PERKS[0].id:Object.keys(PERKS)[0];S.perks={[pk]:2};S.perkPicks=3;S.maxStam=130;
  S.msDone={5:true,10:true};S.tips=Object.assign({},S.tips,{lvltag:true});
  S.missionIdx=11;S.mission=null;S.gate=null;saveGame();`);
 const raw7=g('localStorage.getItem("torii_save")');const s7=JSON.parse(raw7);
 console.log('1. A 7.1 SAVE  (level '+s7.lvl+', '+s7.words.length+' words, '+s7.lira+'₺, unit '+s7.unit+', next mission '+s7.next+', '+s7.pp+' perk cards)');
 ok('made by the real 7.1 game',!!raw7&&s7.v===3&&s7.lvlv===2);
 A.w.close();
 // ---- 2. open 7.2 and press CONTINUE ----
 let B=boot();g=k=>B.w.eval(k);
 await wait(1600);
 ok('the new build is 7.2 ('+g('GAME_VER')+')',/^ALPHA 7\.2/.test(g('GAME_VER')));
 B.T('localStorage.setItem("torii_save",'+JSON.stringify(raw7)+');$("contBtn").style.display="inline-block";');
 B.w.document.getElementById('contBtn').click();await wait(1800);
 B.T('closePatch();if(S.cut)endCut(true);S.dlgOpen=false;closeTip();closePerks();');
 console.log('\n2. 7.2 CONTINUES IT');
 ok('same level ('+g('S.level')+')',g('S.level')===14);
 ok('same XP and XP bar ('+s7.xp+'/'+s7.need+' → '+g('S.xp')+'/'+g('S.xpNeed')+')',g('S.xp')===s7.xp&&g('S.xpNeed')===s7.need);
 ok('same lira, kills, ammo',g('S.lira')===5555&&g('S.kills')===777&&g('S.ammo')===17);
 ok('same words ('+g('S.wordsCount')+')',g('S.wordsCount')===s7.words.length);
 ok('same weapons and wear',g('JSON.stringify(S.weapons)')===JSON.stringify(s7.weap)&&g('S.dur.oklava')===12);
 ok('same book unit, lesson and mastered units',g('S.unit')===11&&g('S.unitLesson')===2&&g('Object.keys(S.mastered).length')===3);
 ok('same story position (next mission '+g('S.missionIdx')+')',g('S.missionIdx')===s7.next||g('S.mission&&S.missionIdx')===s7.next);
 ok('NPC history kept (tavla wins, finished helpers)',g('S.npc.tavla_cin')==='beat'&&g('S.npc.diskoking')==='done');
 ok('same INT, gods, sunglasses',g('S.int')===4&&g('S.godsWins')===3&&g('S.shades')===true);
 ok('same max HP and stamina',g('S.maxhp')===s7.mh&&g('S.maxStam')===s7.ms);
 ok('same perks and unspent perk cards ('+g('S.perkPicks')+')',g('JSON.stringify(S.perks)')===JSON.stringify(s7.perks)&&g('S.perkPicks')===s7.pp);
 ok('no second migration (still lvlv:2)',g('JSON.parse(localStorage.getItem("torii_save")).lvlv')===2);
 // ---- 3. it saves as 7.2 and not one field changed ----
 B.T('saveGame();');
 const s71=JSON.parse(g('localStorage.getItem("torii_save")'));
 const changed=Object.keys(s7).filter(k=>JSON.stringify(s7[k])!==JSON.stringify(s71[k]));
 console.log('\n3. RE-SAVED AS 7.2');
 ok('every 7.1 field is still in the save',Object.keys(s7).every(k=>k in s71));
 // CONTINUE starts the queued mission, so a save made between missions gains its id — same as in 7.1
 const midOk=!changed.includes('mid')||(s7.mid===null&&!!s71.mid&&s71.next===s7.next);
 ok('nothing changed except the queued mission starting'+(changed.length?' (changed: '+changed.join(', ')+')':''),
  changed.every(k=>k==='mid')&&midOk);
 ok('and the 7.1 save is kept as the rolling backup',g('localStorage.getItem("torii_save_bak")')===raw7);
 const E=[...A.E,...B.E];
 console.log(E.length?'ERRORS: '+[...new Set(E)].slice(0,5).join(' ;; '):'NO ERRORS ✓');
 console.log(fails?'FAILED: '+fails+' check(s)':'ALL CHECKS PASS ✓');
 process.exit(fails||E.length?1:0);
})();
setTimeout(()=>{console.log('TIMEOUT');process.exit(2);},60000);
