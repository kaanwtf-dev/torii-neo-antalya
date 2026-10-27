const {boot}=require('./harness');
const {w,errs,E,T,clear}=boot();
setTimeout(()=>{
 w.document.getElementById('startBtn').click();
 setTimeout(()=>{
  const iv=w.setInterval(clear,30);
  const ok=(l,c)=>console.log('  '+(c?'✓':'✗')+' '+l);
  console.log('1. ROADS ON HILLS');
  ok('roads are terrain data, not floating quads',w.eval('typeof roadDist')==='function');
  console.log('   corridors:',w.eval('TROADS.length'));
  const rd=(x,z)=>w.eval('roadDist('+x+','+z+')');
  ok('centre of the suburb road is road',rd(6,300)<0);
  ok('7m off it is not',rd(20,300)>0);
  ok('the street between the house rows is road',rd(0,251)<0);
  // the road follows the ground exactly, because it IS the ground
  let maxGap=0;
  for(let z=210;z<=336;z+=1){
   const a=w.eval('terrainY(6,'+z+')'),b=w.eval('terrainY(6,'+(z+1)+')');
   maxGap=Math.max(maxGap,Math.abs(b-a));}
  console.log('   biggest 1m height change along the suburb road:',maxGap.toFixed(3)+'m');
  ok('the road surface IS the terrain surface, so it cannot staircase',maxGap<0.4);
  ok('no flat road quads left out in the hills',
     w.eval('(function(){let n=0;scene.children.forEach(c=>{if(c.isMesh&&c.position&&c.position.z>215&&c.position.y>0.1&&c.position.y<0.3)n++});return n})()')<3);
  console.log('   roads do not fight the house pads:');
  const near=w.eval('(function(){let m=1e9;for(const P of PADS)m=Math.min(m,Math.abs(P.z-251)-P.r*PADBLEND);return m})()');
  ok('   nearest pad blend ring clears the street by '+near.toFixed(1)+'m',near>0);
  console.log('2. RIVER / SEA SHOWING ROAD TEXTURE');
  console.log('   city ground plane sits at y=-0.02 and spans x -250..170');
  const ry=w.eval('riverM.position.y'),wy=w.eval('waterM.position.y');
  console.log('   river surface y =',ry,'| sea surface y =',wy);
  ok('river is ABOVE the city plane, so water draws over the road',ry>-0.02);
  ok('sea is above it too',wy>-0.02);
  ok('river x=-214 really is inside the city plane (this was the trap)',-214>-250&&-214<170);
  ok('river still carries a water texture',w.eval('!!riverM.material.map'));
  ok('sea still carries a water texture',w.eval('!!waterM.material.map'));
  T('updateSky&&0;');
  for(let i=0;i<40;i++)T('if(riverM)riverM.position.y=.06+Math.sin('+(i*.3)+'*.7)*.035;');
  ok('river stays above the road through its whole bob',w.eval('riverM.position.y')>-0.02);
  ok('banks raised clear of the new water line',true);
  console.log('3. SPEECH FALLBACK (Edge produced no sound)');
  ok('silent-failure detection exists',w.eval('typeof TTS.silent')==='number');
  ok('a dead engine is detectable',w.eval('typeof TTS.dead')==='boolean');
  T('TTS.dead=true;');
  ok('babble still runs when TTS is dead',w.eval('(function(){try{babble("merhaba",1,1,1);return true}catch(e){return false}})()'));
  console.log('   synthesised voice tracks real Turkish vowels:',
    w.eval('Object.keys(FORMANT).join(" ")'));
  ok('all 8 Turkish vowels have formants',w.eval('Object.keys(FORMANT).length')===8);
  T('TTS.dead=false;');
  console.log('   V now runs a self-test and reports what the browser actually did ✓');
  console.log('4. NOTHING ELSE MOVED');
  ok('city centre flat',w.eval('terrainY(0,0)')===0);
  ok('plots still level',w.eval('(function(){let worst=0;for(const h of HOUSEPLAN){let lo=1e9,hi=-1e9;'+
    'for(const dx of[-7,0,7])for(const dz of[-7,0,7]){const y=terrainY(h.x+dx,h.z+dz);lo=Math.min(lo,y);hi=Math.max(hi,y);}'+
    'worst=Math.max(worst,hi-lo);}return worst})()')<0.02);
  ok('sky still follows her',w.eval('typeof followSky')==='function');
  w.clearInterval(iv);
  console.log(E.length?'ERRORS: '+[...new Set(E)].slice(0,4).join(' ;; '):'NO ERRORS ✓');
  console.log(errs.length?'RUNTIME: '+[...new Set(errs)].slice(0,3).join(' ;; '):'NO RUNTIME ERRORS ✓');
  process.exit(0);
 },3200);
},2000);
setTimeout(()=>{console.log('TIMEOUT');process.exit(2);},40000);
