const fs = require('fs');
const content = fs.readFileSync('client/mobile/app.js', 'utf8');
const html = fs.readFileSync('client/mobile/index.html', 'utf8');
const regex = /document\.getElementById\("([^"]+)"\)/g;
let match;
const missing = [];
while ((match = regex.exec(content)) !== null) {
    const id = match[1];
    if (!html.includes(`id="${id}"`)) {
        missing.push(id);
    }
}
console.log('Missing IDs from getElementById:', [...new Set(missing)]);
