const fs = require('fs');
const path = 'C:/Users/carlo/.gemini/antigravity-ide/brain/43997ce7-85c8-45e2-ad0e-478eb8e03bc4/.system_generated/logs/transcript_full.jsonl';
const lines = fs.readFileSync(path, 'utf8').split('\n');
let maxContent = '';
for (let line of lines) {
    if (!line) continue;
    try {
        const obj = JSON.parse(line);
        if (obj.content && obj.content.includes('class CitizenApp {')) {
            if (obj.content.length > maxContent.length) {
                maxContent = obj.content;
            }
        }
    } catch(e) {}
}
fs.writeFileSync('recovered.txt', maxContent);
console.log('Recovered max content length:', maxContent.length);

