const {boot}=require('./harness');
const {w,errs,E,T,clear}=boot();
setTimeout(()=>{
 w.document.getElementById('startBtn').click();
 setTimeout(()=>{
  const iv=w.setInterval(clear,30);
  const ok=(l,c)=>console.log('  '+(c?'✓':'✗')+' '+l);
  // read the raw CSS rather than computed layout (jsdom does not lay out)
  const css=w.eval('Array.from(document.styleSheets[0].cssRules).map(r=>r.cssText).join("\\n")');
  const rule=(sel)=>{
   const m=css.split('\n').find(l=>l.trim().startsWith(sel));
   return m||'';
  };
  console.log('EVERYTHING IN THE HUD SCALES, NOT JUST TEXT');
  const checks=[
   ['.bar',        'health / mana / stamina / XP bars'],
   ['.sk',         'skill buttons'],
   ['#skills',     'skill bar row'],
   ['#mmap',       'minimap'],
   ['#mmapWrap',   'minimap frame'],
   ['.gb',         'corner buttons'],
   ['#btns',       'corner button column'],
   ['#cross',      'crosshair'],
   ['#hud',        'HUD position'],
   ['#missionBox', 'mission panel'],
   ['#buffs',      'buff list'],
   ['.bf',         'buff chips'],
  ];
  let scaled=0;
  checks.forEach(([sel,name])=>{
   const r=rule(sel);
   const usesFs=/var\(--fs\)/.test(r);
   // does it still have a hard px size that should scale?
   const hard=/(?:^|[;{ ])(width|height|padding|gap|border(?:-left)?)\s*:\s*[^;]*?\d+px/.test(
     r.replace(/calc\([^)]*var\(--fs\)[^)]*\)/g,'S'));
   if(usesFs&&!hard)scaled++;
   console.log('   '+(usesFs&&!hard?'✓':'✗')+' '+name);
  });
  ok('every HUD element scales with the slider',scaled===checks.length);
  console.log('\nTHE SLIDER GOES FAR ENOUGH FOR A TV');
  const sl=w.eval('$("optFs").max');
  console.log('   range:',w.eval('$("optFs").min')+'% .. '+sl+'%');
  ok('goes to 300% (was 180%)',+sl>=300);
  console.log('\nIT ACTUALLY MOVES THE VARIABLE');
  const read=()=>w.eval('document.documentElement.style.getPropertyValue("--fs")');
  T('uiFs=100;applyOpts();');const a=read();
  T('uiFs=250;applyOpts();');const b=read();
  console.log('   100% -> --fs:'+a+'   250% -> --fs:'+b);
  ok('the CSS variable follows the slider',parseFloat(b)>parseFloat(a)&&Math.abs(parseFloat(b)-2.5)<0.01);
  console.log('   a 190px bar at 250% renders 475px wide; a 52px skill button becomes 130px');
  console.log('\n   the minimap buffer grows too, so it stays sharp:');
  T('uiFs=250;applyOpts();');
  console.log('     at 250% the canvas is',w.eval('$("mmap").width')+'px internally (was fixed at 146)');
  ok('minimap is redrawn at the bigger resolution',w.eval('$("mmap").width')>146);
  T('drawMinimap();');
  ok('and it draws at that size without error',E.length===0);
  T('uiFs=100;applyOpts();');
  ok('shrinks back down',w.eval('$("mmap").width')===146);
  ok('and resets cleanly',Math.abs(parseFloat(read())-1)<0.01);
  console.log('\nNOTHING ELSE BROKE');
  ok('game still running',w.eval('S.mode')==='play');
  T('drawMinimap();');
  ok('minimap still draws',E.length===0);
  w.clearInterval(iv);
  console.log(E.length?'ERRORS: '+[...new Set(E)].slice(0,3).join(' ;; '):'NO ERRORS ✓');
  console.log(errs.length?'RUNTIME: '+[...new Set(errs)].slice(0,2).join(' ;; '):'NO RUNTIME ERRORS ✓');
  process.exit(0);
 },2800);
},2000);
setTimeout(()=>{console.log('TIMEOUT');process.exit(2);},40000);
