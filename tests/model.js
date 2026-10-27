// 7.2: Torii's real model — the embedded .glb, and the code-body fallback.
const fs=require('fs');
const {boot}=require('./harness');
const DIR=process.env.TORII_DIR||'/sessions/hopeful-inspiring-ptolemy/mnt/Video Game Torii';
const file=fs.readdirSync(DIR).filter(f=>/^torii-neo-antalya-ALPHA-[\d.]+\.html$/.test(f))
 .sort((a,b)=>parseFloat(a.match(/([\d.]+)\.html$/)[1])-parseFloat(b.match(/([\d.]+)\.html$/)[1])).pop();
const html=fs.readFileSync(DIR+'/'+file,'utf8');
let bad=0;
const ok=(l,c)=>{if(!c)bad++;console.log('  '+(c?'✓':'✗')+' '+l);};

console.log('THE MODEL INSIDE THE FILE ('+file+')');
const ext=[...html.matchAll(/<script[^>]*\bsrc="([^"]+)"/g)].map(m=>m[1]);
ok('still only one outside script (three r128 from cdnjs)',ext.length===1&&/cdnjs.*three\.js\/r128\/three\.min\.js/.test(ext[0]));
ok('GLTFLoader is pasted in',/THREE\.GLTFLoader = GLTFLoader;/.test(html));
const m=html.match(/<script id="torii-glb" type="application\/octet-stream">([\s\S]*?)<\/script>/);
ok('the model is embedded as base64',!!m);
const buf=Buffer.from((m?m[1]:'').replace(/\s+/g,''),'base64');
ok('it is a real glTF binary',buf.readUInt32LE(0)===0x46546c67&&buf.readUInt32LE(4)===2);
ok('and small ('+(buf.length/1024).toFixed(0)+' KB)',buf.length<250*1024);
const jl=buf.readUInt32LE(12),J=JSON.parse(buf.slice(20,20+jl).toString('utf8'));
const bin=buf.slice(20+jl+8);
const acc=i=>{const a=J.accessors[i],bv=J.bufferViews[a.bufferView],n={SCALAR:1,VEC2:2,VEC3:3,VEC4:4}[a.type];
 const T={5126:[4,'readFloatLE'],5125:[4,'readUInt32LE'],5123:[2,'readUInt16LE'],5121:[1,'readUInt8']}[a.componentType];
 const st=bv.byteStride||T[0]*n,o0=(bv.byteOffset||0)+(a.byteOffset||0),out=[];
 for(let k=0;k<a.count;k++){const r=[];for(let c=0;c<n;c++){let v=bin[T[1]](o0+k*st+c*T[0]);
  if(a.normalized)v/=a.componentType===5121?255:65535;r.push(v);}out.push(r);}return out;};
ok('no pictures inside — it uses her own painted atlas',!J.images||!J.images.length);
const meshes=Object.fromEntries(J.meshes.map(x=>[x.name,x]));
ok('body + two separate shoes (so gear can swap them)',!!meshes.TorBody&&!!meshes.shoe_m&&!!meshes.shoe_p);
const mats=J.materials.map(x=>x.name).sort().join(',');
ok('materials are atlas / face / bead ('+mats+')',mats==='atlas,bead,face');
const joints=J.skins[0].joints.map(i=>J.nodes[i].name);
const want=['body','head'];for(const s of['m','p'])want.push('arm_'+s,'elb_'+s,'leg_'+s,'kn_'+s);
for(let i=0;i<9;i++)want.push('br'+i,'mid'+i);
ok('every bone is one of the game\'s joints ('+joints.length+')',joints.every(n=>want.includes(n))&&want.every(n=>joints.includes(n)));
const node=n=>J.nodes.find(x=>x.name===n),tr=n=>(node(n).translation||[0,0,0]).map(v=>+v.toFixed(3));
const near=(a,b)=>a.every((v,i)=>Math.abs(v-b[i])<.002);
ok('bones have no rest rotation',joints.every(n=>!node(n).rotation));
ok('shoulders, elbows, hips, knees, head sit on the game\'s joints',
 near(tr('arm_p'),[.222,1.715,0])&&near(tr('arm_m'),[-.222,1.715,0])&&near(tr('elb_p'),[0,-.28,0])&&
 near(tr('leg_p'),[.118,.92,0])&&near(tr('kn_m'),[0,-.4,0])&&near(tr('head'),[0,2,0]));
