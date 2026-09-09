const fs = require('fs');
const content = fs.readFileSync('client/mobile/app.js', 'utf8');
const html = fs.readFileSync('client/mobile/index.html', 'utf8');
const regex = /this\.([a-zA-Z0-9_]+)\.addEventListener/g;
let match;
const missing = [];
while ((match = regex.exec(content)) !== null) {
    const varName = match[1];
    const idMatch = content.match(new RegExp(`this\\.${varName} = document\\.getElementById\\("([^"]+)"\\)`));
    if (idMatch) {
        const id = idMatch[1];
        if (!html.includes(`id="${id}"`)) missing.push(id);
    }
}
console.log('Missing IDs:', missing);
