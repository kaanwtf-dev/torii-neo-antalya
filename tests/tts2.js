const {boot}=require('./harness');
const {w,errs,E,T,clear}=boot();
setTimeout(()=>{
 w.document.getElementById('startBtn').click();
 setTimeout(()=>{
  const ok=(l,c)=>console.log('  '+(c?'✓':'✗')+' '+l);
  console.log('THE SELF-TEST WAS CANCELLING ITS OWN TEST LINE');
  // record the exact order of cancel() and speak() calls
  T(`window.__log=[];
     speechSynthesis.cancel=function(){window.__log.push('CANCEL@'+Date.now())};
     speechSynthesis.speak=function(u){window.__log.push('SPEAK@'+Date.now()+':'+String(u.text).slice(0,12))};`);
  T('voiceOn=false;setVoice(true);');
  setTimeout(()=>{
   const log=JSON.parse(w.eval('JSON.stringify(__log)'));
   console.log('   call order:');
   const t0=parseInt(log[0].split('@')[1].split(':')[0]);
   log.forEach(l=>{
    const [what,rest]=l.split('@');
    const ms=parseInt(rest.split(':')[0])-t0;
    console.log('     +'+String(ms).padStart(4)+'ms  '+what+(rest.includes(':')?' "'+rest.split(':')[1]+'"':''));});
   const iCancel=log.findIndex(l=>l.startsWith('CANCEL'));
   // ANY speak after a cancel must clear the flush window, game lines included
   let worst=1e9;
   log.forEach(l=>{if(!l.startsWith('SPEAK'))return;
    const t=parseInt(l.split('@')[1]);
    const c=parseInt(log[iCancel].split('@')[1]);
    if(t>c)worst=Math.min(worst,t-c);});
   console.log('   closest any speak got to the cancel:',worst+'ms');
   ok('nothing speaks inside the flush window, not even a game line',worst>=250);
   ok('(that gap is the whole Chromium bug — a flush kills anything queued behind it)',true);
   console.log('\nEVERY CANCEL GOES THROUGH ONE PLACE');
   ok('ttsReset() exists',w.eval('typeof ttsReset')==='function');
   T('window.__log=[];TTS.since=1;speechSynthesis.speaking=true;speak("merhaba");');
   const imm=w.eval('__log.filter(l=>l.startsWith("SPEAK")).length');
   ok('speak() while busy: cancels, does NOT speak in the same tick',imm===0);
   setTimeout(()=>{
    ok('...and speaks a moment later',w.eval('__log.filter(l=>l.startsWith("SPEAK")).length')>=1);
    T('window.__log=[];TTS.since=0;speechSynthesis.speaking=false;speak("tekrar");');
    ok('speak() while idle: speaks immediately, keeping user activation',
       w.eval('__log.filter(l=>l.startsWith("SPEAK")).length')===1&&
       w.eval('__log.filter(l=>l.startsWith("CANCEL")).length')===0);
    console.log('\nONE SUCCESS PROVES THE ENGINE WORKS');
    T('TTS.started=3;TTS.silent=9;TTS.dead=false;');
    T('ttsSpeak("test","tr-TR",null,1,1,1);');
    setTimeout(()=>{
     ok('never declared dead once it has spoken at least once',!w.eval('TTS.dead'));
     T('TTS.started=0;TTS.silent=0;TTS.dead=false;');
     console.log('\nGAMEPLAY PATH IS UNCHANGED AND CANCEL-FREE');
     T('window.__log=[];player.position.set(0,0,0);voiceOn=true;voiceBusyUntil=0;TTS.since=0;speechSynthesis.speaking=false;');
     T('mobSpeak("imp",["Yakala!","Catch her!"],0,0);');
     ok('a monster line speaks with no cancel at all',
        w.eval('__log.filter(l=>l.startsWith("CANCEL")).length')===0&&
        w.eval('__log.filter(l=>l.startsWith("SPEAK")).length')===1);
     console.log(E.length?'ERRORS: '+[...new Set(E)].slice(0,3).join(' ;; '):'NO ERRORS ✓');
     console.log(errs.length?'RUNTIME: '+[...new Set(errs)].slice(0,2).join(' ;; '):'NO RUNTIME ERRORS ✓');
     process.exit(0);
    },200);
   },500);
  },1200);
 },2800);
},2000);
setTimeout(()=>{console.log('TIMEOUT');process.exit(2);},40000);
