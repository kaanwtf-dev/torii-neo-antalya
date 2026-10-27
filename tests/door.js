const {boot}=require('./harness');
const {w,errs,E,T,clear}=boot();
setTimeout(()=>{
 w.document.getElementById('startBtn').click();
 setTimeout(()=>{
  const iv=w.setInterval(clear,30);
  const ok=(l,c)=>console.log('  '+(c?'✓':'✗')+' '+l);
  console.log('1. THE BUILDING IS SOLID AGAIN');
  console.log('   apartment: addBuilding(-24,-24,13,10,9) => x -30.5..-17.5, z -29..-19');
  const apt=w.eval('colliders.filter(c=>Math.abs(c.x+24)<1&&Math.abs(c.z+24)<1).map(c=>c.hw+"x"+c.hd).join(",")');
  console.log('   collider at (-24,-24):',apt||'(NONE)');
  ok('the apartment has its collider back',!!apt);
  ok('clearStairPath is gone entirely',w.eval('typeof clearStairPath')==='undefined');
  T('S.zone="city";S.dead=false;S.onBike=false;S.wipeT=0;');
  T('const p={x:-24,z:-22};resolveCol(p,.55);window.__pushed=JSON.stringify(p);');
  console.log('   trying to stand inside the flat at (-24,-22) ->',w.eval('__pushed'));
  ok('she is pushed back out of the wall',JSON.parse(w.eval('__pushed')).z>-19);

  console.log('\n2. THE STAIRS ARE GONE, THE DOOR WORKS');
  ok('no staircase geometry left',w.eval('typeof KS')==='undefined');
  ok('the balcony is still walkable',w.eval('groundY(-24,-17)')>5);
  ok('nothing floats where the stairs used to be',w.eval('groundY(-31,-16.6)')===0);
  const D=JSON.parse(w.eval('JSON.stringify(DOORXZ)'));
  console.log('   door trigger at ('+D.x+','+D.z+')');
  T('player.position.set('+D.x+',0,'+(D.z+1.2)+');S.doorCd=0;S.vy=0;S.grounded=true;');
  T('updateDoor(.03);');
  console.log('   walked into the door ->  y='+w.eval('player.position.y').toFixed(2)+
    '  at ('+w.eval('player.position.x').toFixed(0)+','+w.eval('player.position.z').toFixed(1)+')');
  ok('she is taken up to the balcony',w.eval('player.position.y')>5);
  ok('and lands ON the deck, not in mid-air',
     Math.abs(w.eval('player.position.y')-w.eval('groundY(player.position.x,player.position.z)'))<0.01);
  const kd=w.eval('Math.hypot(kaan.position.x-player.position.x,kaan.position.z-player.position.z)');
  console.log('   distance to Kaan on arrival:',kd.toFixed(1)+'m');
  ok('she arrives right next to Kaan',kd<6);
  ok('a cooldown stops instant ping-pong ('+w.eval('S.doorCd').toFixed(1)+'s)',w.eval('S.doorCd')>0.5);
  T('S.doorCd=0;player.position.set('+D.x+','+w.eval('KD.y')+','+(D.z+.5)+');');
  T('updateDoor(.03);');
  console.log('   walked into it from up there -> y='+w.eval('player.position.y').toFixed(2));
  ok('it brings her back down to the street',w.eval('player.position.y')<1);

  console.log('\n3. SHE NO LONGER SINKS INTO THE GROUND WHEN SHE FALLS');
  T('S.wipeT=2;S.wipePhase="down";S.wipeHard=1;S.wipeSide=1;poseTorii(.03,1,false);');
  const by=w.eval('tor.body.position.y');
  console.log('   lying down: body offset y =',by.toFixed(2),' (was -1.02 — a metre underground)');
  ok('her body sits above ground level, not below',by>0);
  T('S.wipePhase="getup";S.getT=.85;poseTorii(.03,1,false);');
  const g0=w.eval('tor.body.position.y');
  T('S.getT=.02;poseTorii(.03,1,false);');
  const g1=w.eval('tor.body.position.y');
  console.log('   getting up: '+g0.toFixed(2)+' -> '+g1.toFixed(2));
  ok('she rises back to standing height',g0>g1&&Math.abs(g1)<0.02);
  ok('and never dips below the floor',Math.min(g0,g1)>=0);
  T('S.wipeT=0;S.wipePhase="";tor.body.position.set(0,0,0);tor.body.rotation.set(0,0,0);');

  console.log('\n4. A FULL CRASH, START TO FINISH');
  T('S.hp=500;S.maxhp=500;S.onBike=true;bk.parked=false;bk.speed=24;player.position.set(0,0,0);player.rotation.y=0;');
  T('const _r=Math.random;Math.random=()=>0.01;bikeCrash(24,"wall");Math.random=_r;');
  let minY=99,phases=[];
  for(let i=0;i<220;i++){clear();
   T('updatePlayer(.03,'+(i*.03)+')');
   const ph=w.eval('S.wipePhase');
   if(!ph)break;                       // tumble over — after this it is just idle breathing
   T('poseTorii(.03,'+(i*.03)+',false)');
   if(phases[phases.length-1]!==ph)phases.push(ph);
   minY=Math.min(minY,w.eval('player.position.y+tor.body.position.y'));}
  console.log('   phases:',phases.join(' -> '));
  console.log('   lowest she ever got (player + body offset):',minY.toFixed(2)+'m');
  ok('she never goes underground during the whole tumble',minY>=-0.01);
  ok('and ends upright',Math.abs(w.eval('tor.body.position.y'))<0.02&&!w.eval('S.wipeT'));

  w.clearInterval(iv);
  console.log(E.length?'ERRORS: '+[...new Set(E)].slice(0,3).join(' ;; '):'NO ERRORS ✓');
  console.log(errs.length?'RUNTIME: '+[...new Set(errs)].slice(0,2).join(' ;; '):'NO RUNTIME ERRORS ✓');
  process.exit(0);
 },3000);
},2000);
setTimeout(()=>{console.log('TIMEOUT');process.exit(2);},40000);
