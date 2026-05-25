const sharp = require('sharp'); const fs = require('fs');
const dir='newsvg', out='newpng';
if(!fs.existsSync(out)) fs.mkdirSync(out);
(async()=>{
  const dims = fs.existsSync('dpng/dims.json') ? JSON.parse(fs.readFileSync('dpng/dims.json')) : {};
  for (const f of fs.readdirSync(dir).filter(f=>f.endsWith('.svg'))) {
    const base=f.replace('.svg','');
    const buf=await sharp(fs.readFileSync(dir+'/'+f),{density:200}).flatten({background:'#ffffff'}).png().toBuffer();
    fs.writeFileSync(out+'/'+base+'.png', buf);
    const m=await sharp(buf).metadata();
    dims[base]={w:m.width,h:m.height};
    // also copy png into dpng so build-deck can find via IMG()
    fs.writeFileSync('dpng/'+base+'.png', buf);
    console.log(base, m.width+'x'+m.height);
  }
  fs.writeFileSync('dpng/dims.json', JSON.stringify(dims,null,2));
})();
