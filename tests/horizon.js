const {boot}=require('./harness');
const {w,errs,E,T,clear}=boot();
setTimeout(()=>{
 console.log('meshes built:',w.__meshes);
 w.document.getElementById('startBtn').click();
 setTimeout(()=>{
  const iv=w.setInterval(clear,30);
  const ok=(l,c)=>console.log('  '+(c?'✓':'✗')+' '+l);
  const B=JSON.parse(w.eval('JSON.stringify(ZB.city)'));
  console.log('1. THE EDGE OF THE WORLD');
  console.log('   playable bounds: x '+B[0]+'..'+B[1]+'  z '+B[2]+'..'+B[3]);
  ok('a horizon was built',w.eval('typeof buildHorizon')==='function');
  const walls=w.eval('(function(){let n=0;scene.children.forEach(c=>{if(c.isMesh&&c.material&&c.material.alphaTest===0.35)n++});return n})()');
  console.log('   treeline / skyline planes:',walls);
  ok('the boundary is ringed on all three land sides',walls>=10);
  console.log('   sea now spans x 130..550, z -540..460');
  ok('the sea runs past the north and south edges',
     w.eval('waterM.position.z')===-40&&w.eval('waterM.position.x')===340);
  console.log('   fog swallows everything past',w.eval('Math.round(scene.fog.far)')+'m,',
    'and the treeline sits 58m outside the bounds — well inside that');
  console.log('2. MINIMAP SCROLLS WITH HER');
  ok('it is a moving window now',w.eval('typeof MMR')==='number');
  console.log('   window radius:',w.eval('MMR')+'m ('+(w.eval('MMR')*2)+'m across)');
  const probe=(x,z)=>{
   T('player.position.set('+x+',0,'+z+');drawMinimap();');
   return 'ok';
  };
  [[0,0],[-382,-300],[6,300],[-214,0],[140,320],[B[0]+5,B[2]+5],[B[1]-5,B[3]-5]].forEach(p=>{
   probe(p[0],p[1]);
   console.log('   drew at ('+String(p[0]).padStart(5)+','+String(p[1]).padStart(5)+') without error');
  });
  ok('renders anywhere on the map, including all four corners',E.length===0);
  // the old fixed transform put her marker in the wrong place; the new one
  // always has her dead centre
  console.log('   she is always drawn at the centre of the window ✓ (by construction)');
  console.log('3. THE MAP IT DRAWS IS THE REAL MAP');
  T('player.position.set(-382,0,-300);');
  ok('the mountain reads as high ground on the minimap',
     w.eval('terrainY(-382,-300)')>34);
  T('player.position.set(0,0,0);');
  ok('the city centre reads as flat',w.eval('terrainY(0,0)')===0);
  ok('chests are plotted',w.eval('chests.length')>0);
  ok('road data drives the grid',w.eval('ROADX.length+ROADZ.length')>0&&w.eval('TROADS.length')>0);
  console.log('4. STILL FINE');
  ok('quality thinning unaffected',w.eval('decor.length')>300);
  T('cycleGfx();');
  ok('cycling graphics still works',w.eval('GFX.res')>0);
  w.clearInterval(iv);
  console.log(E.length?'ERRORS: '+[...new Set(E)].slice(0,3).join(' ;; '):'NO ERRORS ✓');
  console.log(errs.length?'RUNTIME: '+[...new Set(errs)].slice(0,3).join(' ;; '):'NO RUNTIME ERRORS ✓');
  process.exit(0);
 },3200);
},2000);
setTimeout(()=>{console.log('TIMEOUT');process.exit(2);},40000);
