// ALPHA 7.0 — story: cutscenes, the Hellspace through-line, new step types, quest chains
const {boot}=require('./harness');
const {w,errs,E,T,clear}=boot();
const wait=ms=>new Promise(r=>setTimeout(r,ms));
const ok=(l,c)=>console.log('  '+(c?'✓':'✗')+' '+l);
const g=k=>w.eval(k);
// the mock has no real projection; pretend whatever we aim at is centre-screen
const aimAll=()=>T('tmpV.project=function(){this.x=0;this.y=0;this.z=.5;return this;};');
async function tick(n,dt){for(let i=0;i<n;i++){T('updateQuest('+(dt||.05)+','+(i*.05)+')');}}
// let queued dialogues/tips appear, then click through all of them
async function settle(ms){for(let i=0;i<(ms||2400)/200;i++){await wait(200);
 T(`if(S.cut)endCut(true);S.levelUpUntil=0;S.perkAutoT=0;if(S.uiOpen==="tip")closeTip();if(S.uiOpen==="perk")closePerks();for(let k=0;k<8&&!dlgChoiceCb&&(S.dlgOpen||$("dlg").style.display==="block");k++)dlgNext();`);}}
setTimeout(async()=>{
 w.document.getElementById('startBtn').click();
 await wait(1400);
 ok('the What\'s New panel comes first',g('S.patchOpen')===true);
 T('closePatch()');
 const iv=w.setInterval(clear,30);
 await wait(700);
 console.log('1. A NEW GAME OPENS ON A CUTSCENE');
 ok('the opening is playing (letterbox up, gameplay frozen)',g('S.cut')===true&&g('!!CUT'));
 ok('it starts with the "Bir Kaan yapımı" card',g('CUT.shots[0].title').indexOf('KAAN YAPIMI')>=0);
 T('cutKey("escape")');
 ok('ESC skips it',g('S.cut')===false);
 await wait(7400);
 ok('mission 1 then opens with an incoming CALL',g('S.cut')===true&&g('CUT.shots.some(s=>s.title&&s.title.indexOf("GELEN ARAMA")>=0)'));
 ok('Kaan\'s real mission lines are in it',g('CUT.shots.some(s=>s.line&&s.line.indexOf("avocados")>=0)'));
 ok('the call ends on the mission title card',g('CUT.shots[CUT.shots.length-1].title').indexOf('AVOCADO')>=0);
 for(let i=0;i<12&&g('S.cut');i++){T('CUT.t=1;cutNext()');}
 ok('pressing E through it lands in the mission',!g('S.cut')&&g('S.mission&&S.mission.id')==='avo');
 ok('mission order is untouched',g('MISSIONS.length')===20&&g('MISSIONS[0].id')==='avo'&&g('MISSIONS[19].id')==='kismet');

 console.log('\n2. THE THROUGH-LINE');
 ok('Hellspace scenes after 8 story missions',g('Object.keys(HELLSCENES).length')===8);
 T('S.cut=false;CUT=null;window.__hs=HELLSCENES.liv();');
 ok('a Karen scene builds her office set',g('CUTSET.ok')&&g('__hs.length')>4);
 ok('...with her real lines',g('__hs.some(s=>s.line&&s.line.indexOf("exit interview")>=0)'));
 T('playHell("avo")');await wait(400);
 ok('playHell runs it as a cutscene',g('S.cut')===true);
 T('endCut(true)');

 console.log('\n3. MAIN MISSIONS GOT NEW STEP TYPES');
 const types=g('JSON.stringify(MISSIONS.map(m=>m.steps.map(s=>s.t)))');
 ok('döner: timed delivery home',types.indexOf('"deliver"')>=0&&g('MISSIONS[2].steps[3].t')==='deliver');
 ok('bazaar: a Turkish choice',g('MISSIONS.find(m=>m.id==="bazaar").steps.some(s=>s.t==="choice")'));
 ok('marina: a photo hunt',g('MISSIONS.find(m=>m.id==="marina").steps.some(s=>s.t==="photo")'));
 ok('Karen, the Cruze and the Terrible Driver fight in phases',
  g('["karen","cruze","kismet"].every(id=>MISSIONS.find(m=>m.id===id).steps.some(s=>s.phases))'));
 // run the döner delivery for real
 T('S.cut=false;startMission(2);endCut(true);');await wait(300);T('endCut(true)');
 T('S.mStep=2;advanceStep();');
 ok('the delivery step starts with a timer',g('MAINR.d&&MAINR.d.ph')==='run'&&g('MAINR.d.time')>10);
 T('player.position.set(-24,0,-12);updateMission(.05,1);');
 ok('arriving home in time completes the mission',g('S.mission')===null);

 console.log('\n4. BOSS PHASES');
 T('window.__k=spawnEnemy("karen",5,5);__k.phases=MISSIONS[12].steps[1].phases.map(p=>Object.assign({},p));');
 T('__k.hp=__k.maxhp*.6+1;hitEnemy(__k,1);');
 ok('at 66% Karen starts throwing staplers (caster)',g('__k.caster')===true);
 T('__k.hp=__k.maxhp*.3+2;hitEnemy(__k,1);');
 ok('at 33% she charges (charger) and hits harder',g('__k.charger')===true);

 console.log('\n5. QUEST: THE FERRY RACE (race)');
 T('S.level=9;S.q={};S.qa=null;S.cut=false;questStart("kaptan");');
 ok('quest started, 11 rings out',g('S.qa&&S.qa.id')==='kaptan'&&g('QR.d.rings.length')===11);
 T('S.onBike=true;');
 const pts=JSON.parse(g('JSON.stringify(QR.d.pts)'));
 for(const p of pts){T('player.position.set('+p[0]+',gY('+p[0]+','+p[1]+'),'+p[1]+')');await tick(2,.05);}
 ok('riding every ring in time finishes the race',g('curQuestStep()&&curQuestStep().t')==='talk');
 T('S.onBike=false;const G=qGiver("riza");player.position.set(G.x,0,G.z+1);questInteract();');
 await settle();
 ok('reporting back finishes part 1 and pays out',g('S.q.kaptan')===1&&g('S.qa')===null);

 console.log('\n6. QUEST: THE PICKPOCKET (chase)');
 T('S.level=7;S.q.carsi=1;questStart("carsi");');
 ok('a runner appears',g('!!(QR.d&&QR.d.g)'));
 await tick(20,.05);
 T('player.position.set(QR.d.g.position.x+1,0,QR.d.g.position.z);');await tick(1);
 ok('getting close catches him',g('curQuestStep().t')==='talk');
 T('questAbandon();');

 console.log('\n7. QUEST: PAMUK (photo → escort)');
 aimAll();
 T('S.level=5;S.q.kedi=0;questStart("kedi");');
 ok('three cats are hiding',g('QR.d.tg.length')===3);
 T('takePhoto();');
 ok('from far away, T finds nothing',g('QR.d.n')===0);
 for(let i=0;i<3;i++){T('const o=QR.d.tg['+i+'];camera.position.set(o.g.position.x+6,2,o.g.position.z+6);takePhoto();');}
 ok('close up, each press of T photographs a cat — all three done',g('curQuestStep().t')==='talk');
 T('const G=qGiver("fatma");player.position.set(G.x,0,G.z+1);questInteract();');
 await settle();
 ok('part 1 done',g('S.q.kedi')===1);
 T('questStart("kedi");player.position.set(2,0,300);');await tick(2);
 ok('part 2: at the swings the escort begins',g('curQuestStep().t')==='escort'&&g('!!QR.d.g'));
 for(let i=0;i<400&&g('S.qa&&curQuestStep()&&curQuestStep().t==="escort"');i++){
  T('player.position.set(QR.d.g.position.x+2,0,QR.d.g.position.z+2);for(const e of enemies.slice())killEnemy(e);');await tick(4,.1);}
 await settle();
 ok('Pamuk walked home safely',g('S.q.kedi')===2);
 ok('...and the Kedi Gözü sunglasses are in the gear bag',g('S.gear.some(it=>it.n==="Kedi Gözü")'));

 console.log('\n8. QUEST: THE RUG (Turkish choices)');
 T('S.level=7;S.q.carsi=0;S.qa=null;questStart("carsi");player.position.set(-156,0,58);');
 for(let q=0;q<3;q++){
  await tick(2);
  const txt=g('document.getElementById("dlgText").innerHTML');
  const opts=txt.split('<br>').filter(s=>/^<b>\d\.<\/b>/.test(s));
  const want=['Bin lira','Sekiz yüz','Güle güle'][q];
  const k=opts.findIndex(s=>s.indexOf(want)>=0);
  T('dlgChoice('+k+');');await settle(800);
 }
 await settle();
 ok('three right answers sell the rug',g('S.q.carsi')===1);

 console.log('\n9. QUESTS SAVE');
 T('questStart("defter");saveGame();');
 const sv=JSON.parse(g('localStorage.getItem("torii_save")'));
 ok('progress and the active part are saved',sv.q&&sv.q.kaptan===1&&sv.qa&&sv.qa.id==='defter');
 T('S.q={};S.qa=null;applySave(loadGame());');
 ok('...and restored',g('S.q.kaptan')===1&&g('S.q.kedi')===2);
 await wait(4300);
 ok('the active quest restarts on load',g('S.qa&&S.qa.id')==='defter');

 w.clearInterval(iv);
 console.log(E.length?'ERRORS: '+[...new Set(E)].slice(0,5).join(' ;; '):'NO ERRORS ✓');
 console.log(errs.length?'RUNTIME: '+[...new Set(errs)].slice(0,3).join(' ;; '):'NO RUNTIME ERRORS ✓');
 process.exit(0);
},1800);
setTimeout(()=>{console.log('TIMEOUT');process.exit(2);},90000);
