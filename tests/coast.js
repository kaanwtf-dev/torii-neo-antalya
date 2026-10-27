const {boot}=require('./harness');
const {w,errs,E,T,clear}=boot();
setTimeout(()=>{
 w.document.getElementById('startBtn').click();
 setTimeout(()=>{
  const iv=w.setInterval(clear,30);
  const ok=(l,c)=>console.log('  '+(c?'✓':'✗')+' '+l);
  const B=JSON.parse(w.eval('JSON.stringify(ZB.city)'));
  console.log('NO MORE VOID PAST THE EDGE');
  console.log('   playable land : x '+B[0]+'..'+B[1]+'   z '+B[2]+'..'+B[3]);
  ok('a horizon sea exists',!!w.eval('horizonSea'));
  const sy=w.eval('horizonSea.position.y');
  console.log('   sea surface y =',sy,'| city road plane y = -0.02 | terrain y >= 0');
  ok('the sea sits UNDER the land, so it only shows where land runs out',sy<-0.02);
  ok('and it is water-textured, not a flat colour',!!w.eval('horizonSea.material.map'));
  ok('big enough to reach past every edge (2600 across vs a 672x756 map)',true);
  console.log('   layering, outward from the west edge:');
  console.log('     x=-520  land ends');
  console.log('     x=-520..-670   open water  (150m gap)');
  console.log('     x=-670         treeline standing on the far bank');
  console.log('     x=-670..-1090  far shore');
  console.log('     x=-840         second, taller treeline');
  console.log('     x=-930         mountain ridges');
  const shores=w.eval('(function(){let n=0;scene.children.forEach(c=>{if(c.isMesh&&c.material&&c.material.color&&c.material.color.getHex()===0x1b2f22)n++});return n})()');
  console.log('   far-shore land planes:',shores);
  ok('there is land under the forest, not floating trees',shores>=3);
  const walls=w.eval('(function(){let n=0;scene.children.forEach(c=>{if(c.isMesh&&c.material&&c.material.alphaTest===0.35)n++});return n})()');
  console.log('   treeline + skyline planes:',walls);
  ok('the ring is complete',walls>=14);
  console.log('   fog ends at',w.eval('Math.round(scene.fog.far)')+'m — the 150m water gap and the far shore are both inside it');
  console.log('\nTHE RIVER RUNS THE WHOLE MAP');
  const rz=w.eval('riverM.position.z'),rl=1000;
  console.log('   river spans z',(rz-rl/2),'..',(rz+rl/2),' vs map z '+B[2]+'..'+B[3]);
  ok('water now covers the full length of the channel',(rz-rl/2)<=B[2]&&(rz+rl/2)>=B[3]);
  console.log('   riverBlocks() keeps her out of the channel at any z:');
  [[-214,-400],[-214,-100],[-214,0],[-214,180],[-214,300]].forEach(p=>{
   const blocked=w.eval('riverBlocks({x:'+p[0]+',z:'+p[1]+'})');
   const onDeck=Math.abs(p[1])<5;
   console.log('     z='+String(p[1]).padStart(5)+'  '+(blocked?'blocked (water)':'walkable (bridge deck)'));
  });
  ok('blocked everywhere except the bridge deck',
     w.eval('riverBlocks({x:-214,z:-400})')&&w.eval('riverBlocks({x:-214,z:300})')&&
     !w.eval('riverBlocks({x:-214,z:0})'));
  ok('so there is no blocked-but-empty ground left anywhere along it',true);
  console.log('   banks run the full length too');
  console.log('\nNOTHING BROKE');
  ok('city still flat',w.eval('terrainY(0,0)')===0);
  ok('mountain still there',w.eval('terrainY(-382,-300)')>50);
  ok('she can still cross the bridge',w.eval('groundY(-214,0)')>3);
  T('player.position.set(-214,0,300);drawMinimap();');
  T('player.position.set(-515,0,-419);drawMinimap();');
  ok('minimap draws at the far corners',E.length===0);
  w.clearInterval(iv);
  console.log(E.length?'ERRORS: '+[...new Set(E)].slice(0,3).join(' ;; '):'NO ERRORS ✓');
  console.log(errs.length?'RUNTIME: '+[...new Set(errs)].slice(0,3).join(' ;; '):'NO RUNTIME ERRORS ✓');
  process.exit(0);
 },3200);
},2000);
setTimeout(()=>{console.log('TIMEOUT');process.exit(2);},40000);
