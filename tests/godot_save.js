// Godot port ⇄ 7.2 save round trip (batch 1 of godot/PORT_GAPS.md). Needs Godot 4 on the PATH as `godot`.
// 1. the REAL 7.2 game (newest HTML in the root) makes a save mid hunt-gate, with a missed question in it
// 2. Godot imports that file the way dragging it onto the window does, repairs + resumes it (--savecheck)
//    → nothing may change, and the hunt must stay "thots" (7.2 saves no type)
// 3. real 7.2 loads the save Godot wrote: same level, words, weapons, hunt, missed list, no errors
// 4. a pre-7.0 save (no lvlv) converts in Godot to exactly what 7.2's own applySave() gives
// 5. a transfer code (base64) imports like the file
// 6. Godot plays one mission from it (--autoplay=1) and 7.2 still loads the result
const {boot}=require('./harness');
const fs=require('fs'),path=require('path'),os=require('os'),cp=require('child_process');
const wait=ms=>new Promise(r=>setTimeout(r,ms));
let fails=0;
const ok=(l,c)=>{if(!c)fails++;console.log('  '+(c?'✓':'✗')+' '+l);};
const ROOT=process.env.TORII_DIR||path.resolve(__dirname,'..');
const GODOT=process.env.GODOT||'godot';
const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'torii-godot-'));
// canonical JSON (sorted keys) so 14 vs 14.0 and key order don't count as changes
const canon=v=>v===null||typeof v!=='object'?JSON.stringify(v):Array.isArray(v)?'['+v.map(canon).join(',')+']':
 '{'+Object.keys(v).sort().map(k=>JSON.stringify(k)+':'+canon(v[k])).join(',')+'}';
