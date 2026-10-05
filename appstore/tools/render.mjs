/** Render original simulator captures inside a phone frame without modifying app UI. */
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const sharp = require(process.env.SHARP_MODULE || 'sharp');
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const content = JSON.parse(await fs.readFile(path.join(root, 'tools/content.json'), 'utf8'));
const scenes = ['overview', 'swipe', 'filters', 'resize', 'final'];
const esc = s => s.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const family = 'Arial, Hiragino Sans, Apple SD Gothic Neo, sans-serif';
const text = (s, x, y, size, weight=400, color='#6B5D77') => `<text x="${x}" y="${y}" font-family="${family}" font-size="${size}" font-weight="${weight}" fill="${color}">${esc(s)}</text>`;
// Use rendered glyph bounds, including CJK fallback fonts, to fit headline copy.
async function fit(lines, maximum, size, weight) {
  while (size >= 24) {
    const widths = await Promise.all(lines.map(async s => {
      const {info} = await sharp(Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="2200" height="220">${text(s,10,150,size,weight,'#000')}</svg>`)).trim().toBuffer({resolveWithObject:true});
      return info.width;
    }));
    if (Math.max(...widths) <= maximum) break;
    size -= 2;
  }
  return size;
}
function wrap(s) {
  const units = /[\u3040-\u30ff\u3400-\u9fff]/u.test(s) ? [...s] : s.split(' ');
  const separator = /[\u3040-\u30ff\u3400-\u9fff]/u.test(s) ? '' : ' ';
  const lines = []; let line = '';
  for (const unit of units) {
    const candidate = line ? line + separator + unit : unit;
    const estimate = [...candidate].reduce((sum,c) => sum + (/[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]/u.test(c) ? 1 : 0.52),0);
    if (estimate * 38 > 1040 && line) { lines.push(line); line=unit; } else line=candidate;
  }
  if (line) lines.push(line);
  return lines;
}
const icon = (await fs.readFile(path.resolve(root,'../branding/Pruney-AppStore-1024.png'))).toString('base64');
const manifest = [];
for (const [language,c] of Object.entries(content)) {
  const destination = path.join(root,language); await fs.mkdir(destination,{recursive:true});
  for (const [key,limit] of [['name',30],['subtitle',30],['promotional',170],['description',4000]]) {
    if ([...c[key]].length > limit) throw new Error(`${language}: ${key} exceeds ${limit}`);
  }
  if (Buffer.byteLength(c.keywords,'utf8') > 100) throw new Error(`${language}: keywords exceed 100 bytes`);
  await fs.writeFile(path.join(destination,'metadata.txt'), [['Name','name'],['Subtitle','subtitle'],['Promotional Text','promotional'],['Description','description'],['Keywords','keywords']].map(([label,key])=>`${label}\n${c[key]}`).join('\n\n')+'\n');
  for (let i=0;i<scenes.length;i++) {
    const screenshot = await fs.readFile(path.join(root,'source-screens',language,`${scenes[i]}.png`));
    const raw = await sharp(screenshot).metadata();
    if (raw.width !== 1242 || raw.height !== 2688) throw new Error('Unexpected native capture dimensions');
    const [headlines, subtitle] = c.screens[i];
    const size = await fit(headlines,1050,88,700);
    const sublines = wrap(subtitle);
    const subsize = await fit(sublines,1050,38,400);
    const headings = headlines.map((s,j)=>text(s,96,278+j*106,size,700,'#2D183E')).join('');
    const subs = sublines.map((s,j)=>text(s,98,472+j*49,subsize)).join('');
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1242" height="2688" viewBox="0 0 1242 2688">
      <defs>
        <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#FCF9FF"/><stop offset="1" stop-color="#E7D9F1"/></linearGradient>
        <linearGradient id="rim"><stop stop-color="#77707D"/><stop offset="0.13" stop-color="#161319"/><stop offset="0.86" stop-color="#151219"/><stop offset="1" stop-color="#827789"/></linearGradient>
        <filter id="shadow" x="-30%" y="-10%" width="160%" height="140%"><feGaussianBlur stdDeviation="27"/></filter>
        <clipPath id="screen"><rect x="179" y="646" width="884" height="1913.24" rx="86"/></clipPath>
        <clipPath id="icon"><rect x="96" y="84" width="72" height="72" rx="18"/></clipPath>
      </defs>
      <rect width="1242" height="2688" fill="url(#bg)"/>
      <ellipse cx="1110" cy="1690" rx="570" ry="850" fill="#C9B2DE" opacity=".20"/>
      <ellipse cx="50" cy="2650" rx="780" ry="380" fill="#E2D1EC" opacity=".65"/>
      <image x="96" y="84" width="72" height="72" xlink:href="data:image/png;base64,${icon}" clip-path="url(#icon)"/>
      ${text('Pruney',190,135,43,700,'#4E2C69')}
      ${headings}${subs}
      <rect x="164" y="665" width="914" height="1914" rx="108" fill="#3F1D54" opacity=".24" filter="url(#shadow)"/>
      <rect x="152" y="835" width="10" height="112" rx="5" fill="#433A4A"/>
      <rect x="152" y="978" width="10" height="112" rx="5" fill="#433A4A"/>
      <rect x="1080" y="929" width="10" height="175" rx="5" fill="#433A4A"/>
      <rect x="160" y="625" width="922" height="1955" rx="109" fill="url(#rim)" stroke="#C8BECD" stroke-width="3"/>
      <rect x="169" y="635" width="904" height="1935" rx="99" fill="#08070A"/>
      <image x="179" y="646" width="884" height="1913.24" xlink:href="data:image/png;base64,${screenshot.toString('base64')}" clip-path="url(#screen)"/>
      <path d="M478 646H764V673Q764 704 733 704H509Q478 704 478 673Z" fill="#08070A"/>
      <rect x="574" y="661" width="91" height="8" rx="4" fill="#242029"/>
      <circle cx="696" cy="665" r="7" fill="#121A29"/>
    </svg>`;
    const file = `${String(i+1).padStart(2,'0')}-${scenes[i]}.png`;
    await sharp(Buffer.from(svg)).removeAlpha().png().toFile(path.join(destination,file));
    manifest.push({language,file,width:1242,height:2688,scene:scenes[i]});
  }
  console.log(`Rendered ${language}: 5 screenshots and metadata`);
}
await fs.writeFile(path.join(root,'manifest.json'),JSON.stringify({size:'6.5-inch',screenshots:manifest},null,2)+'\n');
const thumbs = [];
for (const language of Object.keys(content)) {
  const file = path.join(root,language,'01-overview.png');
  thumbs.push(await sharp(file).resize(248,537).toBuffer());
}
await sharp({create:{width:1240,height:1074,channels:3,background:'#eee5f5'}}).composite(thumbs.map((input,i)=>({input,left:(i%5)*248,top:Math.floor(i/5)*537}))).png().toFile(path.join(root,'all-languages-preview.png'));
const english = await Promise.all(scenes.map((scene,i)=>sharp(path.join(root,'en',`${String(i+1).padStart(2,'0')}-${scene}.png`)).resize(310,672).toBuffer()));
await sharp({create:{width:1550,height:672,channels:3,background:'#eee5f5'}}).composite(english.map((input,i)=>({input,left:i*310,top:0}))).png().toFile(path.join(root,'english-preview.png'));
