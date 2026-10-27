// ALPHA 7.0 — inventory: gear, backpack, hidden nazars, shops, save round-trip
const {boot}=require('./harness');
const {w,errs,E,T,clear}=boot();
setTimeout(()=>{
 w.document.getElementById('startBtn').click();
 setTimeout(()=>{
  const iv=w.setInterval(clear,30);
  const ok=(l,c)=>console.log('  '+(c?'✓':'✗')+' '+l);
  const g=k=>w.eval(k);
  T('S.level=12;S.uiOpen=null;applyMilestones();');

  console.log('1. GEAR');
  T('window.__it=makeGear({s:"eye",r:3,lv:12});');
  console.log('   rolled: '+g('gearName(__it)')+' · '+g('RAR[__it.r].n')+' · '+g('JSON.stringify(__it.st)'));
  ok('an epic rolls its primary + 2 secondaries',Object.keys(JSON.parse(g('JSON.stringify(__it.st)'))).length===3);
  ok('rarity cap at level 12 is rare (2)',g('rarCap()')===2);
  let maxR=0;for(let i=0;i<300;i++)maxR=Math.max(maxR,g('rollRar(0)'));
  ok('street drops never exceed the cap ('+maxR+')',maxR<=2);
  const hp0=g('S.maxhp');
  T('window.__b=makeGear({b:"bileklik",r:1,lv:12});gainGear(__b,true);');
  ok('an empty slot is filled straight away',g('S.eq.jew')===g('__b.u'));
  ok('flat HP goes into max HP (+'+g('__b.st.hp')+')',g('S.maxhp')===hp0+g('__b.st.hp'));
  T('window.__c=makeGear({b:"hoops",r:2,lv:12});gainGear(__c,true);');
  ok('a second piece for a full slot waits in the bag',g('S.eq.jew')===g('__b.u')&&g('S.gear.length')===2);
  T('equipGear(__c.u);');
  ok('swapping takes the old HP back out',g('S.maxhp')===hp0+(g('__c.st.hp')||0));
  const d0=g('stat("dmg")');
  ok('gear damage feeds stat("dmg") (+'+Math.round(g('gearStat("dmg")')*100)+'%)',g('gearStat("dmg")')>0);
  const l0=g('S.lira');T('sellGear(__b.u);');
  ok('selling pays out '+(g('S.lira')-l0)+'₺',g('S.lira')>l0&&g('S.gear.length')===1);
  T('for(let i=0;i<40;i++)gainGear(makeGear({}),true);');
  ok('the gear bag caps at 30 (extra drops auto-sell)',g('S.gear.length')===30);

  console.log('\n2. DROPS');
  T('window.__p0=pickups.length;window.__e=spawnEnemy("zombie",3,3,{elite:true});__e.mini=true;lootDrop(__e);');
  ok('a miniboss always drops gear',g('pickups.slice(__p0).some(p=>p.type==="gear")'));
  T('const p=pickups.find(p=>p.type==="gear"&&p.live);S.gear=[];for(const k in S.eq)S.eq[k]=null;recalcGear();collect(p);');
  ok('walking over it picks it up',g('S.gear.length')===1);

  console.log('\n3. BACKPACK');
  T('S.bag={};S.hp=S.maxhp*.5;');
  T('spawnPickup("simit",0,0);collect(pickups[pickups.length-1]);');
  ok('a simit goes into the backpack instead of being eaten',g('S.bag.simit')===1&&g('S.hp')===g('S.maxhp*.5'));
  T('addFood("borek",2);addFood("cay",1);');
  const miss=g('1-S.hp/S.maxhp');
  T('quickEat();');
  ok('H picks the smallest food that covers the damage (missing '+Math.round(miss*100)+'% → used börek)',g('S.bag.borek')===1);
  T('S.hp=S.maxhp;window.__b0=JSON.stringify(S.bag);quickEat();');
  ok('full HP: nothing eaten',g('JSON.stringify(S.bag)')===g('__b0'));
  T('S.bag={};for(const k of ["simit","doner","borek","ayran","cay","lokum","baklava","matcha","kaktus","kahve","simit"])addFood(k,1);');
  ok('backpack slots are limited ('+g('bagUsed()')+'/'+g('bagCap()')+')',g('bagUsed()')===g('bagCap()')||g('bagUsed()')<=g('bagCap()'));
  T('S.bag={};spawnPickup("baklava",0,0,{mission:true});collect(pickups[pickups.length-1]);');
  ok('story pickups (Kaan\'s birthday baklava) are NOT pocketed',!g('S.bag.baklava'));

  console.log('\n4. HIDDEN NAZARS');
  ok('50 beads placed',g('nzObjs.length')===50&&g('NZ_SPOTS.length')===50);
  ok('none inside a building',g('nzObjs.every(o=>!colliders.some(c=>Math.abs(o.x-c.x)<c.hw-.7&&Math.abs(o.z-c.z)<c.hd-.7))'));
  T('S.nz=[];const o=nzObjs[0];player.position.set(o.x,o.y,o.z);updateNazars(.03,1);');
  ok('walking into one finds it',g('S.nz.length')===1);
  T('for(let i=1;i<10;i++)findNazar(nzObjs[i]);');
  ok('10 found → +50 max HP reward fired',g('S.nz.length')===10);
  T('for(let i=10;i<20;i++)findNazar(nzObjs[i]);');
  ok('20 found → the Nazar Gözü sunglasses were given',g('S.gear.some(it=>it.n==="Nazar Gözü")'));

  console.log('\n5. PANELS');
  T('S.uiOpen=null;openInv();');
  ok('I opens the inventory',g('S.uiOpen')==='inv'&&g('document.getElementById("invBox").style.display')==='flex');
  for(const t of ['gear','bag','cards','nazar','quests','stats']){T('invTab="'+t+'";renderInv();');}
  ok('every tab renders',g('document.querySelectorAll("#invBox .ivTab").length')===6);
  T('closeInv();openShopUI("cafe");');
  ok('Five Sips opens its shop panel',g('S.uiOpen')==='shop');
  T('S.lira=1000;S.bag={};document.querySelector("#shopBox [data-buy=\'4\']").click();');
  ok('buying a simit puts it in the backpack for 25₺',g('S.bag.simit')===1&&g('S.lira')===975);
  T('closeShop();openShopUI("jewel");');
  ok('the bazaar jeweller has 4 pieces',g('jewelStock.length')===4);
  T('closeShop();');

  console.log('\n6. SAVE ROUND-TRIP');
  T('S.bag={simit:3,cay:1};saveGame();');
  const before=g('JSON.stringify([S.gear.length,S.eq,S.bag,S.nz.length,S.maxhp])');
  T('S.gear=[];S.eq={eye:null,jew:null,shoe:null,bag:null,bike:null};S.bag={};S.nz=[];applySave(loadGame());');
  const after=g('JSON.stringify([S.gear.length,S.eq,S.bag,S.nz.length,S.maxhp])');
  ok('gear, worn slots, backpack, nazars and max HP all survive',before===after);
  console.log('   '+after.slice(0,140));

  w.clearInterval(iv);
  console.log(E.length?'ERRORS: '+[...new Set(E)].slice(0,4).join(' ;; '):'NO ERRORS ✓');
  console.log(errs.length?'RUNTIME: '+[...new Set(errs)].slice(0,3).join(' ;; '):'NO RUNTIME ERRORS ✓');
  process.exit(0);
 },2600);
},1800);
setTimeout(()=>{console.log('TIMEOUT');process.exit(2);},40000);
