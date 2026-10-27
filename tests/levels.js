// ALPHA 7.0 — Levels 2.0: curve, migration of an old save, perk cards, milestones, mob levels
const {boot}=require('./harness');
const {w,errs,E,T,clear}=boot();
setTimeout(()=>{
 w.document.getElementById('startBtn').click();
 setTimeout(()=>{
  const iv=w.setInterval(clear,30);
  const ok=(l,c)=>console.log('  '+(c?'✓':'✗')+' '+l);
  console.log('1. THE CURVE');
  const cur=[1,2,5,10,15,20,30].map(L=>L+':'+w.eval('xpFor('+L+')'));
  console.log('   need per level  '+cur.join('  '));
  const old=L=>Math.round(60*Math.pow(L,1.35));
  ok('steeper than the old curve from level 5 on',[5,10,20,30].every(L=>w.eval('xpFor('+L+')')>old(L)));
  ok('always rising',[...Array(40)].every((_,i)=>w.eval('xpFor('+(i+2)+')')>w.eval('xpFor('+(i+1)+')')));

  console.log('\n2. HER OLD SAVE MIGRATES — nothing lost');
  const oldSave={v:3,lvl:12,xp:860,need:old(12),mh:260,mm:155,int:3,lira:4321,ammo:9,
   weap:['katana','terlik'],words:['ev','su'],kills:410,next:9,mid:'cam',unit:9,ul:1,mastered:{1:true}};
  T('localStorage.setItem("torii_save",'+JSON.stringify(JSON.stringify(oldSave))+');applySave(loadGame());');
  const g=k=>w.eval(k);
  console.log('   level '+g('S.level')+' · xp '+g('S.xp')+'/'+g('S.xpNeed')+' · maxHP '+g('S.maxhp')+
   ' · mana '+g('S.maxmana')+' · stamina '+g('S.maxStam')+' · cards '+g('S.perkPicks'));
  ok('still level 12',g('S.level')===12);
  ok('same fraction of the bar ('+(860/old(12)).toFixed(3)+' → '+(g('S.xp')/g('S.xpNeed')).toFixed(3)+')',
   Math.abs(860/old(12)-g('S.xp')/g('S.xpNeed'))<.01);
  ok('lira, kills, unit and words untouched',g('S.lira')===4321&&g('S.kills')===410&&g('S.unit')===9&&g('S.wordsCount')>=2);
  ok('back-paid stats: HP 260→'+g('S.maxhp')+', mana 155→'+g('S.maxmana'),g('S.maxhp')===260+22&&g('S.maxmana')===155+33);
  ok('stamina grown to '+g('S.maxStam'),g('S.maxStam')===122);
  ok('11 unopened perk cards (one per level she earned)',g('S.perkPicks')===11);
  ok('milestones 5 and 10 recorded silently',g('!!S.msDone[5]&&!!S.msDone[10]&&!S.msDone[15]'));
  ok('level-10 skill [6] unlocked, level-25 skill [7] still locked',g('!SKILLS[5].lock&&SKILLS[6].lock'));
  ok('backpack grew at level 5 (cap '+g('S.bagCap')+')',g('S.bagCap')===12);
  T('saveGame();');
  const sv=JSON.parse(g('localStorage.getItem("torii_save")'));
  ok('saved as a 7.0 save (lvlv 2)',sv.lvlv===2&&sv.pp===11);
  T('applySave(loadGame());');
  ok('reloading a 7.0 save does NOT migrate twice (cards '+g('S.perkPicks')+', HP '+g('S.maxhp')+')',
   g('S.perkPicks')===11&&g('S.maxhp')===282);

  console.log('\n3. OPENING PERK CARDS');
  T('S.uiOpen=null;openPerks();');
  ok('the card panel opens with 3 cards',g('S.uiOpen')==='perk'&&g('perkHand.length')===3);
  ok('first time: it explains itself',g('document.querySelector("#perkBox .pkIntro")!==null'));
  const first=g('perkHand[0].id');
  T('pickPerk(0);');
  ok('picking one ranks it up ('+first+' = '+g('S.perks["'+first+'"]')+') and uses a card ('+g('S.perkPicks')+' left)',
   g('S.perks["'+first+'"]')===1&&g('S.perkPicks')===10);
  ok('the next pack opens straight away',g('S.uiOpen')==='perk');
  T('closePerks();');
  ok('SONRA (later) keeps the rest',g('S.uiOpen')===null&&g('S.perkPicks')===10);
  const hp0=g('S.maxhp');T('takePerk("dayanikli");');
  ok('DAYANIKLI: +40 max HP at once',g('S.maxhp')===hp0+40);
  const st0=g('S.maxStam');T('takePerk("maraton");');
  ok('MARATON: +25 max stamina',g('S.maxStam')===st0+25);
  T('S.perks.nefes2=1;S.perks.nefes2=5;');
  ok('a maxed perk is never offered again',[...Array(30)].every(()=>{T('window.__h=drawPerks().map(p=>p.id)');
   return !g('__h.includes("nefes2")');}));

  console.log('\n4. A REAL LEVEL UP');
  T('S.uiOpen=null;S.perkPicks=0;S.level=4;S.xpNeed=xpFor(4);S.xp=0;S.maxhp=200;S.maxmana=100;S.maxStam=110;S.msDone={};');
  T('gainXP(99999);');
  console.log('   → level '+g('S.level')+', cards '+g('S.perkPicks')+', maxHP '+g('S.maxhp'));
  ok('levels gained, one card per level',g('S.level')>5&&g('S.perkPicks')===g('S.level')-4);
  ok('level 5 milestone fired',g('!!S.msDone[5]'));
  ok('the card panel waits for the level-up show',g('S.perkAutoT')>g('now()'));

  console.log('\n5. FAINTING NO LONGER COSTS A LEVEL');
  T('S.level=9;S.xp=3;S.xpNeed=xpFor(9);S.lira=1000;S.dead=false;S.hp=10;S.uiOpen=null;');
  T('die();');
  ok('still level 9, lost lira '+(1000-g('S.lira'))+', xp now '+g('S.xp'),g('S.level')===9&&g('S.lira')===900&&g('S.xp')===0);
  T('S.dead=false;');

  console.log('\n6. MONSTERS HAVE LEVELS');
  T('S.level=10;S.uiOpen=null;S.zone="city";');
  T('window.__e=spawnEnemy("zombie",0,0);');
  console.log('   zombie at her level 10 → Lv '+g('__e.lv')+', HP '+g('__e.maxhp')+' (base 60), dmg '+g('__e.dmg')+' (base 12)');
  ok('level tag attached',!!g('__e.tag'));
  ok('scaled HP and damage',g('__e.maxhp')>60&&g('__e.dmg')>12);
  T('window.__m=spawnEnemy("imp",MTN.x,MTN.z);');
  ok('Mount Işıkdağ runs hotter (Lv '+g('__m.lv')+')',g('__m.lv')>=11);
  ok('damage grows with level: ×'+g('stat("dmg")').toFixed(2)+' at 10',g('stat("dmg")')>1.2);

  w.clearInterval(iv);
  console.log(E.length?'ERRORS: '+[...new Set(E)].slice(0,4).join(' ;; '):'NO ERRORS ✓');
  console.log(errs.length?'RUNTIME: '+[...new Set(errs)].slice(0,3).join(' ;; '):'NO RUNTIME ERRORS ✓');
  process.exit(0);
 },2600);
},1800);
setTimeout(()=>{console.log('TIMEOUT');process.exit(2);},40000);
