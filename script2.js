const fs = require('fs');
const path = 'C:/Users/carlo/.gemini/antigravity-ide/brain/43997ce7-85c8-45e2-ad0e-478eb8e03bc4/.system_generated/logs/transcript_full.jsonl';
const lines = fs.readFileSync(path, 'utf8').split('\n');
let maxContent = '';
for (let line of lines) {
    if (!line) continue;
    try {
        const obj = JSON.parse(line);
        let str = JSON.stringify(obj);
        if (str.includes('class CitizenApp')) {
            console.log('Found match! Keys:', Object.keys(obj), 'Source:', obj.source, 'Type:', obj.type);
            fs.appendFileSync('recovered2.txt', str + '\n');
        }
    } catch(e) {}
}

