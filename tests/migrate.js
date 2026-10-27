// ALPHA 7.0 — her REAL 6.0 save, made by the real 6.0 game, loaded by 7.0 through CONTINUE.
// Nothing she earned may change except what 7.0 adds on top.
const {boot}=require('./harness');
const path=require('path');
const wait=ms=>new Promise(r=>setTimeout(r,ms));
const ok=(l,c)=>console.log('  '+(c?'✓':'✗')+' '+l);
const NEW=process.env.TORII_DIR||path.resolve(__dirname,'..');
const OLD=process.env.TORII_OLD||path.join(NEW,'backups');
(async()=>{
 // ---- 1. play a while in 6.0 ----
 let A=boot(OLD);let g=k=>A.w.eval(k);
 await wait(1600);
 A.w.document.getElementById('startBtn').click();await wait(1500);
 A.T(`S.level=14;S.xpNeed=Math.round(60*Math.pow(14,1.35));S.xp=Math.round(S.xpNeed*.4);S.maxhp=298;S.hp=250;S.maxmana=180;S.int=4;
  S.lira=5555;S.ammo=17;S.kills=777;S.weapons=['katana','oklava','bass'];S.wi=2;S.dur={katana:40,oklava:12,bass:30};
  ['ev','su','köpek','gece','ay','güneş'].forEach(w=>teach(w));S.npc={diskoking:'done',tavla_cin:'beat',dino:'done'};
  S.unit=11;S.unitLesson=2;S.mastered={1:true,2:true,3:true};S.godsWins=3;S.cigs=5;S.shades=true;S.lessonIdx=7;S.lessonKills=3;
  S.missionIdx=11;S.mission=null;S.gate=null;saveGame();`);
 const raw6=g('localStorage.getItem("torii_save")');const s6=JSON.parse(raw6);
 console.log('1. A 6.0 SAVE  (level '+s6.lvl+', '+s6.words.length+' words, '+s6.lira+'₺, unit '+s6.unit+', next mission '+s6.next+')');
 ok('made by the real 6.0 game',!!raw6&&s6.v===3&&!('lvlv' in s6));
 A.w.close();
 // ---- 2. open 7.0 and press CONTINUE ----
 let B=boot();g=k=>B.w.eval(k);
 await wait(1600);
 B.T('localStorage.setItem("torii_save",'+JSON.stringify(raw6)+');$("contBtn").style.display="inline-block";');
 B.w.document.getElementById('contBtn').click();await wait(1800);
 B.T('closePatch();if(S.cut)endCut(true);S.dlgOpen=false;closeTip();closePerks();');
 console.log('\n2. 7.0 CONTINUES IT');
 ok('same level ('+g('S.level')+')',g('S.level')===14);
 ok('same lira, kills, ammo',g('S.lira')===5555&&g('S.kills')===777&&g('S.ammo')===17);
 ok('same words ('+g('S.wordsCount')+')',g('S.wordsCount')===s6.words.length);
 ok('same weapons and wear',g('JSON.stringify(S.weapons)')===JSON.stringify(s6.weap)&&g('S.dur.oklava')===12);
 ok('same book unit, lesson and mastered units',g('S.unit')===11&&g('S.unitLesson')===2&&g('Object.keys(S.mastered).length')===3);
 ok('same story position (next mission '+g('S.missionIdx')+')',g('S.missionIdx')===s6.next||g('S.mission&&S.missionIdx')===s6.next);
 ok('NPC history kept (tavla wins, finished helpers)',g('S.npc.tavla_cin')==='beat'&&g('S.npc.diskoking')==='done');
 ok('same INT, gods, sunglasses',g('S.int')===4&&g('S.godsWins')===3&&g('S.shades')===true);
 ok('XP bar keeps its place ('+(s6.xp/s6.need).toFixed(2)+' → '+(g('S.xp')/g('S.xpNeed')).toFixed(2)+')',Math.abs(s6.xp/s6.need-g('S.xp')/g('S.xpNeed'))<.01);
 ok('max HP only goes UP ('+s6.mh+' → '+g('S.maxhp')+')',g('S.maxhp')>=s6.mh);
 ok('13 perk cards waiting, one per level earned',g('S.perkPicks')===13);
 // ---- 3. it saves as 7.0 and nothing from 6.0 went missing ----
 B.T('saveGame();');
 const s7=JSON.parse(g('localStorage.getItem("torii_save")'));
 const changed=Object.keys(s6).filter(k=>JSON.stringify(s6[k])!==JSON.stringify(s7[k]));
 console.log('\n3. RE-SAVED AS 7.0');
 ok('every 6.0 field is still in the save',Object.keys(s6).every(k=>k in s7));
 ok('the only fields that changed are the ones 7.0 rescales: '+changed.join(', '),changed.every(k=>['xp','need','mh','mm','next','mid','resp'].includes(k)));
 ok('and the 6.0 save is kept as the rolling backup',g('localStorage.getItem("torii_save_bak")')===raw6);
 const E=[...A.E,...B.E];
 console.log(E.length?'ERRORS: '+[...new Set(E)].slice(0,5).join(' ;; '):'NO ERRORS ✓');
 process.exit(0);
})();
setTimeout(()=>{console.log('TIMEOUT');process.exit(2);},60000);
