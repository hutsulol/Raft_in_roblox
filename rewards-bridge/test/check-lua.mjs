import fs from 'node:fs';
import luaparse from 'luaparse';
for (const folder of ['roblox', 'studio']) {
for (const name of fs.readdirSync(folder).filter(n => n.endsWith('.lua'))) {
  const text = fs.readFileSync(`${folder}/${name}`, 'utf8');
  if (text.charCodeAt(0) === 0xfeff) throw new Error(`${name}: BOM`);
  luaparse.parse(text, { luaVersion: '5.1' });
  console.log(`Syntax OK: ${folder}/${name}`);
}
}
