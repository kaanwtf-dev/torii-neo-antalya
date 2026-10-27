// ALPHA 7.0 — the guide: PAUSE (P) → 📘 GUIDE explains every system
const {boot}=require('./harness');
const {w,errs,E,T}=boot();
const wait=ms=>new Promise(r=>setTimeout(r,ms));
const ok=(l,c)=>console.log('  '+(c?'✓':'✗')+' '+l);
const g=k=>w.eval(k);
const key=k=>w.dispatchEvent(new w.KeyboardEvent('keydown',{key:k,bubbles:true}));
setTimeout(async()=>{
 w.document.getElementById('startBtn').click();
 await wait(1400);T('closePatch()');T('if(S.cut)endCut(true)');await wait(200);T('if(S.cut)endCut(true);S.dlgOpen=false;$("dlg").style.display="none";closeTip();');
 console.log('1. FINDING IT');
 key('p');
 ok('P opens the pause menu',g('S.paused')===true);
 ok('...which now has a 📘 GUIDE button',!!g('$("optGuide")')&&g('$("optGuide").textContent').indexOf('GUIDE')>=0);
 T('$("optGuide").click()');
 ok('the guide opens over it',g('$("guideBox").style.display')==='flex'&&g('S.uiOpen')==='guide');
 console.log('\n2. WHAT IS IN IT');
 const html=g('$("gdBody").innerHTML');
 for(const [l,needle] of [['controls with the new keys','<b>H</b> eat'],['Levels 2.0','LEVELS 2.0'],['perk cards','PERK CARDS'],
  ['every 5th level','Level 25'],['monster levels','MONSTER LEVELS'],['boss phases','BOSS PHASES'],['gear and rarities','legendary'],
  ['the backpack','BACKPACK'],['nazar beads','NAZAR'],['side quests','SIDE QUESTS'],['all six mission types','PHOTO HUNTS'],
  ['the story scenes','Hellspace'],['saving, and that fainting never costs a level','never a level']])
  ok(l,html.indexOf(needle)>=0);
 ok('her own numbers are in it (level, bag, beads)',html.indexOf('level '+g('S.level'))>=0&&html.indexOf('slots used')>=0&&html.indexOf('/ 50')>=0);
 ok('a topic chip for every section',g('$("gdIdx").querySelectorAll("button").length')===g('GUIDE.length'));
 console.log('\n3. GETTING OUT');
 key('Escape');
 ok('ESC closes the guide and goes back to the pause menu',g('$("guideBox").style.display')==='none'&&g('S.paused')===true&&g('S.uiOpen')===null);
 key('Escape');
 ok('ESC again resumes the game',g('S.paused')===false);
 console.log('\n4. LATER IN THE GAME');
 T('S.level=31;S.q={kedi:3,carsi:1};S.perks={keskin:2};S.perkPicks=2;openGuide();');
 const h2=g('$("gdBody").innerHTML');
 ok('milestones show as reached',h2.split('✅').length-1>=6);
 ok('finished quests say so, unfinished ones show progress',h2.indexOf('✅ finished')>=0&&h2.indexOf('1 / ')>=0);
 ok('her perks are listed',h2.indexOf('KESKİN ×2')>=0);
 T('closeGuide()');
 console.log(E.length?'ERRORS: '+[...new Set(E)].slice(0,5).join(' ;; '):'NO ERRORS ✓');
 console.log(errs.length?'RUNTIME: '+[...new Set(errs)].slice(0,3).join(' ;; '):'NO RUNTIME ERRORS ✓');
 process.exit(0);
},1800);
setTimeout(()=>{console.log('TIMEOUT');process.exit(2);},40000);
