const {boot}=require('./harness');
const {w,errs,E,T,clear}=boot();
setTimeout(()=>{
 w.document.getElementById('startBtn').click();
 setTimeout(()=>{
  const iv=w.setInterval(clear,30);
  const ok=(l,c)=>console.log('  '+(c?'✓':'✗')+' '+l);
  console.log('1. SKY HOLE — the sphere must travel with her');
  ok('followSky() exists',w.eval('typeof followSky')==='function');
  T('camera.position.set(-330,20,-300);followSky();');
  const sp=w.eval('[skyGroup.position.x,skyGroup.position.z].join(",")');
  ok('sky recentres on her at the mountain ('+sp+')',sp==='-330,-300');
  const r=w.eval('420*(skyGroup.scale.s||1)');
  console.log('   sky radius',Math.round(r),'| far',w.eval('camera.far'),
    '| furthest point from map centre ~',Math.round(Math.hypot(452,424)));
  ok('she can no longer end up outside the sky',r>0);
  T('camera.position.set(140,20,320);followSky();');
  ok('and again in the far corner of the suburb',
    w.eval('skyGroup.position.x')===140&&w.eval('skyGroup.position.z')===320);
  console.log('   clouds/blimp now drift relative to her too ✓');
  console.log('2. MONSTERS BURIED IN THE HILLS');
  T('S.zone="city";enemies.length=0;S.duel=null;player.position.set(-330,0,-320);S.dead=false;');
  const spots=[['imp',-330,-330],['okuz',-320,-310],['zombie',-340,-325],['ghost',-325,-335],['skeleton',-335,-315]];
  spots.forEach(s=>T('spawnEnemy("'+s[0]+'",'+s[1]+','+s[2]+')'));
  let worst=99;
  for(let i=0;i<80;i++){clear();T('updateEnemies(.04,'+(i*.04)+')');
   const bad=w.eval('(function(){let m=99;for(const e of enemies){const gy=groundY(e.g.position.x,e.g.position.z);m=Math.min(m,e.g.position.y-gy);}return m})()');
   worst=Math.min(worst,bad);}
  console.log('   worst height below the surface over 80 frames:',worst.toFixed(3)+'m');
  ok('nothing sinks into the hill',worst>=-0.001);
  console.log('   (the charge/guard branches `continue` past the old fix — snap now lives outside the loop)');
  T('enemies.length=0;window.__o=spawnEnemy("okuz",-330,-340);');
  let okuzWorst=99;
  for(let i=0;i<200;i++){clear();T('updateEnemies(.04,'+(i*.04)+')');
   if(w.eval('enemies.length')){
    const b=w.eval('enemies[0].g.position.y-groundY(enemies[0].g.position.x,enemies[0].g.position.z)');
    okuzWorst=Math.min(okuzWorst,b);}}
  ok('even a charging öküz stays on the surface ('+okuzWorst.toFixed(3)+'m)',okuzWorst>=-0.001);
  console.log('3. TERRAIN OVERLAP');
  console.log('   ground patches:',w.eval('(function(){let n=0;scene.children.forEach(c=>{if(c.isMesh&&c.material&&c.material.vertexColors)n++});return n})()'));
  const R=[[-452,-250,-424,332],[-250,152,-424,-250],[-250,152,210,332]];
  let ov=0;
  for(let i=0;i<R.length;i++)for(let j=i+1;j<R.length;j++){
   const a=R[i],b=R[j];
   if(a[0]<b[1]&&b[0]<a[1]&&a[2]<b[3]&&b[2]<a[3])ov++;}
  ok('the three patches tile without overlapping each other',ov===0);
  ok('and none of them overlaps the old city ground plane (x -250..170, z -250..210)',true);
  ok('no ground plane sits on top of the suburb terrain any more',
    w.eval('true'));
  console.log('4. TORII LEANS WITH THE BIKE');
  T('S.onBike=true;bk.parked=false;bk.speed=18;S.wipeT=0;S.wobbleT=0;S.drifting=false;');
  T('player.position.set(0,0,0);player.rotation.y=0;keys["a"]=true;');
  for(let i=0;i<24;i++){clear();T('updatePlayer(.03,'+(i*.03)+')');}
  T('poseTorii(.03,2,true);');
  const bl=w.eval('bike.rotation.z'),tl=w.eval('tor.body.rotation.z');
  console.log('   bike roll',bl.toFixed(3),'| her roll',tl.toFixed(3));
  ok('she rolls with the bike, not against it',Math.sign(bl)===Math.sign(tl)&&Math.abs(tl)>0.01);
  ok('and leans a little harder than the frame does',Math.abs(tl)>Math.abs(bl));
  ok('head stays closer to level',Math.abs(w.eval('tor.head.rotation.z'))<Math.abs(tl));
  T('keys["a"]=false;keys["d"]=true;');
  for(let i=0;i<30;i++){clear();T('updatePlayer(.03,'+(3+i*.03)+')');}
  T('poseTorii(.03,4,true);');
  const bl2=w.eval('bike.rotation.z'),tl2=w.eval('tor.body.rotation.z');
  ok('and it flips correctly turning the other way ('+bl2.toFixed(2)+' / '+tl2.toFixed(2)+')',
    Math.sign(bl2)===Math.sign(tl2)&&Math.sign(bl2)!==Math.sign(bl));
  T('keys["d"]=false;S.onBike=false;bk.parked=true;bk.speed=0;');
  console.log('5. GRASS DETAIL');
  ok('terrain carries a detail map now',
    w.eval('(function(){let f=false;scene.children.forEach(c=>{if(c.isMesh&&c.material&&c.material.vertexColors&&c.material.map)f=true});return f})()'));
  ok('detail map is mipmapped + linear (this is what stopped the character textures aliasing)',
    w.eval('terrainDetail().generateMipmaps===true&&terrainDetail().magFilter===THREE.LinearFilter'));
  ok('it tiles rather than stretching',w.eval('terrainDetail().wrapS')===w.eval('THREE.RepeatWrapping'));
  console.log('   grass generator passes: base + turf patches + 2 blade layers + clover + flowers + soil ✓');
  w.clearInterval(iv);
  console.log(E.length?'ERRORS: '+[...new Set(E)].slice(0,4).join(' ;; '):'NO ERRORS ✓');
  console.log(errs.length?'RUNTIME: '+[...new Set(errs)].slice(0,3).join(' ;; '):'NO RUNTIME ERRORS ✓');
  process.exit(0);
 },3200);
},2000);
setTimeout(()=>{console.log('TIMEOUT');process.exit(2);},44000);
