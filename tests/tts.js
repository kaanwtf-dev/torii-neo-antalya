const {boot}=require('./harness');
const {w,errs,E,T,clear}=boot();
setTimeout(()=>{
 const ok=(l,c)=>console.log('  '+(c?'✓':'✗')+' '+l);
 console.log('CHROMIUM / EDGE SPEECH WORKAROUNDS');
 ok('TTS layer present',w.eval('typeof ttsSpeak')==='function'&&w.eval('typeof ttsBusy')==='function');
 ok('voice list is polled, not just event-driven (Edge often never fires voiceschanged)',
    w.eval('typeof loadVoice')==='function'&&w.eval('TTS.tries')>=0);
 ok('warm-up on the start gesture exists',w.eval('typeof ttsWarmUp')==='function');
 console.log('  THE STICKY `speaking` FLAG — the reason it dies after a while:');
 T('speechSynthesis.speaking=true;TTS.since=performance.now()/1000;');
 ok('   while genuinely speaking, we hold off',w.eval('ttsBusy()')===true);
 T('TTS.since=performance.now()/1000-20;');           // pretend it wedged 20s ago
 const wedged=w.eval('ttsBusy()');
 ok('   a wedged utterance is detected and cleared instead of blocking forever',wedged===false);
 T('speechSynthesis.speaking=false;TTS.since=0;');
 console.log('  cancel()+speak() in the same tick is the Chromium drop bug:');
 let spoke=0;
 T('window.__spoke=0;speechSynthesis.speak=function(){window.__spoke++;};');
 T('TTS.since=0;speechSynthesis.speaking=false;speak("merhaba");');
 ok('   idle engine: speaks straight away, staying inside the user-activation window',w.eval('__spoke')===1);
 T('window.__spoke=0;TTS.since=performance.now()/1000;speechSynthesis.speaking=true;speak("tekrar");');
 ok('   busy engine: cancels, then DEFERS (0 in this tick)',w.eval('__spoke')===0);
 T('speechSynthesis.speaking=false;TTS.since=0;');
 setTimeout(()=>{
  ok('   ...and the deferred one lands a moment later ('+w.eval('__spoke')+')',w.eval('__spoke')>=1);
  T('window.__spoke=0;');
  T('player.position.set(0,0,0);voiceOn=true;TTS.since=0;speechSynthesis.speaking=false;voiceBusyUntil=0;');
  T('mobSpeak("imp",["Yakala!","Catch her!"],0,0);');
  ok('   mob lines still go out',w.eval('__spoke')>=1);
  T('window.__spoke=0;player.position.set(0,0,0);speechSynthesis.speaking=true;TTS.since=performance.now()/1000-20;voiceBusyUntil=0;');
  T('mobSpeak("imp",["Yakala!","Catch her!"],0,0);');
  ok('   and a wedged engine no longer swallows every later line',w.eval('__spoke')>=1);
  console.log('  every utterance clears its own timer on end/error:',
    w.eval('(function(){let u=null;speechSynthesis.speak=function(x){u=x};TTS.since=5;'+
    'ttsSpeak("test","tr-TR",null,1,1,1);if(u&&u.onend){u.onend();}return TTS.since===0})()')?'✓':'✗');
  console.log(errs.length?'RUNTIME: '+[...new Set(errs)].slice(0,3).join(' ;; '):'NO RUNTIME ERRORS ✓');
  process.exit(0);
 },300);
},2400);
setTimeout(()=>{console.log('TIMEOUT');process.exit(2);},30000);
