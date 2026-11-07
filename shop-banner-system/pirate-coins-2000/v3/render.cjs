const fs=require('node:fs'), path=require('node:path'), sharp=require('sharp');
sharp.concurrency(1);
sharp.cache(false);
const dir=__dirname;
const img=name=>'data:image/png;base64,'+fs.readFileSync(path.join(dir,'../assets',name)).toString('base64');
const rect=(x,y,w,h,r,fill,extra='')=>`<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" fill="${fill}" ${extra}/>`;
const picture=(name,x,y,w,h)=>`<image href="${img(name)}" x="${x}" y="${y}" width="${w}" height="${h}" preserveAspectRatio="xMidYMid meet"/>`;
const star=(x,y,r,opacity=1)=>`<path d="M${x} ${y-r} Q${x+3} ${y-3} ${x+r*.72} ${y} Q${x+3} ${y+3} ${x} ${y+r} Q${x-3} ${y+3} ${x-r*.72} ${y} Q${x-3} ${y-3} ${x} ${y-r}Z" fill="white" opacity="${opacity}"/>`;
const defs=`<defs>
<clipPath id="card">${rect(8,8,984,609,84,'white')}</clipPath>
<clipPath id="panel">${rect(42,160,565,340,55,'white')}</clipPath>
<linearGradient id="top" x2="0%" y2="100%"><stop stop-color="#FFD875"/><stop offset=".55" stop-color="#F5B837"/><stop offset="1" stop-color="#EF9E22"/></linearGradient>
<linearGradient id="lower" x2="0%" y2="100%"><stop stop-color="#05C39A"/><stop offset="1" stop-color="#009A79"/></linearGradient>
<linearGradient id="pill" x2="0%" y2="100%"><stop stop-color="#FFC557"/><stop offset=".5" stop-color="#FFAC27"/><stop offset="1" stop-color="#EA8C14"/></linearGradient>
<linearGradient id="glass" x2="0%" y2="100%"><stop stop-color="#FFFFFF" stop-opacity=".8"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></linearGradient>
<linearGradient id="panelFill" x2="0%" y2="100%"><stop stop-color="#FFF9E9"/><stop offset="1" stop-color="#FFECC7"/></linearGradient>
<linearGradient id="ribbon" x2="0%" y2="100%"><stop stop-color="#91E9BD" stop-opacity=".92"/><stop offset="1" stop-color="#50C9A0" stop-opacity=".86"/></linearGradient>
<linearGradient id="button" x2="0%" y2="100%"><stop stop-color="#A0EF65"/><stop offset=".45" stop-color="#65D441"/><stop offset="1" stop-color="#35AB36"/></linearGradient>
<radialGradient id="halo"><stop stop-color="#FFFFFF" stop-opacity=".98"/><stop offset=".32" stop-color="#FFF9CF" stop-opacity=".9"/><stop offset=".7" stop-color="#FFF6B8" stop-opacity=".48"/><stop offset="1" stop-color="#FFF8C9" stop-opacity="0"/></radialGradient>
<radialGradient id="contact"><stop stop-color="#07452F" stop-opacity=".45"/><stop offset="1" stop-color="#07452F" stop-opacity="0"/></radialGradient>
</defs>`;
let b=rect(8,18,984,609,84,'#007E67');
b+=`<g clip-path="url(#card)">`+rect(8,8,984,609,84,'url(#top)');
for(let i=0;i<10;i++) b+=`<path d="M787 345L${-500+i*230} -120L${-420+i*230} -120Z" fill="#FFF8D5" opacity=".15"/>`;
b+=`<path d="M0 406H600Q800 405 1000 260V640H0Z" fill="url(#lower)"/><path d="M0 490Q430 640 1000 423V633H0Z" fill="#006C59" opacity=".17"/>`;
b+=`<ellipse cx="790" cy="345" rx="208" ry="208" fill="url(#halo)"/></g>`;
b+=rect(17,17,966,589,77,'none','stroke="#FFEFAC" stroke-opacity=".65" stroke-width="9"');
b+=`<path d="M44 78Q55 37 105 32H880Q943 32 963 79" fill="none" stroke="white" stroke-width="10" opacity=".55" stroke-linecap="round"/>`;
b+=rect(85,70,475,70,35,'#B9740D','opacity=".3"')+rect(85,62,475,70,35,'url(#pill)','stroke="#FFE7A2" stroke-width="4"');
b+=`<path d="M111 82Q122 73 151 73H484" fill="none" stroke="white" stroke-opacity=".32" stroke-width="6" stroke-linecap="round"/>`;
b+=star(126,100,17,.86)+star(521,100,17,.86);
b+=rect(42,169,565,340,55,'#005E4E','opacity=".19"');
b+=`<g clip-path="url(#panel)">`+rect(42,160,565,340,55,'url(#panelFill)')+rect(42,406,565,94,0,'url(#ribbon)')+`<path d="M45 410H604" stroke="white" stroke-opacity=".44" stroke-width="3"/></g>`;
b+=rect(49,167,551,326,49,'none','stroke="white" stroke-opacity=".66" stroke-width="9"');
b+=`<path d="M66 209Q70 181 97 180" fill="none" stroke="white" stroke-width="12" stroke-linecap="round" opacity=".85"/>`;
b+=picture('coin.png',220,176,208,208);
// Amount badge overlaps the reward art, like the reference's bonus item badge.
b+=`<path d="M215 304L196 311L207 327L195 342L224 341M433 304L452 311L441 327L453 342L424 341" fill="#9B2543" stroke="#5A1E29" stroke-width="3"/>`;
b+=rect(220,306,208,84,21,'#532321','stroke="#54241C" stroke-width="6"');
b+=rect(213,301,222,36,12,'#D64758','stroke="#782734" stroke-width="4"');
b+=`<path d="M228 307H420" stroke="#FF9A9C" stroke-width="3" stroke-linecap="round"/>`;
b+=star(96,451,24)+star(552,451,24);
b+=`<ellipse cx="795" cy="508" rx="153" ry="32" fill="url(#contact)"/>`;
// Simpler squat sack sits lower; button occludes its base for depth.
b+=picture('bag-simple.png',640,211,300,315);
b+=star(923,287,12,.8)+star(654,342,9,.6);
b+=rect(645,484,310,100,32,'#176A29')+rect(645,475,310,100,32,'url(#button)','stroke="#A7EE78" stroke-width="3"');
b+=`<path d="M667 489Q680 483 695 483H910Q930 483 939 497" fill="none" stroke="white" stroke-opacity=".43" stroke-width="5" stroke-linecap="round"/>`;
const lettering=JSON.parse(fs.readFileSync(path.join(dir,'lettering.json'),'utf8'));
const wrap=content=>`<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="633" viewBox="0 0 1000 633">${defs}${content}</svg>`;
(async()=>{
 const full=wrap(b+lettering.map(t=>t.svg).join('')+picture('robux.png',693,513,29,29));
 for(const [name,data] of [['preview',full],['artwork',wrap(b)]]){
  fs.writeFileSync(path.join(dir,name+'.svg'),data);
  await sharp(Buffer.from(data)).png().toFile(path.join(dir,name+'.png'));
 }
 await sharp(Buffer.from(full)).resize(290,184).png().toFile(path.join(dir,'shop-size.png'));
 fs.writeFileSync(path.join(dir,'layout.json'),JSON.stringify({canvas:[1000,633],splitY:406,hero:{x:640,y:211,width:300,height:315},button:{x:645,y:475,width:310,height:100},currency:{x:693,y:513,width:29,height:29},font:'Nunito Black, outlines embedded in SVG',texts:lettering.map(({svg,...t})=>t)},null,2));
 console.log('Rendered v3: English copy, integrated 2,000 coin badge, factual 20 coins per Robux, redesigned lower sack.');
})().catch(e=>{console.error(e);process.exitCode=1});
