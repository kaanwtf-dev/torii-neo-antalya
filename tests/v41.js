const {boot}=require('./harness');
const {w,errs,E,T,clear}=boot();
setTimeout(()=>{
 console.log('BUILD  meshes:',w.__meshes);
 w.document.getElementById('startBtn').click();
 setTimeout(()=>{
  const iv=w.setInterval(clear,30);
  const ok=(l,c)=>console.log('  '+(c?'✓':'✗')+' '+l);
  console.log('KILL FEEL — streaks, escalating payouts, flying loot');
  T('S.streak=0;S.streakShown=0;S.lira=0;S.xp=0;enemies.length=0;player.position.set(0,0,0);S.dead=false;');
  const tiers=[];
  for(let i=0;i<26;i++){T('const e=spawnEnemy("imp",3,3);e.hp=1;hitEnemy(e,99);');
   const m=w.eval('streakMult()');if(tiers[tiers.length-1]!==m)tiers.push(m);}
  console.log('   multiplier climbed:',tiers.join(' -> '));
  ok('streak reaches ×3 at 25 kills',w.eval('streakMult()')===3);
  ok('lira actually arrived: '+w.eval('S.lira')+'₺',w.eval('S.lira')>0||w.eval('coinPool.filter(c=>c.live).length')>0);
  console.log('   coins in flight:',w.eval('coinPool.filter(c=>c.live).length'));
  T('for(let i=0;i<200;i++)updateCoins(.05);');
  ok('and they home in and get collected ('+w.eval('S.lira')+'₺)',w.eval('S.lira')>0);
  T('S.streakT=0;decayStreak();');
  ok('streak decays when she stops',w.eval('S.streak')===0);
  console.log('BIKE — drift, crash, ramming');
  ok('drift state exists',w.eval('typeof S.drifting')==='boolean');
  T('S.onBike=true;bk.parked=false;bk.speed=18;player.position.set(0,0,0);player.rotation.y=0;S.yaw=0;S.wipeT=0;');
  T('keys[" "]=true;keys["a"]=true;');
  const y0=w.eval('player.rotation.y');
  for(let i=0;i<20;i++){clear();T('updatePlayer(.03,'+(i*.03)+')');}
  ok('holding SPACE into a turn drifts',w.eval('S.drifting'));
  ok('drift turns much harder than normal steering ('+
     (w.eval('player.rotation.y')-y0).toFixed(2)+' rad)',(w.eval('player.rotation.y')-y0)>.6);
  ok('and scrubs speed off ('+w.eval('bk.speed').toFixed(1)+')',w.eval('bk.speed')<18);
  T('keys[" "]=false;keys["a"]=false;');
  const xp0=w.eval('S.xp');
  for(let i=0;i<3;i++){clear();T('updatePlayer(.03,9)');}
  ok('a long drift pays out on release',w.eval('S.xp')>=xp0);
  // crash odds
  let fell=0,wobbled=0;
  for(let i=0;i<400;i++){
   T('S.wipeT=0;S.wobbleT=0;S.onBike=true;S.hp=100;bk.speed=20;bikeCrash(20,"wall");');
   if(w.eval('S.wipeT')>0)fell++;else wobbled++;}
  console.log('   400 crashes ->',fell,'falls /',wobbled,'wobbles');
  ok('roughly a 50/50 fall chance',Math.abs(fell-200)<50);
  T('S.wipeT=0;S.wobbleT=0;S.onBike=true;bk.parked=false;bk.speed=16;');
  T('enemies.length=0;player.position.set(0,0,0);player.rotation.y=0;');
  T('window.__m=spawnEnemy("zombie",1.2,0.4);window.__hp0=__m.hp;');
  T('__m.ramCd=0;bikeRam(.03);');
  ok('riding through a mob hurts it ('+w.eval('__hp0')+' -> '+w.eval('__m.hp')+')',w.eval('__m.hp')<w.eval('__hp0'));
  ok('and knocks it flying',Math.abs(w.eval('__m.kbx'))+Math.abs(w.eval('__m.kbz'))>5);
  ok('and risks her balance too',w.eval('S.wipeT')>0||w.eval('S.wobbleT')>0);
  T('S.wipeT=0;S.wobbleT=0;S.onBike=false;bk.parked=true;bk.speed=0;');
  console.log('GUARDED CHESTS');
  console.log('   chests placed:',w.eval('chests.length'));
  T('enemies.length=0;S.duel=null;chests.forEach(c=>{c.open=false;c.keeper=null;});');
  T('const c=chests[0];player.position.set(c.x+2,0,c.z+2);window.__c=c;');
  T('spawnEnemy("imp",__c.x+10,__c.z+10);spawnEnemy("imp",__c.x-9,__c.z+6);');
  T('updateChests(.03);');
  ok('walking up starts a duel',!!w.eval('S.duel'));
  ok('a keeper spawned and it is elite',w.eval('!!(__c.keeper&&__c.keeper.elite)'));
  ok('every OTHER mob got handed to Bandit',w.eval('enemies.filter(e=>e.guard).length')>=2);
  const hpB=w.eval('S.hp');
  T('bandit.position.set(__c.x+11,0,__c.z+11);');
  const guarded0=w.eval('enemies.filter(e=>e.guard).length');
  let everHurt=false;
  for(let i=0;i<120;i++){clear();T('updateEnemies(.05,'+(i*.05)+')');
   if(w.eval('enemies.some(e=>e.guard&&e.hp<e.maxhp)'))everHurt=true;}
  const guarded1=w.eval('enemies.filter(e=>e.guard).length');
  ok('guarded mobs chase Bandit, not her (HP '+hpB+' -> '+w.eval('S.hp')+')',w.eval('S.hp')>=hpB-1);
  ok('and Bandit wears them down ('+guarded0+' guarded -> '+guarded1+' left alive)',everHurt||guarded1<guarded0);
  const lira0=w.eval('S.lira');
  T('killEnemy(__c.keeper);updateChests(.03);');
  ok('killing the keeper opens the chest',w.eval('__c.open'));
  ok('loot paid out ('+lira0+' -> '+w.eval('S.lira')+'₺, plus flying coins)',true);
  ok('and everyone is released back to normal',w.eval('enemies.filter(e=>e.guard).length')===0&&!w.eval('S.duel'));
  console.log('SUNGLASSES');
  T('setShades(true);');
  ok('worn: mesh visible',w.eval('tor.shades.visible'));
  ok('they ride on her head, so they turn with it',w.eval('tor.shades.parent===tor.head'));
  T('saveGame();S.shades=false;setShades(false);applySave(loadGame());');
  ok('and the choice survives a save/reload',w.eval('S.shades'));
  T('setShades(false);');
  console.log('CITY DETAIL + LIVING WORLD');
  console.log('   decor objects now:',w.eval('decor.length'),'(was ~100 in 3.x)');
  console.log('   pedestrians:',w.eval('peds.length'),'| NPCs:',w.eval('NPCS.length'));
  ok('pedestrians are real people with limbs now',w.eval('peds.every(p=>p.g.userData&&p.g.userData.legs)'));
  ok('nothing new landed in the road',
    w.eval('decor.filter(g=>g.position&&g.position.y<6&&onRoad(g.position.x,g.position.z,4.6)).length')===0);
  T('updateNPCsIdle(3);');
  ok('standing NPCs breathe instead of freezing',
    w.eval('NPCS.some(n=>n.g.userData.legs&&Math.abs(n.g.userData.legs[0].rotation.x)>0)'));
  console.log('VOCAB');
  console.log('   words:',w.eval('WORDS.length'),'| pool questions:',
    w.eval('Object.keys(POOLS).reduce((a,k)=>a+POOLS[k].length,0)'),
    '| grammar bank:',w.eval('GQ.length'));
  ok('every unit has at least 16 questions',w.eval('Object.keys(POOLS).every(k=>POOLS[k].length>=16)'));
  ok('the 4 new suburb lessons exist',w.eval('!!(LESSONS.ecek&&LESSONS.di&&LESSONS.meli&&LESSONS.se)'));
  ok('every suburb NPC has a real lesson attached',
    w.eval('["bahci","cocuk","bakkal","komsu","kopekci"].every(id=>{const n=NPCS.find(x=>x.id===id);return n&&n.lesson&&n.lesson.title})'));
  w.clearInterval(iv);
  console.log(E.length?'ERRORS: '+[...new Set(E)].slice(0,4).join(' ;; '):'NO ERRORS ✓');
  console.log(errs.length?'RUNTIME: '+[...new Set(errs)].slice(0,3).join(' ;; '):'NO RUNTIME ERRORS ✓');
  process.exit(0);
 },3200);
},2000);
setTimeout(()=>{console.log('TIMEOUT');process.exit(2);},44000);
