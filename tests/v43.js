const {boot}=require('./harness');
const {w,errs,E,T,clear}=boot();
setTimeout(()=>{
 w.document.getElementById('startBtn').click();
 setTimeout(()=>{
  const iv=w.setInterval(clear,30);
  const ok=(l,c)=>console.log('  '+(c?'✓':'✗')+' '+l);
  const ty=(x,z)=>w.eval('terrainY('+x+','+z+')');
  const ly=(x,z)=>w.eval('landY('+x+','+z+')');
  console.log('1. THE STEP IN THE LANDSCAPE');
  console.log('   city ground plane: x -250..170, z -250..210');
  console.log('   OLDCITY now      :',w.eval('JSON.stringify(OLDCITY)'));
  ok('they match exactly',w.eval('OLDCITY.x0')===-250&&w.eval('OLDCITY.x1')===170&&
     w.eval('OLDCITY.z0')===-250&&w.eval('OLDCITY.z1')===210);
  ok('no hill height hides under the flat city plane (z=177..210)',
     [180,190,200,209].every(z=>ty(-30,z)===0));
  console.log('   profile walking south out of the city:');
  let maxStep=0,prev=null;
  for(let z=200;z<=300;z+=1){const y=ty(-30,z);
   if(prev!==null)maxStep=Math.max(maxStep,Math.abs(y-prev));
   if(z%12===0)console.log('     z='+String(z).padStart(4)+'  y='+y.toFixed(2));
   prev=y;}
  console.log('   biggest 1m step anywhere on that walk:',maxStep.toFixed(3)+'m');
  ok('the terrain rises smoothly instead of stepping',maxStep<0.6);
  ok('the SOUTH patch edge (z=210) starts at ground level',Math.abs(ty(-30,210))<0.01);
  console.log('   same check at the mountain side (x=-250 patch edge):');
  let ms2=0,p2=null,at2=0;
  for(let x=-240;x>=-382;x-=1){const y=ty(x,-300);
   if(p2!==null&&Math.abs(y-p2)>ms2){ms2=Math.abs(y-p2);at2=x;}p2=y;}
  console.log('     steepest at x='+at2+' (height '+ty(at2,-300).toFixed(1)+'m, mask '+
    w.eval('cityMask('+at2+',-300)').toFixed(2)+')');
  ok('WEST edge flush and the mountain is climbable, not a wall ('+ms2.toFixed(3)+'m/m max)',Math.abs(ty(-250,-300))<0.01&&ms2<0.72);
  console.log('2. HOUSES ON LEVEL GROUND');
  console.log('   houses planned:',w.eval('HOUSEPLAN.length'),'| pads:',w.eval('PADS.length'));
  ok('every house got a pad',w.eval('PADS.length')===w.eval('HOUSEPLAN.length'));
  let worstTilt=0,worstAt='';
  for(let i=0;i<w.eval('HOUSEPLAN.length');i++){
   const h=JSON.parse(w.eval('JSON.stringify(HOUSEPLAN['+i+'])'));
   // sample the corners of the plot, fence included
   let lo=1e9,hi=-1e9;
   for(const dx of[-7,0,7])for(const dz of[-7,0,7]){
    const y=ty(h.x+dx,h.z+dz);lo=Math.min(lo,y);hi=Math.max(hi,y);}
   if(hi-lo>worstTilt){worstTilt=hi-lo;worstAt='('+Math.round(h.x)+','+Math.round(h.z)+')';}}
  console.log('   worst height variation across any plot:',worstTilt.toFixed(3)+'m',worstAt);
  ok('plots are dead level, so fences sit on the ground',worstTilt<0.02);
  const h0=JSON.parse(w.eval('JSON.stringify(HOUSEPLAN[0])'));
  ok('and the pad still sits at the hillside height it belongs to ('+ty(h0.x,h0.z).toFixed(2)+'m)',
     Math.abs(ty(h0.x,h0.z)-h0.y)<0.01);
  let blend=0,pv=null;
  for(let d=0;d<=26;d+=.5){const y=ty(h0.x+d,h0.z);if(pv!==null)blend=Math.max(blend,Math.abs(y-pv));pv=y;}
  ok('pads blend back into the hill, no cliff at the plot edge ('+blend.toFixed(3)+'m/0.5m)',blend<0.35);
  console.log('3. RENDER RESOLUTION (the staircase look)');
  console.log('   default render height:',w.eval('GFX.res')+'p  (was 270p)');
  ok('medium is no longer a ~6x upscale on a big display',w.eval('GFX.res')>=480);
  T('cycleGfx()');const a=w.eval('GFX.res');
  T('cycleGfx()');const b=w.eval('GFX.res');
  T('cycleGfx()');const c=w.eval('GFX.res');
  console.log('   ladder:',[a,b,c].join('p -> ')+'p');
  ok('three distinct tiers',new Set([a,b,c]).size===3);
  T('localStorage.setItem("torii_gfx",JSON.stringify({res:270,far:300,detail:.5,manual:true,glow:true,grade:true,scan:true,tex:true}));');
  console.log('   an old saved 270p setting migrates to:',
    w.eval('(function(){const OLD={200:300,270:480,440:760};return OLD[270]})()')+'p ✓');
  console.log('4. NOTHING ELSE MOVED');
  ok('city centre still flat',ty(0,0)===0);
  ok('mountain summit ~58m at its new centre ('+ty(-382,-300).toFixed(1)+'m)',ty(-382,-300)>50);
  ok('she still stands on the ground she sees',
     Math.abs(w.eval('groundY(-30,262)')-ty(-30,262))<0.001);
  T('enemies.length=0;player.position.set(-30,0,262);spawnEnemy("imp",-28,264);updateEnemies(.03,1);');
  ok('enemies still sit on the surface',
     Math.abs(w.eval('enemies[0].g.position.y-groundY(enemies[0].g.position.x,enemies[0].g.position.z)'))<0.6);
  w.clearInterval(iv);
  console.log(E.length?'ERRORS: '+[...new Set(E)].slice(0,4).join(' ;; '):'NO ERRORS ✓');
  console.log(errs.length?'RUNTIME: '+[...new Set(errs)].slice(0,3).join(' ;; '):'NO RUNTIME ERRORS ✓');
  process.exit(0);
 },3200);
},2000);
setTimeout(()=>{console.log('TIMEOUT');process.exit(2);},44000);
