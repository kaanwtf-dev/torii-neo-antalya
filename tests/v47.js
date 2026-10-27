const {boot}=require('./harness');
const {w,errs,E,T,clear}=boot();
setTimeout(()=>{
 w.document.getElementById('startBtn').click();
 setTimeout(()=>{
  const iv=w.setInterval(clear,30);
  const ok=(l,c)=>console.log('  '+(c?'✓':'✗')+' '+l);
  console.log('ORDERING A SPECIFIC SPECIES');
  console.log('   species on offer:',w.eval('HIRE.length'));
  console.log('   '+w.eval('HIRE.map(h=>h.e+(h.k||"mixed")+" x"+h.m).join("  ")'));
  ok('every listed species is a real mob (or the mixed option)',
     w.eval('HIRE.every(h=>h.k===null||!!ENEMY[h.k])'));
  ok('mixed is the cheapest',w.eval('HIRE[0].m')===Math.min(...JSON.parse(w.eval('JSON.stringify(HIRE.map(h=>h.m))')))); 
  console.log('   price of 5 monsters by species:');
  ['imp','ghost','mummy','driver',null].forEach(k=>{
   const p=w.eval('hirePrice(CONTRACTS[4],hireOf('+JSON.stringify(k)+'))');
   console.log('     5 × '+String(k||'mixed').padEnd(9)+' = '+p+'₺');});
  ok('a ghost order costs more than an imp order',
     w.eval('hirePrice(CONTRACTS[4],hireOf("ghost"))')>w.eval('hirePrice(CONTRACTS[4],hireOf("imp"))'));
  ok('it is a finder\'s fee with NO separate payout (removed in 4.8)',
     w.eval('typeof hirePay')==='undefined'&&w.eval('typeof hireXp')==='undefined');
  ok('fees are modest, not job prices',
     w.eval('hirePrice(CONTRACTS[4],hireOf("driver"))')<3500);
  console.log('   THE ACTUAL USE CASE — a gate demanding 5 ghosts:');
  T('S.gate={next:5,type:"ghost",left:5,eleft:0};S.lira=99999;S.bounty=null;enemies.length=0;');
  T('player.position.set(-24,6,-19);');
  T('pickSpecies(0);');
  const first=w.eval('$("dlg").textContent||""');
  ok('the dialog names what the hunt needs',/ghost/i.test(first));
  ok('and marks it in the list',/⚑/.test(w.eval('document.body.innerHTML')));
  T('S.bounty=null;startBounty(CONTRACTS[4],hireOf("ghost"));');
  console.log('   contract:',w.eval('S.bounty.total'),'×',w.eval('S.bounty.tag'),'at',w.eval('S.bounty.place'));
  ok('the contract remembers the species',w.eval('S.bounty.type')==='ghost');
  T('player.position.set(S.bounty.x+8,0,S.bounty.z+8);updateBounty(.03);');
  console.log('   spawned:',w.eval('enemies.map(e=>e.type).join(", ")'));
  ok('ALL five are ghosts, not a mixed bag',
     w.eval('enemies.length')===5&&w.eval('enemies.every(e=>e.type==="ghost")'));
  T('for(let i=0;i<150;i++)updateCoins(.05);');
  const gate0=w.eval('S.gate.left');
  T('while(enemies.length)killEnemy(enemies[0]);updateBounty(.03);');
  ok('killing them counts toward the gate ('+gate0+' -> '+w.eval('S.gate?S.gate.left:0')+')',
     !w.eval('S.gate')||w.eval('S.gate.left')<gate0);
  ok('contract cleared',!w.eval('S.bounty'));
  console.log('   mixed orders still work:');
  T('S.gate=null;S.bounty=null;enemies.length=0;S.lira=99999;startBounty(CONTRACTS[2],hireOf(null));');
  T('player.position.set(S.bounty.x+8,0,S.bounty.z+8);updateBounty(.03);');
  ok('3 spawned, any species',w.eval('enemies.length')===3);
  console.log('   species survives a save/reload:');
  T('S.bounty=null;enemies.length=0;startBounty(CONTRACTS[3],hireOf("okuz"));saveGame();');
  T('S.bounty=null;applySave(loadGame());');
  ok('   restored as '+w.eval('S.bounty&&S.bounty.tag'),w.eval('S.bounty&&S.bounty.type')==='okuz');
  T('enemies.length=0;player.position.set(S.bounty.x+8,0,S.bounty.z+8);updateBounty(.03);');
  ok('   and still spawns öküz after the reload',w.eval('enemies.every(e=>e.type==="okuz")')&&w.eval('enemies.length')===4);
  console.log('ONE FILE');
  ok('version banner matches the newest patch entry',
     w.eval('GAME_VER').indexOf(w.eval('PATCHES[0].v'))===0);
  w.clearInterval(iv);
  console.log(E.length?'ERRORS: '+[...new Set(E)].slice(0,4).join(' ;; '):'NO ERRORS ✓');
  console.log(errs.length?'RUNTIME: '+[...new Set(errs)].slice(0,3).join(' ;; '):'NO RUNTIME ERRORS ✓');
  process.exit(0);
 },3200);
},2000);
setTimeout(()=>{console.log('TIMEOUT');process.exit(2);},40000);
