const {boot}=require('./harness');
const {w,errs,E,T,clear}=boot();
const ok=(l,c)=>console.log('  '+(c?'✓':'✗')+' '+l);
setTimeout(()=>{
 setTimeout(()=>{
  // Silence every OTHER route into the speech engine so the probe only sees
  // the utterances it makes itself.
  T('S.paused=true;voiceOn=false;window.speak=function(){};window.mobSpeak=function(){};');
  T(`window.__try=[];window.__quiet=true;
     speechSynthesis.speak=function(u){window.__try.push({lang:u.lang||'(none)',voice:u.voice?'pinned':'(none)',u:u});};`);
  console.log('CHROMIUM GOES SILENT IF IT CANNOT SATISFY THE REQUEST AS ASKED');
  console.log('  (usually lang="tr-TR" on a machine with no Turkish voice —');
  console.log('   Safari falls back by itself, Chromium just returns nothing)\n');
  const reset=(extra)=>T('window.__try=[];TTS.dead=false;TTS.silent=0;TTS.started=0;TTS.resetUntil=0;'+(extra||''));
  const get=()=>JSON.parse(w.eval('JSON.stringify(__try.map(a=>({lang:a.lang,voice:a.voice})))'));

  reset('TTS.tier=0;trVoice={name:"Yelda",lang:"tr-TR"};');
  T('ttsSpeak("merhaba","tr-TR",trVoice,1,1,1);');
  setTimeout(()=>{
   const t=get();
   console.log('  A. Turkish voice present, but nothing ever actually speaks:');
   t.forEach((a,i)=>console.log('     attempt '+i+':  lang='+a.lang+'   voice='+a.voice));
   ok('tier 0 asks for the Turkish voice + tr-TR',t[0]&&t[0].lang==='tr-TR'&&t[0].voice==='pinned');
   ok('tier 1 drops the pinned voice',t[1]&&t[1].lang==='tr-TR'&&t[1].voice==='(none)');
   ok('tier 2 drops the language too',t[2]&&t[2].lang==='(none)');
   ok('then it gives up — no retry storm',t.length===3);
   w.document.getElementById('startBtn').click();   // rest of the probe needs a live game

   reset('TTS.tier=0;trVoice=null;');
   T('ttsSpeak("merhaba","tr-TR",null,1,1,1);');
   setTimeout(()=>{
    const t2=get();
    console.log('\n  B. NO Turkish voice installed at all:');
    t2.forEach((a,i)=>console.log('     attempt '+i+':  lang='+a.lang+'   voice='+a.voice));
    ok('skips straight past tr-TR rather than asking for a voice that is not there',
       t2[0]&&t2[0].lang==='(none)');
    ok('one attempt, not three',t2.length===1);

    // let a tier-2 utterance actually succeed
    T(`window.__try=[];TTS.tier=0;TTS.started=0;TTS.silent=0;TTS.resetUntil=0;TTS.dead=false;
       trVoice={name:"Yelda",lang:"tr-TR"};
       speechSynthesis.speak=function(u){window.__try.push({lang:u.lang||'(none)',voice:u.voice?'pinned':'(none)'});
        if(!u.lang&&u.onstart)setTimeout(function(){u.onstart()},1);};`);
    T('ttsSpeak("bir","tr-TR",trVoice,1,1,1);');
    setTimeout(()=>{
     console.log('\n  C. once a tier works, it is remembered:');
     console.log('     tier now =',w.eval('TTS.tier'),'| successful utterances =',w.eval('TTS.started'));
     ok('the working tier is recorded',w.eval('TTS.tier')===2&&w.eval('TTS.started')>0);
     T('window.__try=[];ttsSpeak("iki","tr-TR",trVoice,1,1,1);');
     setTimeout(()=>{
      const t4=get();
      console.log('     next line ->',t4.length,'call(s), lang='+(t4[0]&&t4[0].lang));
      ok('later lines go straight to it — one call, not three',t4.length===1&&t4[0].lang==='(none)');
      console.log('\n  D. and the player is never told any of this:');
      const src=w.eval('JSON.stringify(PATCHES[0])');
      ok('no Terminal instructions in the patch notes',!src.includes('http.server'));
      ok('no browser-bug lecture',!src.includes('known Edge'));
      T('TTS.dead=true;');
      ok('synthesised voice still carries it if everything fails',
         w.eval('(function(){try{babble("merhaba",1,1,1);return true}catch(e){return false}})()'));
      console.log(E.length?'ERRORS: '+[...new Set(E)].slice(0,3).join(' ;; '):'NO ERRORS ✓');
      console.log(errs.length?'RUNTIME: '+[...new Set(errs)].slice(0,2).join(' ;; '):'NO RUNTIME ERRORS ✓');
      process.exit(0);
     },500);
    },3000);
   },3600);
  },3600);
 },2800);
},2000);
setTimeout(()=>{console.log('TIMEOUT');process.exit(2);},44000);
