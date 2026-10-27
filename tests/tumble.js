const {boot}=require('./harness');
const {w,errs,E,T,clear}=boot();
setTimeout(()=>{
 w.document.getElementById('startBtn').click();
 setTimeout(()=>{
  const iv=w.setInterval(clear,30);
  const ok=(l,c)=>console.log('  '+(c?'✓':'✗')+' '+l);
  console.log('COMING OFF THE BIKE');
  const crashAt=(sp)=>{
   T('S.hp=500;S.maxhp=500;S.hurtCd=0;S.dead=false;S.wipeT=0;S.wipePhase="";S.wobbleT=0;');
   T('S.onBike=true;bk.parked=false;bk.speed='+sp+';player.position.set(0,0,0);player.rotation.y=0;S.yaw=0;');
   // force the bad half of the coin flip
   T('const _r=Math.random;Math.random=()=>0.01;bikeCrash('+sp+',"wall");Math.random=_r;');
   const start={x:w.eval('player.position.x'),z:w.eval('player.position.z')};
   let peak=0,phases=[],land=null,frames=0;
   for(let i=0;i<200;i++){
    clear();T('updatePlayer(.03,'+(i*.03)+')');
    const ph=w.eval('S.wipePhase')||'(up)';
    if(phases[phases.length-1]!==ph)phases.push(ph);
    peak=Math.max(peak,w.eval('player.position.y'));
    if(!land&&ph==='down')land=frames*0.03;
    frames++;
    if(!w.eval('S.wipeT'))break;
   }
   const d=Math.hypot(w.eval('player.position.x')-start.x,w.eval('player.position.z')-start.z);
   return {d,peak,phases,total:frames*0.03,land};
  };
  const slow=crashAt(11), fast=crashAt(26);
  console.log('   crash at 11 -> flew '+slow.d.toFixed(1)+'m, peak '+slow.peak.toFixed(1)+'m, down for '+slow.total.toFixed(1)+'s');
  console.log('   crash at 26 -> flew '+fast.d.toFixed(1)+'m, peak '+fast.peak.toFixed(1)+'m, down for '+fast.total.toFixed(1)+'s');
  ok('she actually flies away from the bike',slow.d>2&&fast.d>2);
  ok('a fast crash throws her much further',fast.d>slow.d*1.5);
  ok('and higher',fast.peak>slow.peak);
  ok('and keeps her down longer',fast.total>slow.total);
  console.log('   phase sequence:',fast.phases.join(' -> '));
  ok('fly, then lying down, then getting up',
     fast.phases[0]==='fly'&&fast.phases.indexOf('down')>0&&fast.phases.indexOf('getup')>fast.phases.indexOf('down'));
  ok('and she ends up standing and off the bike',!w.eval('S.onBike')&&!w.eval('S.wipeT'));
  console.log('   the bike stays where it fell:',
    'bike at ('+w.eval('bike.position.x').toFixed(1)+','+w.eval('bike.position.z').toFixed(1)+')',
    'her at ('+w.eval('player.position.x').toFixed(1)+','+w.eval('player.position.z').toFixed(1)+')');
  ok('bike did not follow her',Math.hypot(w.eval('bike.position.x')-w.eval('player.position.x'),
      w.eval('bike.position.z')-w.eval('player.position.z'))>1.5);
  console.log('\n   poses along the way:');
  T('S.wipeT=2;S.wipePhase="fly";S.wipeHard=1;S.wipeSpinT=1.4;S.wipeSide=1;poseTorii(.03,1,false);');
  console.log('     fly   body rot x='+w.eval('tor.body.rotation.x').toFixed(2)+
    ' z='+w.eval('tor.body.rotation.z').toFixed(2));
  ok('tumbling in the air',Math.abs(w.eval('tor.body.rotation.x'))>.5);
  T('S.wipePhase="down";poseTorii(.03,1,false);');
  console.log('     down  body rot x='+w.eval('tor.body.rotation.x').toFixed(2)+
    ' y-offset='+w.eval('tor.body.position.y').toFixed(2));
  ok('lying flat, not standing',w.eval('tor.body.rotation.x')<-1.3);
  ok('lying ON the ground, not buried in it (was -1.02)',w.eval('tor.body.position.y')>0);
  T('S.wipePhase="getup";S.getT=.85;poseTorii(.03,1,false);');
  const a=w.eval('tor.body.rotation.x');
  T('S.getT=.42;poseTorii(.03,1,false);');const b=w.eval('tor.body.rotation.x');
  T('S.getT=.02;poseTorii(.03,1,false);');const c=w.eval('tor.body.rotation.x');
  console.log('     getup body rot x: '+a.toFixed(2)+' -> '+b.toFixed(2)+' -> '+c.toFixed(2));
  ok('stands up smoothly from flat to upright',a<b&&b<c&&Math.abs(c)<.15);
  T('S.wipeT=0;S.wipePhase="";');
  console.log('\nSOLID WORLD');
  const treeCols=w.eval('colliders.filter(c=>c.hw<1&&c.hd<1).length');
  console.log('   small props with colliders:',treeCols);
  ok('trees and street props block now',treeCols>20);
  console.log('\nSTAMINA');
  T('S.onBike=true;bk.parked=false;S.wipeT=0;bk.speed=15;bk.boostCd=0;S.stam=100;S.winded=false;S.drifting=false;');
  T('keys[" "]=true;keys["a"]=false;');
  clear();T('updatePlayer(.03,1)');
  const afterBoost=w.eval('S.stam');
  console.log('   boost: stamina 100 ->',afterBoost.toFixed(0));
  ok('boost costs stamina',afterBoost<100);
  T('keys[" "]=false;');
  T('S.stam=100;S.winded=false;bk.speed=22;S.drifting=false;keys[" "]=true;keys["a"]=true;');
  let minStam=100,everDrifted=false;
  for(let i=0;i<25;i++){clear();T('updatePlayer(.03,'+(i*.03)+')');
   if(w.eval('S.drifting'))everDrifted=true;
   minStam=Math.min(minStam,w.eval('S.stam'));}
  console.log('   drifting: stamina never dropped below',minStam.toFixed(0),'| drifted =',everDrifted);
  ok('drifting is free',everDrifted&&minStam>=99.9);
  T('keys[" "]=false;keys["a"]=false;');
  T('S.stam=5;S.winded=false;bk.boostCd=0;bk.speed=15;keys[" "]=true;');
  const spd0=w.eval('bk.speed');
  clear();T('updatePlayer(.03,9)');
  ok('cannot boost on an empty bar',w.eval('bk.speed')<=spd0+1);
  T('keys[" "]=false;S.onBike=false;bk.parked=true;bk.speed=0;');
  w.clearInterval(iv);
  console.log(E.length?'ERRORS: '+[...new Set(E)].slice(0,3).join(' ;; '):'NO ERRORS ✓');
  console.log(errs.length?'RUNTIME: '+[...new Set(errs)].slice(0,2).join(' ;; '):'NO RUNTIME ERRORS ✓');
  process.exit(0);
 },3000);
},2000);
setTimeout(()=>{console.log('TIMEOUT');process.exit(2);},40000);
