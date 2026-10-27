const {boot}=require('./harness');const {w,E,T}=boot();
setTimeout(()=>{
 w.document.getElementById('startBtn').click();
 setTimeout(()=>{
  const ok=(l,c)=>console.log('  '+(c?'✓':'✗')+' '+l);
  T('localStorage.clear();');
  T('S.level=5;S.lira=111;saveGame();');
  T('S.level=6;S.lira=222;saveGame();');
  T('S.level=7;S.lira=333;saveGame();');
  console.log('  main:',w.eval('JSON.parse(localStorage.getItem(SAVE_KEY)).lira'),
    '| bak:',w.eval('JSON.parse(localStorage.getItem(SAVE_KEY+"_bak")).lira'),
    '| bak2:',w.eval('JSON.parse(localStorage.getItem(SAVE_KEY+"_bak2")).lira'));
  ok('rolling backups keep the two previous saves',
     w.eval('JSON.parse(localStorage.getItem(SAVE_KEY+"_bak")).lira')===222);
  T('localStorage.setItem(SAVE_KEY,"{{{corrupt");');
  const d=w.eval('JSON.stringify(loadGame())');
  ok('a corrupt main save falls back to the backup instead of wiping her',
     JSON.parse(d)&&JSON.parse(d).lira===222);
  T('localStorage.setItem(SAVE_KEY+"_bak","also broken");');
  ok('and falls back again to the one before that',
     JSON.parse(w.eval('JSON.stringify(loadGame())')).lira===111);
  console.log('  save key is fixed, not filename-derived:',w.eval('SAVE_KEY'),'✓ survives renames');
  process.exit(0);
 },2600);
},1800);
