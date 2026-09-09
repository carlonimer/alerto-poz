const fs = require('fs');
const html = fs.readFileSync('C:/Users/carlo/.gemini/antigravity-ide/scratch/alerto-poz/client/web/index.html', 'utf8');
const js = fs.readFileSync('C:/Users/carlo/.gemini/antigravity-ide/scratch/alerto-poz/client/web/app.js', 'utf8');
const matches = js.match(/document\.getElementById\(['\x22](.*?)['\x22]\)/g);
const missing = new Set();
if(matches) {
    for(let m of matches) {
        const id = m.match(/['\x22](.*?)['\x22]/)[1];
        if(!html.includes('id=\x22' + id + '\x22') && !html.includes('id=\'' + id + '\'')) {
            missing.add(id);
        }
    }
}
console.log('Missing IDs in HTML:', Array.from(missing));

