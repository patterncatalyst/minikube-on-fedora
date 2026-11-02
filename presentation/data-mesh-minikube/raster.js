const sharp = require('sharp');
const fs = require('fs');
const path = require('path');
const dir = 'dimg';
const out = 'dpng';
if (!fs.existsSync(out)) fs.mkdirSync(out);
(async () => {
  const files = fs.readdirSync(dir).filter(f => f.endsWith('.svg'));
  const dims = {};
  for (const f of files) {
    const base = f.replace('.svg','');
    const svg = fs.readFileSync(path.join(dir,f));
    // render at ~2x for crispness; flatten onto white
    const img = sharp(svg, { density: 200 }).flatten({ background: '#ffffff' });
    const meta = await img.metadata();
    const buf = await img.png().toBuffer();
    fs.writeFileSync(path.join(out, base+'.png'), buf);
    const m2 = await sharp(buf).metadata();
    dims[base] = { w: m2.width, h: m2.height };
    console.log(base, m2.width+'x'+m2.height);
  }
  fs.writeFileSync('dpng/dims.json', JSON.stringify(dims,null,2));
})();
