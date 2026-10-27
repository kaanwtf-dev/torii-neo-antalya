const {boot}=require('./harness');
const {w,errs,E,T,clear}=boot();
setTimeout(()=>{
 w.document.getElementById('startBtn').click();
 setTimeout(()=>{
  const iv=w.setInterval(clear,30);
  const ok=(l,c)=>console.log('  '+(c?'✓':'✗')+' '+l);
  const txt=()=>w.eval('document.body.textContent')||'';
  console.log('CHESTS OPEN ON [E], NOT ON APPROACH');
  T('S.duel=null;enemies.length=0;chests.forEach(c=>{c.open=false;c.keeper=null;});');
  T('window.__c=chests[0];player.position.set(__c.x+2,groundY(__c.x+2,__c.z+2),__c.z+2);');
  console.log('   standing 2.8m from a chest...');
  for(let i=0;i<60;i++){clear();T('updateChests(.05)');}
  ok('walking up does NOT start the fight',!w.eval('S.duel')&&w.eval('enemies.length')===0);
  ok('the chest is still shut',!w.eval('__c.open'));
  ok('chestNear() finds it',!!w.eval('chestNear()'));
  console.log('   prompt shown:',/KİLİTLİ SANDIK/.test(w.eval('$("prompt")?$("prompt").textContent:"" ')||'')?'yes':'(checked below)');
  console.log('   pressing E:');
  clear();T('interact();');
  ok('opens a dialog rather than jumping straight into a fight',
     /Kilidi kır|Break the lock/i.test(txt())&&!w.eval('S.duel'));
  ok('it warns her what is guarding it',/keeper|bekçi/i.test(txt()));
  ok('and offers a way out',/Şimdi değil|Not yet/i.test(txt()));
  console.log('   choosing "Not yet":');
  T('dlgChoice(1);');
  ok('nothing happens, chest stays shut',!w.eval('S.duel')&&!w.eval('__c.open')&&w.eval('enemies.length')===0);
  console.log('   pressing E again and choosing "Break the lock":');
  clear();T('interact();');T('dlgChoice(0);');
  ok('the duel starts',!!w.eval('S.duel'));
  ok('an elite keeper spawned',w.eval('!!(__c.keeper&&__c.keeper.elite)'));
  ok('its species matches what the chest advertised',w.eval('__c.keeper.type===__c.typ'));
  console.log('   keeper:',w.eval('__c.keeper.type'),'| hp',w.eval('__c.keeper.hp'));
  ok('keepers are hard, not story bosses',
     w.eval('chests.every(c=>c.typ!=="karen"&&c.typ!=="cruze")'));
  console.log('   keeper hp across all 12 chests:',
     w.eval('chests.map(c=>ENEMY[c.typ].hp*3*1.35|0).sort((a,b)=>a-b).join(", ")'));
  console.log('   a second chest cannot be opened mid-duel:');
  T('window.__c2=chests[1];player.position.set(__c2.x+2,groundY(__c2.x+2,__c2.z+2),__c2.z+2);');
  clear();T('interact();');
  ok('refused while a keeper is alive',!w.eval('__c2.keeper'));
  ok('and it says why',/Finish the keeper/i.test(txt()));
  console.log('   killing the keeper opens it:');
  const lira0=w.eval('S.lira');
  T('killEnemy(__c.keeper);updateChests(.03);');
  ok('chest opened',w.eval('__c.open'));
  ok('duel released, everyone back to normal',!w.eval('S.duel')&&w.eval('enemies.filter(e=>e.guard).length')===0);
  console.log('   loot paid ('+lira0+' -> '+w.eval('S.lira')+'₺ plus coins in flight)');
  console.log('   an opened chest is no longer interactable:');
  T('player.position.set(__c.x+2,groundY(__c.x+2,__c.z+2),__c.z+2);');
  ok('chestNear() skips it',!w.eval('(function(){const n=chestNear();return n&&n===__c})()'));
  console.log('   and the other chest works afterwards:');
  T('player.position.set(__c2.x+2,groundY(__c2.x+2,__c2.z+2),__c2.z+2);');
  clear();T('interact();');T('dlgChoice(0);');
  ok('second chest opens fine now',!!w.eval('__c2.keeper'));
  w.clearInterval(iv);
  console.log(E.length?'ERRORS: '+[...new Set(E)].slice(0,3).join(' ;; '):'NO ERRORS ✓');
  console.log(errs.length?'RUNTIME: '+[...new Set(errs)].slice(0,3).join(' ;; '):'NO RUNTIME ERRORS ✓');
  process.exit(0);
 },3000);
},2000);
setTimeout(()=>{console.log('TIMEOUT');process.exit(2);},40000);