let top=0,sz=[9,-9],tris=0,wsum=1,uvOut=0;
const REG=[[.005859375,.744140625,.255859375,.994140625],[.267578125,.744140625,.517578125,.994140625],[.529296875,.806640625,.779296875,.994140625],
 [.005859375,.576171875,.255859375,.732421875],[.267578125,.607421875,.517578125,.732421875],[.529296875,.482421875,.591796875,.732421875],
 [.603515625,.607421875,.728515625,.732421875],[.740234375,.669921875,.802734375,.732421875]];
for(const me of J.meshes)for(const p of me.primitives){
 const P=acc(p.attributes.POSITION);P.forEach(v=>{top=Math.max(top,v[1]);sz[0]=Math.min(sz[0],v[2]);sz[1]=Math.max(sz[1],v[2]);});
 tris+=acc(p.indices).length/3;
 acc(p.attributes.WEIGHTS_0).forEach(w=>{const s=w[0]+w[1]+w[2]+w[3];if(Math.abs(s-1)>Math.abs(wsum-1))wsum=s;});
 if(J.materials[p.material].name!=='bead')acc(p.attributes.TEXCOORD_0).forEach(([u,v])=>{v=1-v;
  if(!REG.some(r=>u>=r[0]-1e-4&&u<=r[2]+1e-4&&v>=r[1]-1e-4&&v<=r[3]+1e-4))uvOut++;});}
ok('head top at '+top.toFixed(2)+' (game wants about 2.2)',top>2.1&&top<2.3);
ok('PS1 poly count ('+tris+' triangles)',tris<4000);
ok('skin weights add up (worst '+wsum.toFixed(3)+')',Math.abs(wsum-1)<.01);
ok('every UV lands inside one of her atlas regions ('+uvOut+' outside)',uvOut===0);

const {w,errs,E,T}=boot();
setTimeout(()=>{
 console.log('IN THE GAME (mock THREE: the model never loads, so the code body must stay)');
 const regs=T('JSON.stringify(Object.keys(GIRL_UVREF).map(n=>[GIRL_UVREF[n],TATL.uv(n)]))');
 ok('the model\'s UV map matches her real atlas layout',!!regs&&JSON.parse(regs).every(([a,b])=>a.every((v,i)=>Math.abs(v-b[i])<1e-9)));
 ok('without the model, her code body is all there',T('tor.body&&tor.body.children.length>0&&!tor.body.children.some(c=>c.isSkinnedMesh)'));
 // a broken model must leave her exactly as she was
 const before=T('JSON.stringify([tor.braids[0].position,tor.hoops[0].position])');
 T('window.__R=buildGirl(TORII_PAL);window.__f=__R.feet[1];GIRLGLB.parts=[{key:"body",mat:"atlas",geo:{},bones:["nope"],inv:[]}];girlModel(__R);');
 ok('a model with a bone the game lacks is refused',T('!__R.model'));
 ok('…and the code body stays visible',T('__R.proc.length>10&&__R.proc.every(o=>o.visible)'));
 ok('…with her own shoes',T('__R.feet[1]===__f'));
 ok('…and nothing of the model left behind',T('!__R.body.children.some(c=>/^girl_/.test(c.name||""))'));
 ok('Torii herself untouched',T('JSON.stringify([tor.braids[0].position,tor.hoops[0].position])')===before);
 T('GIRLGLB.parts=null;');
 ok('Vinrax is credited',/Vinrax/.test(html));
 console.log(E.length?'ERRORS: '+[...new Set(E)].slice(0,3).join(' ;; '):'NO ERRORS ✓');
 console.log(errs.length?'RUNTIME: '+[...new Set(errs)].slice(0,2).join(' ;; '):'NO RUNTIME ERRORS ✓');
 process.exit(bad?1:0);
},2500);
setTimeout(()=>{console.log('TIMEOUT');process.exit(2);},40000);
