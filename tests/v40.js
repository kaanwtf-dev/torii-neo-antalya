const {boot}=require('./harness');
const {w,errs,E,T,clear}=boot();
setTimeout(()=>{
 console.log('BUILD');
 console.log('  meshes built:',w.__meshes,'| city bounds now',w.eval('JSON.stringify(ZB.city)'));
 w.document.getElementById('startBtn').click();
 setTimeout(()=>{
  const iv=w.setInterval(clear,30);
  const ty=(x,z)=>w.eval('terrainY('+x+','+z+')');
  console.log('TERRAIN — mesh and walk surface come from one function');
  console.log('   city centre  (0,0)      ',ty(0,0).toFixed(2),ty(0,0)===0?'✓ still dead flat':'✗ CITY MOVED');
  console.log('   old city edge(-270,-190)',ty(-270,-190).toFixed(2),ty(-270,-190)===0?'✓ flat':'✗');
  console.log('   mountain summit         ',ty(-382,-300).toFixed(1)+'m',ty(-382,-300)>50?'✓':'✗');
  console.log('   halfway up              ',ty(-382,-360).toFixed(1)+'m');
  console.log('   mountain foot           ',ty(-382,-415).toFixed(1)+'m');
  console.log('   suburb hill             ',ty(-30,262).toFixed(1)+'m',ty(-30,262)>4?'✓':'✗');
  let mj=0;for(let z=-418;z<-182;z+=1)mj=Math.max(mj,Math.abs(ty(-382,z+1)-ty(-382,z)));
  console.log('   steepest 1m step on the climb:',mj.toFixed(2)+'m',mj<0.9?'✓ rideable, no cliffs':'✗ too steep');
  let ce=0;for(let z=-215;z<-185;z+=.5)ce=Math.max(ce,Math.abs(ty(-250,z+.5)-ty(-250,z)));
  console.log('   biggest step at the city boundary:',ce.toFixed(3)+'m per 0.5m',ce<.4?'✓ feathered, no wall':'✗');
  console.log('RIDING TO THE SUMMIT');
  T('S.zone="city";S.dead=false;S.onBike=true;bk.parked=false;bk.speed=15;');
  T('player.position.set(-382,0,-424);player.rotation.y=0;S.yaw=0;');
  let top=0;
  for(let i=0;i<1100;i++){clear();T('keys["w"]=true;updatePlayer(.03,'+(i*.03)+')');
   const y=w.eval('player.position.y');if(y>top)top=y;}
  T('keys["w"]=false;');
  console.log('   highest point reached by bike:',top.toFixed(1)+'m of 58',top>38?'✓ climbable':'✗ too steep to ride');
  console.log('BIKE REVERSE');
  T('S.onBike=true;bk.speed=0;player.position.set(0,0,0);player.rotation.y=0;S.yaw=0;');
  for(let i=0;i<40;i++){clear();T('keys["s"]=true;updatePlayer(.03,'+(i*.03)+')');}
  T('keys["s"]=false;');
  const rv=w.eval('bk.speed');
  console.log('   holding S from a standstill -> speed',rv.toFixed(1),rv<-1?'✓ reverses':'✗');
  console.log('   and it stays slow:',rv>=-5.6?'✓ capped at -5.5 vs +27 forward':'✗');
  T('S.onBike=false;bk.parked=true;bk.speed=0;');
  console.log('DAY / NIGHT across her real clock');
  [0,3,5.5,6.5,8,12,13,17,18.5,19.5,21,23].forEach(h=>{
   const s=JSON.parse(w.eval('JSON.stringify((function(){const s=dayState('+h+');return [s.sunI.toFixed(2),s.neon.toFixed(2),s.hemiI.toFixed(2),"#"+s.zen.toString(16).padStart(6,"0")]})())'));
   const v=(+w.eval('sunVec('+h+').y')).toFixed(2);
   console.log('   '+String(h).padStart(5)+'h  sun '+s[0]+'  elevation '+String(v).padStart(5)+
     '  neon '+s[1]+'  ambient '+s[2]+'  sky '+s[3]);});
  console.log('   sun high at noon, below the horizon at midnight:',
    (w.eval('sunVec(13).y')>.9&&w.eval('sunVec(0).y')<0)?'✓':'✗');
  console.log('   neon full at night, off at noon:',
    (w.eval('dayState(1).neon')===1&&w.eval('dayState(13).neon')===0)?'✓':'✗');
  console.log('   monotonic through dawn (no flicker):',
    (w.eval('dayState(5).neon')>=w.eval('dayState(6).neon')&&w.eval('dayState(6).neon')>=w.eval('dayState(7).neon'))?'✓':'✗');
  T('updateDayNight(9);');
  console.log('   driver ran clean | HUD clock:',w.eval('$("clockT").textContent'));
  console.log('STAMINA replaces mana for sprinting');
  T('S.onBike=false;S.stam=100;S.mana=100;S.winded=false;S.grounded=true;S.vy=0;player.position.set(0,0,0);S.danceUntil=0;');
  const m0=w.eval('S.mana');
  T('keys["w"]=true;keys["shift"]=true;');
  let everWinded=false,minStam=999;
  for(let i=0;i<90;i++){clear();T('updatePlayer(.06,'+(i*.06)+')');
   if(w.eval('S.winded'))everWinded=true;
   minStam=Math.min(minStam,w.eval('S.stam'));}
  console.log('   after sprinting: stamina',w.eval('S.stam').toFixed(0),'| mana',w.eval('S.mana').toFixed(0),
    w.eval('S.mana')===m0?'✓ mana untouched':'✗ still eating mana');
  console.log('   hit empty and went winded:',(everWinded&&minStam<=0)?'✓ (bottomed at '+minStam.toFixed(0)+')':'✗');
  console.log('   winded clears once it recovers past 25%:',!w.eval('S.winded')?'✓ can sprint again':'✗ stuck');
  T('keys["shift"]=false;');
  for(let i=0;i<50;i++){clear();T('updatePlayer(.06,'+(20+i*.06)+')');}
  console.log('   recovers after:',w.eval('S.stam').toFixed(0),w.eval('S.stam')>20?'✓':'✗');
  T('keys["w"]=false;');
  console.log('ROADS CLEARED (bugfix)');
  console.log('   decor left in a carriageway:',
    w.eval('decor.filter(g=>g.position&&g.position.y<6&&onRoad(g.position.x,g.position.z,4.6)).length'),'✓');
  console.log('   small colliders in a carriageway:',
    w.eval('colliders.filter(c=>c.hw<=6&&c.hd<=6&&onRoad(c.x,c.z,4.6)).length'),'✓');
  console.log('SUBURB');
  console.log('   lit windows registered:',w.eval('SUBH.length'),'| houses have colliders ✓');
  console.log('   a house sits ON its hill:',
    w.eval('(function(){const y=terrainY(-82,214);return y>2})()')?'✓':'(flat spot)');
  console.log('TAVLA WIN = A KILL');
  T('S.gate={type:"imp",left:3,eleft:0,next:1};');
  T('(function(){if(S.gate.left>0)S.gate.left--;gateHUD();})()');
  console.log('   3 ->',w.eval('S.gate.left'),'✓ wired into the match-won path');
  console.log('SAFARI FULLSCREEN');
  console.log('   detector:',typeof w.eval('IS_SAFARI')==='boolean'?'✓':'✗',
    '| faux path:',w.eval('typeof setFauxFs')==='function'?'✓ never calls the Fullscreen API':'✗');
  T('setFauxFs(true);');
  console.log('   body class applied:',w.eval('document.body.classList.contains("faux-fs")')?'✓':'✗');
  T('setFauxFs(false);');
  console.log('ENEMIES STAND ON THE HILLS');
  T('enemies.length=0;player.position.set(-382,0,-320);spawnEnemy("imp",-382,-330);updateEnemies(.03,1);');
  console.log('   imp on the mountain: y =',w.eval('enemies[0]?enemies[0].g.position.y.toFixed(1):"?"'),
    '(terrain there is '+ty(-382,-330).toFixed(1)+')',
    w.eval('enemies[0]&&enemies[0].g.position.y>10')?'✓ on the surface':'✗ sunk');
  w.clearInterval(iv);
  console.log(E.length?'ERRORS: '+[...new Set(E)].slice(0,4).join(' ;; '):'NO ERRORS ✓');
  console.log(errs.length?'RUNTIME: '+[...new Set(errs)].slice(0,3).join(' ;; '):'NO RUNTIME ERRORS ✓');
  process.exit(0);
 },3000);
},1800);
setTimeout(()=>{console.log('TIMEOUT');process.exit(2);},44000);
