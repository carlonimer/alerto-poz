const fs = require('fs');
const js = fs.readFileSync('c:/Users/carlo/.gemini/antigravity-ide/scratch/alerto-poz/client/web/app.js', 'utf8');
const html = fs.readFileSync('c:/Users/carlo/.gemini/antigravity-ide/scratch/alerto-poz/client/web/index.html', 'utf8');
const regex = /getElementById\(['"]([^'"]+)['"]\)/g;
let match;
while ((match = regex.exec(js)) !== null) {
    const id = match[1];
    if (!html.includes('id="' + id + '"') && !html.includes("id='" + id + "'")) {
        console.log('Missing in HTML: ' + id);
    }
}
