// Exercises adaptive layouts, invalid commercial data, required art, portable exports.
const fs=require('node:fs'), os=require('node:os'), path=require('node:path');
const {spawnSync}=require('node:child_process'), assert=require('node:assert/strict');
const sharp=require('sharp');
(async()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'banner-qa-'));
 const renderer=path.join(__dirname,'render.cjs');
 const seed=JSON.parse(fs.readFileSync(path.join(__dirname,'../examples/pirate.json'),'utf8'));
 const invoke=(c,name,extra=[])=>{
  const file=path.join(root,name+'.json'), out=path.join(root,name);
  fs.writeFileSync(file,JSON.stringify(c));
  const result=spawnSync(process.execPath,[renderer,file,out,...extra],{encoding:'utf8'});
  return {...result,out};
 };
 for(let n=1;n<=6;n++) {
  const c={...seed,title:'Ледяной капитан',offer:'НАБОР НОВИЧКА',rewards:Array.from({length:n},(_,i)=>({label:'×'+(i+1),asset:''}))};
  const r=invoke(c,'count-'+n,['--draft']); assert.equal(r.status,0,r.stderr);
  const meta=await sharp(path.join(r.out,'preview.png')).metadata(); assert.equal(meta.width,1000); assert.equal(meta.height,633);
  const l=JSON.parse(fs.readFileSync(path.join(r.out,'layout.json')));
  assert.equal(l.textNodes.find(x=>x.key==='offer').y,416);
  for(const t of l.textNodes) assert.ok(t.x>=0&&t.y>=0&&t.x+t.width<=1000&&t.y+t.height<=633);
 }
 assert.notEqual(invoke(seed,'missing').status,0);
 assert.notEqual(invoke({...seed,price:-1},'negative',['--draft']).status,0);
 assert.notEqual(invoke({...seed,title:'W'.repeat(100)},'overflow',['--draft']).status,0);
 assert.notEqual(invoke({...seed,rewards:[]},'empty',['--draft']).status,0);
 // This synthetic asset is a test fixture, never a final illustration.
 const png=path.join(root,'fixture.png');
 await sharp({create:{width:32,height:32,channels:4,background:{r:80,g:120,b:180,alpha:0.5}}}).png().toFile(png);
 const full={...seed,hero:png,currencyIcon:png,rewards:seed.rewards.map(r=>({...r,asset:png}))};
 const good=invoke(full,'complete'); assert.equal(good.status,0,good.stderr);
 const rerun=spawnSync(process.execPath,[renderer,path.join(good.out,'config.json'),path.join(root,'portable')],{encoding:'utf8'});
 assert.equal(rerun.status,0,rerun.stderr);
 assert.equal(fs.readFileSync(path.join(good.out,'preview.png')).equals(fs.readFileSync(path.join(root,'portable','preview.png'))),true);
 console.log('PASS: 6 adaptive layouts, Cyrillic, input rejection, final assets, portable deterministic rebuild. Fixtures: '+root);
})().catch(e=>{console.error(e);process.exitCode=1});
