// Shared jsdom + THREE-mock harness for torii-neo-antalya.html.
// Loads the game headlessly so tests can poke real game functions.
const fs=require('fs');const {JSDOM,VirtualConsole}=require('jsdom');
// Always test the NEWEST versioned build, whatever it is called today.
const DIR=process.env.TORII_DIR||'/sessions/hopeful-inspiring-ptolemy/mnt/Video Game Torii';
function newest(dir){
 const v=fs.readdirSync(dir).filter(f=>/^torii-neo-antalya-ALPHA-[\d.]+\.html$/.test(f))
  .sort((a,b)=>parseFloat(a.match(/([\d.]+)\.html$/)[1])-parseFloat(b.match(/([\d.]+)\.html$/)[1]));
 return dir+'/'+(v.length?v[v.length-1]:'torii-neo-antalya.html');
}
const GAME=newest(DIR);
// boot() runs the newest build; boot(dir) runs the newest build in another folder (e.g. backups/)
function boot(dir){
let html=fs.readFileSync(dir?newest(dir):GAME,'utf8');
html=html.replace(/<script src="[^"]*"><\/script>/,'');
const stub=`<script>
const __mk=()=>{const f=function(){};return new Proxy(f,{get(t,p){if(p===Symbol.toPrimitive)return h=>0;if(p===Symbol.iterator)return function*(){};if(p==='then')return undefined;if(!(p in t)){try{t[p]=__mk()}catch(e){return undefined}}return t[p];},set(t,p,v){try{t[p]=v}catch(e){};return true},construct(){return __mk()},apply(){return __mk()},});};
window.__meshes=0;window.__mats=0;window.__pts=0;
function Tex(){return {wrapS:0,wrapT:0,repeat:{set(){}},magFilter:0,minFilter:0,generateMipmaps:false,needsUpdate:false,image:{},clone(){return Tex()}};}
function V3(x,y,z){return {x:x||0,y:y||0,z:z||0,set(a,b,c){this.x=a;this.y=b;this.z=c;return this},copy(o){this.x=o.x;this.y=o.y;this.z=o.z;return this},
 multiplyScalar(){return this},addScalar(){return this},setScalar(v){this.s=v;return this},project(){return this},normalize(){return this},sub(){return this},length(){return 1},
 clone(){return V3(this.x,this.y,this.z)},add(){return this},lookAt(){}};}
function Obj(){const o={children:[],position:V3(),rotation:V3(),scale:V3(1,1,1),visible:true,isMesh:false,userData:{},frustumCulled:true,
 add(...c){c.forEach(x=>{x.parent=o;o.children.push(x)})},remove(c){const i=o.children.indexOf(c);if(i>=0)o.children.splice(i,1)},
 traverse(cb){cb(o);o.children.forEach(c=>c.traverse&&c.traverse(cb))},clone(){const n=Obj();n.children=o.children.slice();n.material=o.material;return n},
 lookAt(){},updateMatrixWorld(){},getWorldPosition(v){v.set(o.position.x,o.position.y,o.position.z);return v},
 quaternion:{copy(){}},rotateZ(){}};return o;}
function Col(v){const c={r:1,g:1,b:1,v:typeof v==='number'?v:0xffffff,
 setHex(h){this.v=h;return this},getHex(){return this.v},lerp(){return this},copy(o){this.v=o.v;return this},clone(){return Col(this.v)}};return c;}
window.THREE=new Proxy({},{get(t,p){const n=String(p);
 if(n==='CanvasTexture')return function(){return Tex()};
 if(n==='RepeatWrapping')return 1000;if(n==='AdditiveBlending')return 2;
 if(n==='NearestFilter')return 3;if(n==='LinearFilter')return 4;
 if(n==='DoubleSide')return 'D';if(n==='FrontSide')return 'F';if(n==='BackSide')return 'B';
 if(n==='Vector3')return function(x,y,z){return V3(x,y,z)};
 if(n==='Color')return function(v){return Col(v)};
 if(n==='Group')return function(){return Obj()};
 if(n==='Scene')return function(){const o=Obj();o.isScene=true;return o};
 if(n==='PerspectiveCamera')return function(f,a,nr,fr){const o=Obj();o.fov=f;o.aspect=a;o.near=nr;o.far=fr;
   o.updateProjectionMatrix=function(){};return o;};
 if(n==='Sprite')return function(){return Obj()};
 if(n==='Points'){return function(g,m){window.__pts++;const o=Obj();o.isPoints=true;o.material=m||{};return o;};}
 if(n==='Mesh'){return function(g,m){window.__meshes++;const o=Obj();o.isMesh=true;o.geometry=g||{};
   o.material=m||{color:Col(),emissive:Col()};return o;};}
 if(n==='MeshBasicMaterial'||n==='MeshLambertMaterial'||n==='PointsMaterial'){return function(o){window.__mats++;o=o||{};
   const m=Object.assign({},o);m.color=Col(o.color);m.emissive=Col(o.emissive);return m;};}
 if(n==='HemisphereLight')return function(a,b,i){return {color:Col(a),groundColor:Col(b),intensity:i,position:V3()}};
 if(n==='DirectionalLight')return function(a,i){return {color:Col(a),intensity:i,position:V3()}};
 if(n==='Fog')return function(c,a,b){return {color:Col(c),near:a,far:b}};
 if(n==='BufferGeometry')return function(){return {setAttribute(){},setIndex(){},computeBoundingSphere(){},attributes:{},computeVertexNormals(){},rotateX(){},rotateY(){},scale(){},translate(){}}};
 if(n==='PlaneGeometry')return function(){return {setAttribute(){},attributes:{},computeVertexNormals(){},rotateX(){},translate(){}}};
 if(n==='Float32BufferAttribute')return function(){return {}};
 return function(){return __mk()};}});
window.AudioContext=__mk();
HTMLCanvasElement.prototype.getContext=function(){
 return {textAlign:'',textBaseline:'',font:'16px m',shadowColor:'',shadowBlur:0,fillStyle:'',strokeStyle:'',lineWidth:0,globalAlpha:1,lineCap:'',
  measureText(t){return {width:String(t).length*9}},fillText(){},beginPath(){},moveTo(){},lineTo(){},closePath(){},
  fill(){},stroke(){},arc(){},ellipse(){},rect(){},roundRect(){},fillRect(){},strokeRect(){},clearRect(){},
  quadraticCurveTo(){},bezierCurveTo(){},arcTo(){},setLineDash(){},clip(){},
  save(){},restore(){},translate(){},scale(){},rotate(){},strokeText(){},
  getImageData(x,y,w,h){return {data:new Uint8ClampedArray(4*Math.max(1,(w||1)*(h||1)))}},putImageData(){},
  createLinearGradient(){return{addColorStop(){}}},createRadialGradient(){return{addColorStop(){}}}};};
window.requestAnimationFrame=cb=>setTimeout(()=>cb(Date.now()),16);window.confirm=()=>true;
window.speechSynthesis={getVoices:()=>[],cancel(){},speaking:false,speak(){},onvoiceschanged:null};
window.SpeechSynthesisUtterance=function(t){this.text=t;this.rate=1;this.pitch=1;this.volume=1;this.lang='';};</script>`;
html=html.replace('<script>','%%S%%<script>').replace('%%S%%',stub);
const errs=[];const vc=new VirtualConsole();vc.on('jsdomError',e=>errs.push(e.message));
const dom=new JSDOM(html,{runScripts:'dangerously',virtualConsole:vc,url:'https://localhost/',pretendToBeVisual:true});
const w=dom.window;
const E=[];
const T=c=>{try{return w.eval(c)}catch(e){E.push(String(c).slice(0,46)+' >> '+e.message);return null}};
const clear=()=>T('S.quizOpen=false;S.dlgOpen=false;S.paused=false;S.dead=false;S.tavlaOpen=false;S.betOpen=false;');
return {w,errs,E,T,clear,dom};
}
module.exports={boot};
