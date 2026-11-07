// Deterministic vector composition; PNGs are embedded unchanged, never cropped.
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');
const [input, output, ...flags] = process.argv.slice(2);
const draft = flags.includes('--draft');
const esc = s => String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]));
const fail = s => { throw new Error(s); };
async function main() {
  if (!input || !output) fail('Usage: node render.cjs config.json output-directory [--draft]');
  const c = JSON.parse(fs.readFileSync(input, 'utf8').replace(/^\uFEFF/,''));
  const base = path.dirname(path.resolve(input));
  for (const k of ['title','offer']) if(typeof c[k] !== 'string' || !c[k].trim()) fail(k+' is required');
  if(!Number.isSafeInteger(c.price) || c.price < 0 || c.price > 999999) fail('price must be an integer 0..999999');
  if(!Array.isArray(c.rewards) || c.rewards.length < 1 || c.rewards.length > 6) fail('Use 1..6 rewards');
  const p = c.palette;
  for(const k of ['top','bottom','accent','panel','offerText']) if(!/^#[0-9a-f]{6}$/i.test(p?.[k])) fail('Invalid palette.'+k);
  const missing = [], retainedAssets = [];
  async function asset(v, key) {
    if(!v) { if(!draft) fail('Missing '+key); missing.push(key); return ''; }
    const file = path.resolve(base,v), data = fs.readFileSync(file), meta = await sharp(data).metadata();
    if(meta.format !== 'png' || !meta.hasAlpha) fail(key+' must be a PNG with an alpha channel');
    retainedAssets.push({key, data, name:'asset-'+retainedAssets.length+'.png'});
    return 'data:image/png;base64,'+data.toString('base64');
  }
  const hero = await asset(c.hero,'hero'), currency = await asset(c.currencyIcon,'currencyIcon');
  const rewards = [];
  for(let i=0;i<c.rewards.length;i++) {
    const r=c.rewards[i];
    if(typeof r.label!=='string'||!r.label.trim()||r.label.length>10) fail('Reward label must contain 1..10 characters');
    rewards.push({...r, uri:await asset(r.asset,'reward '+(i+1))});
  }
  const textNodes=[];
  function label(text,x,y,width,height,max,min,color,key) {
    // Conservative fitting; visual review is still required for the selected font.
    const len=Array.from(text).reduce((s,ch)=>s+(/[MWШЩЮЖ]/.test(ch)?1:ch===' '?0.33:0.67),0);
    const size=Math.min(max, width/Math.max(1,len));
    if(size<min) fail(key+' is too long; shorten it before rendering');
    textNodes.push({key,text,x,y,width,height,fontSize:Math.floor(size),color});
  }
  label(c.title,105,60,435,58,42,28,'#FFFFFF','title');
  label(c.offer,65,416,519,66,40,27,p.offerText,'offer');
  label(String(c.price),710,493,220,62,48,30,'#FFFFFF','price');
  const rect=(x,y,w,h,r,fill,extra='')=>`<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" fill="${fill}" ${extra}/>`;
  const pic=(uri,x,y,w,h)=>`<image href="${uri}" x="${x}" y="${y}" width="${w}" height="${h}" preserveAspectRatio="xMidYMid meet"/>`;
  const placeholder=(x,y,w,h,name)=>`<g>${rect(x,y,w,h,15,'#EEF3FA','stroke="#7B8DA5" stroke-width="3" stroke-dasharray="8 5"')}<text x="${x+w/2}" y="${y+h/2}" text-anchor="middle" fill="#46556B" font-family="Arial" font-size="18">${name}</text></g>`;
  let body=rect(8,16,984,609,84,p.bottom)+`<g clip-path="url(#outer)">`+rect(8,8,984,609,84,'url(#top)');
  for(let i=0;i<9;i++) body+=`<path d="M800 325 L${-500+i*220} -100 L${-380+i*220} -100Z" fill="white" opacity=".09"/>`;
  body+=`<path d="M0 406 H600 Q780 406 1000 220 V640 H0Z" fill="url(#bottom)"/><path d="M0 480 Q440 660 1000 400 V633 H0Z" fill="#003C36" opacity=".13"/></g>`;
  body+=rect(18,18,964,586,75,'none','stroke="white" stroke-opacity=".35" stroke-width="9"');
  body+=rect(85,54,475,84,42,p.accent)+rect(85,48,475,80,40,'url(#pill)','stroke="white" stroke-opacity=".2" stroke-width="4"');
  body+=rect(42,166,565,340,55,'#003C36','opacity=".16"');
  body+=`<g clip-path="url(#panel)">`+rect(42,160,565,340,55,p.panel,'fill-opacity=".95"')+rect(42,406,565,94,0,p.bottom,'fill-opacity=".43"')+`</g>`;
  body+=rect(49,167,551,326,49,'none','stroke="white" stroke-opacity=".65" stroke-width="9"');
  const rows = rewards.length>4?2:1, cols=rows===2?3:rewards.length;
  rewards.forEach((r,i)=> {
    const row=Math.floor(i/cols), count=rows===2 && row===1?rewards.length-cols:cols;
    const cw=521/cols, start=64+(521-count*cw)/2, x=start+(i%cols)*cw;
    const y=182+row*109, ih=rows===2?72:163, iw=Math.min(cw-16,ih);
    body+=r.uri?pic(r.uri,x+(cw-iw)/2,y,iw,ih):placeholder(x+(cw-iw)/2,y,iw,ih,'ITEM '+(i+1));
    label(r.label,x+6,y+ih+1,cw-12,rows===2?30:42,rows===2?23:30,18,'#794619','reward'+(i+1));
  });
  body+=hero?pic(hero,610,42,350,435):placeholder(630,70,310,390,'HERO — DRAFT');
  body+=rect(645,484,310,100,32,'#176A29')+rect(645,475,310,100,32,'url(#button)','stroke="#B7F799" stroke-width="3"');
  const defs=`<defs><clipPath id="outer">${rect(8,8,984,609,84,'white')}</clipPath><clipPath id="panel">${rect(42,160,565,340,55,'white')}</clipPath><linearGradient id="top" x2="0" y2="1"><stop stop-color="${p.top}"/><stop offset="1" stop-color="${p.accent}"/></linearGradient><linearGradient id="bottom" x2="0" y2="1"><stop stop-color="${p.bottom}"/><stop offset="1" stop-color="${p.bottom}"/><stop offset="1" stop-color="#006C58"/></linearGradient><linearGradient id="pill" x2="0" y2="1"><stop stop-color="${p.top}"/><stop offset="1" stop-color="${p.accent}"/></linearGradient><linearGradient id="button" x2="0" y2="1"><stop stop-color="#8FE36A"/><stop offset=".55" stop-color="#4FC13F"/><stop offset="1" stop-color="#3FAE3F"/></linearGradient></defs>`;
  const font=esc(c.fontFamily||'Arial Black, Arial');
  const texts=textNodes.map(t=>`<text x="${t.x+t.width/2}" y="${t.y+t.height/2+t.fontSize*.35}" text-anchor="middle" font-family="${font}" font-weight="900" font-size="${t.fontSize}" fill="${t.color}" stroke="#000000" stroke-opacity=".12" stroke-width="1.5" paint-order="stroke">${esc(t.text)}</text>`).join('');
  const icon=currency?pic(currency,671,505,33,33):`<path d="M687 505L704 514V532L687 541L670 532V514Z" fill="none" stroke="white" stroke-width="4"/>`;
  const wrap=b=>`<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="633" viewBox="0 0 1000 633">${defs}${b}</svg>`;
  fs.mkdirSync(output,{recursive:true});
  for(const [name,svg] of [['preview',wrap(body+texts+icon)],['artwork',wrap(body)]]) {
    fs.writeFileSync(path.join(output,name+'.svg'),svg);
    await sharp(Buffer.from(svg)).png().toFile(path.join(output,name+'.png'));
  }
  await sharp(path.join(output,'preview.png')).resize(290,184).png().toFile(path.join(output,'shop-size.png'));
  fs.writeFileSync(path.join(output,'layout.json'),JSON.stringify({canvas:{width:1000,height:633},splitY:406,button:{x:645,y:475,width:310,height:100},currency:{x:671,y:505,width:33,height:33},textNodes},null,2));
  fs.writeFileSync(path.join(output,'qa.json'),JSON.stringify({status:draft?'draft':'ready-for-visual-review',missing,visualReviewRequired:true,rewardCount:rewards.length,rows,fontFamily:c.fontFamily||'Arial Black, Arial'},null,2));
  const portable=JSON.parse(JSON.stringify(c));
  fs.mkdirSync(path.join(output,'inputs'),{recursive:true});
  for(const a of retainedAssets) {
    fs.writeFileSync(path.join(output,'inputs',a.name),a.data);
    const rel='inputs/'+a.name;
    if(a.key.startsWith('reward ')) portable.rewards[Number(a.key.split(' ')[1])-1].asset=rel;
    else portable[a.key]=rel;
  }
  fs.writeFileSync(path.join(output,'config.json'),JSON.stringify(portable,null,2));
  console.log(JSON.stringify({output:path.resolve(output),status:draft?'draft':'ready-for-visual-review'}));
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
