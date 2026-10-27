const {boot}=require('./harness');
const {w,errs,E,T,clear}=boot();
setTimeout(()=>{
 w.document.getElementById('startBtn').click();
 setTimeout(()=>{
  const iv=w.setInterval(clear,30);
  const ok=(l,c)=>console.log('  '+(c?'✓':'✗')+' '+l);
  const gy=(x,z)=>w.eval('groundY('+x+','+z+')');
  const KS=JSON.parse(w.eval('JSON.stringify(KS)')),KD=JSON.parse(w.eval('JSON.stringify(KD)'));
  console.log('THE APARTMENT vs THE STAIRS');
  console.log('   apartment volume : x -30.5..-17.5,  z -29..-19  (addBuilding(-24,-24,13,10,9))');
  console.log('   stair run        : x '+KS.x0+'..'+KS.x1+',  z '+(KS.z-KS.w).toFixed(1)+'..'+(KS.z+KS.w).toFixed(1));
  console.log('   balcony deck     : x '+KD.x0+'..'+KD.x1+',  z '+KD.z0+'..'+KD.z1);
  const bx0=-30.5,bx1=-17.5,bz0=-29,bz1=-19;
  const overlap=(ax0,ax1,az0,az1)=>(ax0<bx1&&bx0<ax1&&az0<bz1&&bz0<az1);
  ok('the stair is clear of the building volume',
     !overlap(KS.x0,KS.x1,KS.z-KS.w,KS.z+KS.w));
  ok('the deck is in front of the building face, not inside it',
     !overlap(KD.x0,KD.x1,KD.z0+0.01,KD.z1));
  ok('stair and deck tile without overlapping (stair ends where deck begins)',
     Math.abs(KS.x1-KD.x0)<0.001);
  console.log('WALKING UP');
  const prof=[];
  let mx=0,pv=null;
  for(let x=-37;x<KD.x1-0.25;x+=.5){
   const y=gy(x,KS.z<-15?KS.z:-16.6);
   if(pv!==null)mx=Math.max(mx,Math.abs(y-pv));
   pv=y;
   if(Math.round(x*2)%4===0)prof.push('x='+x.toFixed(0)+' y='+y.toFixed(2));}
  console.log('   '+prof.join('  '));
  ok('smooth climb from the street to the deck ('+mx.toFixed(2)+'m per 0.5m step)',mx<0.6);
  console.log('   (past x='+KD.x1+' the deck ends and she drops — that is a balcony edge, not a bug)');
  ok('foot of the stairs is at ground level',Math.abs(gy(KS.x0-.5,KS.z))<0.01);
  ok('top of the stairs meets the deck height',Math.abs(gy(KS.x1,KS.z)-KD.y)<0.05);
  console.log('   deck height at Kaan:',gy(w.eval('kaan.position.x'),w.eval('kaan.position.z')).toFixed(2)+'m');
  ok('Kaan stands ON the deck',Math.abs(gy(w.eval('kaan.position.x'),w.eval('kaan.position.z'))-KD.y)<0.05);
  ok('nothing blocks the way up',
     w.eval('colliders.filter(c=>Math.abs(c.z-KS.z)<c.hd+1.5&&c.x>KS.x0-3&&c.x<KD.x1+1).length')===0);
  console.log('   the stair foot is off the road grid:',
     w.eval('onRoad('+KS.x0+','+KS.z+',5.4)')?'✗ ON A ROAD':'✓ clear');
  console.log('SHE CAN ACTUALLY GET THERE AND TALK');
  T('S.zone="city";S.dead=false;S.onBike=false;S.grounded=true;S.vy=0;');
  T('player.position.set('+(KS.x0-1)+',0,'+KS.z+');player.rotation.y=Math.PI/2;S.yaw=Math.PI/2;');
  let top=0,arrivedAt=null;
  for(let i=0;i<260;i++){clear();T('keys["w"]=true;updatePlayer(.03,'+(i*.03)+')');
   top=Math.max(top,w.eval('player.position.y'));
   const dd=w.eval('Math.hypot(kaan.position.x-player.position.x,kaan.position.z-player.position.z)');
   if(dd<4.5){arrivedAt=i;break;}}
  T('keys["w"]=false;');
  console.log('   walked east from the foot -> reached',top.toFixed(2)+'m, ended at x='+w.eval('player.position.x').toFixed(1));
  ok('she climbs it just by walking forward',top>5);
  const d=w.eval('Math.hypot(kaan.position.x-player.position.x,kaan.position.z-player.position.z)');
  console.log('   walked into talking range after',arrivedAt!==null?arrivedAt+' frames':'never','— distance '+d.toFixed(1)+'m');
  ok('walking forward from the street reaches Kaan',arrivedAt!==null);
  ok('and she is up on the deck when she gets there ('+w.eval('player.position.y').toFixed(2)+'m)',w.eval('player.position.y')>5);
  T('S.gate={next:1,type:"imp",left:5,eleft:0};S.bounty=null;S.lira=9999;interact();');
  ok('and E opens his menu',/hunt|Kar/i.test(w.eval('document.body.textContent')||''));
  w.clearInterval(iv);
  console.log(E.length?'ERRORS: '+[...new Set(E)].slice(0,3).join(' ;; '):'NO ERRORS ✓');
  console.log(errs.length?'RUNTIME: '+[...new Set(errs)].slice(0,3).join(' ;; '):'NO RUNTIME ERRORS ✓');
  process.exit(0);
 },3000);
},2000);
setTimeout(()=>{console.log('TIMEOUT');process.exit(2);},40000);