function godot(dir,args,timeout){
 const r=cp.spawnSync(GODOT,['--headless','--path',path.join(ROOT,'godot'),'--','--savedir='+dir,...args],
  {encoding:'utf8',timeout:timeout||120000});
 const out=(r.stdout||'')+(r.stderr||'');
 const errs=out.split('\n').filter(l=>/SCRIPT ERROR|Parse Error|ERROR:/.test(l)&&!/ALSA|audio|XDG|dbus/i.test(l));
 return {out,errs,status:r.status};
}
function readSave(dir){return JSON.parse(fs.readFileSync(path.join(dir,'torii_save.json'),'utf8'));}
async function load72(raw){
 const B=boot();const g=k=>B.w.eval(k);
 await wait(1600);
 B.T('localStorage.setItem("torii_save",'+JSON.stringify(raw)+');$("contBtn").style.display="inline-block";');
 B.w.document.getElementById('contBtn').click();await wait(1800);
 B.T('closePatch();if(S.cut)endCut(true);S.dlgOpen=false;closeTip();closePerks();');
 return {B,g};
}
(async()=>{
 // ---- 1. a real 7.2 save, mid-hunt, with a missed question ----
 const A=boot();let g=k=>A.w.eval(k);
 await wait(1600);
 A.w.document.getElementById('startBtn').click();await wait(1500);
 A.T(`S.level=14;S.xpNeed=xpFor(14);S.xp=Math.round(S.xpNeed*.4);S.maxhp=298;S.hp=250;S.maxmana=180;S.int=4;
  S.lira=5555;S.ammo=17;S.kills=777;S.weapons=['katana','oklava','bass'];S.wi=2;S.dur={katana:40,oklava:12,bass:30};
  ['ev','su','köpek','gece','ay','güneş'].forEach(w=>teach(w));S.npc={diskoking:'done',tavla_cin:'beat'};
  S.unit=3;S.unitLesson=2;S.mastered={1:true,2:true};S.godsWins=1;S.shades=true;S.lessonIdx=7;S.lessonKills=3;
  rememberMiss({kind:'mc',vis:'🏠',text:'What does <b>ev</b> mean?',opts:['house','water'],a:0,expl:'<i>ev</i> = house'});
  S.mission=null;S.missionIdx=2;S.gate={next:3,type:'thot',left:7,eleft:0};saveGame();`);
 const raw72=g('localStorage.getItem("torii_save")');const s72=JSON.parse(raw72);
 A.w.close();
 console.log('1. A REAL 7.2 SAVE (level '+s72.lvl+', unit '+s72.unit+', hunt gate '+JSON.stringify(s72.gate)+', '+s72.missed.length+' missed)');
 ok('7.2 saves the hunt without a monster type',s72.gate&&!('type' in s72.gate)&&s72.gate.left===7);
 const file=path.join(tmp,'torii-save-lvl14-test.json');fs.writeFileSync(file,raw72);

 // ---- 2. Godot imports + resumes it ----
 const d1=path.join(tmp,'g1');fs.mkdirSync(d1);
 const r1=godot(d1,['--import='+file,'--savecheck']);
 const chk=(r1.out.match(/SAVECHECK (.*)/)||[])[1];
 console.log('\n2. GODOT IMPORTS THE FILE');
 ok('Godot ran with no script errors'+(r1.errs.length?' — '+r1.errs.slice(0,3).join(' | '):''),r1.errs.length===0&&!!chk);
 ok('import read it as level 14',/IMPORT lvl=14/.test(r1.out));
 const c1=chk?JSON.parse(chk):{};
 ok('the hunt resumes as THOTS, 7 left ('+JSON.stringify(c1.gate)+')',c1.gate&&c1.gate.type==='thot'&&c1.gate.left===7);
 const sg=readSave(d1);
 const changed=Object.keys(s72).filter(k=>canon(s72[k])!==canon(sg[k]));
 const durOk=k=>k==='dur'&&Object.keys(s72.dur).every(w=>s72.dur[w]===sg.dur[w]||(s72.dur[w]===null&&sg.dur[w]===9999));
 ok('every 7.2 field kept'+(changed.length?' (differs: '+changed.join(', ')+')':''),changed.every(k=>durOk(k)));
 ok('no fields added (the hunt keeps 7.2\'s own shape)',Object.keys(sg).every(k=>k in s72)&&(!sg.gate||!('type' in sg.gate)||sg.gate.type==='thot'));
 ok('the imported 7.2 file is kept word for word as the backup',fs.readFileSync(path.join(d1,'torii_save_bak.json'),'utf8')===raw72);

 // ---- 3. real 7.2 loads what Godot wrote ----
 console.log('\n3. 7.2 LOADS THE GODOT SAVE');
 let L=await load72(JSON.stringify(sg));g=L.g;
 ok('same level ('+g('S.level')+') and XP',g('S.level')===14&&g('S.xp')===s72.xp);
 ok('same words ('+g('S.wordsCount')+')',g('S.wordsCount')===s72.words.length);
 ok('same weapons',g('JSON.stringify(S.weapons)')===JSON.stringify(s72.weap));
 ok('same hunt (thot, 7 left)',g('S.gate&&S.gate.type')==='thot'&&g('S.gate.left')===7);
 ok('missed question kept in 7.2 form',g('S.missed.length')===1&&/<b>ev<\/b>/.test(g('S.missed[0].q.text')));
 ok('no errors in 7.2',L.B.E.length===0);
 L.B.w.close();

 // ---- 4. a pre-7.0 save converts exactly like 7.2's applySave() ----
 console.log('\n4. PRE-7.0 SAVE CONVERSION (Godot vs 7.2)');
 const old=JSON.parse(raw72);delete old.lvlv;delete old.msd;delete old.gate;old.next=3;
 old.need=Math.round(60*Math.pow(14,1.35));old.xp=Math.round(old.need*.4);old.pp=0;old.mh=260;old.mm=150;old.ms=100;
 const oldFile=path.join(tmp,'old.json');fs.writeFileSync(oldFile,JSON.stringify(old));
 L=await load72(JSON.stringify(old));g=L.g;
 const want={xp:g('S.xp'),need:g('S.xpNeed'),mh:g('S.maxhp'),mm:g('S.maxmana'),ms:g('S.maxStam'),pp:g('S.perkPicks'),msd:JSON.parse(g('JSON.stringify(S.msDone)'))};
 L.B.w.close();
 const d4=path.join(tmp,'g4');fs.mkdirSync(d4);
 const r4=godot(d4,['--import='+oldFile,'--savecheck']);
 const so=readSave(d4);
 const got={xp:so.xp,need:so.need,mh:so.mh,mm:so.mm,ms:so.ms,pp:so.pp,msd:so.msd};
 ok('Godot ran clean',r4.errs.length===0);
 for(const k of Object.keys(want))ok(k+': 7.2 '+canon(want[k])+' · Godot '+canon(got[k]),canon(want[k])===canon(got[k]));
 ok('stamped lvlv:2 only after converting',so.lvlv===2);

 // ---- 5. transfer code ----
 console.log('\n5. TRANSFER CODE');
 const code=Buffer.from(raw72,'utf8').toString('base64');
 const codeFile=path.join(tmp,'code.txt');fs.writeFileSync(codeFile,code);
 const d5=path.join(tmp,'g5');fs.mkdirSync(d5);
 const r5=godot(d5,['--import='+codeFile,'--savecheck']);
 ok('the code imports as the same level 14 save',/IMPORT lvl=14/.test(r5.out)&&readSave(d5).kills===777);
 const junk=path.join(tmp,'junk.txt');fs.writeFileSync(junk,'hello, not a save');
 const d5b=path.join(tmp,'g5b');fs.mkdirSync(d5b);
 const r5b=godot(d5b,['--import='+junk,'--savecheck']);
 ok('junk is refused and writes nothing she had',/IMPORT lvl=0/.test(r5b.out));

 // ---- 6. play a mission in Godot, then 7.2 loads it ----
 console.log('\n6. ONE MISSION IN GODOT, THEN BACK TO 7.2');
 const d6=path.join(tmp,'g6');fs.mkdirSync(d6);
 const r6=godot(d6,['--import='+file,'--autoplay=1'],420000);
 const s6=readSave(d6);
 ok('Godot played clean ('+((r6.out.match(/AUTOPLAY .*/)||['no AUTOPLAY line'])[0]).slice(0,110)+')',r6.errs.length===0&&/AUTOPLAY/.test(r6.out));
 ok('hunt done and the next mission reached (next '+s6.next+')',s6.next>=4&&!s6.gate);
 ok('nothing she had is gone',['words','weap','npc','mastered','missed'].every(k=>k in s6)&&s6.words.length>=6&&s6.lvl>=14);
 L=await load72(JSON.stringify(s6));g=L.g;
 ok('7.2 opens it at level '+g('S.level')+', mission '+g('S.missionIdx'),g('S.level')===s6.lvl&&L.B.E.length===0);
 L.B.w.close();
 console.log(fails?'\nFAILED: '+fails+' check(s)':'\nALL CHECKS PASS ✓');
 fs.rmSync(tmp,{recursive:true,force:true});
 process.exit(fails?1:0);
})();
setTimeout(()=>{console.log('TIMEOUT');process.exit(2);},900000);
