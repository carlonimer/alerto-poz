const fs = require('fs');
const path = 'C:/Users/carlo/.gemini/antigravity-ide/brain/43997ce7-85c8-45e2-ad0e-478eb8e03bc4/.system_generated/logs/transcript_full.jsonl';
const lines = fs.readFileSync(path, 'utf8').split('\n');
const fileLines = [];
for (let line of lines) {
    if (!line) continue;
    try {
        const obj = JSON.parse(line);
        if (obj.content && obj.content.toLowerCase().includes('client/web/app.js')) {
            const linesData = obj.content.split('\n');
            for(let l of linesData) {
                const match = l.match(/^(\d+):\s(.*)/);
                if(match) {
                    const lineNum = parseInt(match[1]);
                    const text = match[2];
                    fileLines[lineNum] = text;
                }
            }
        }
    } catch(e) {}
}

let recoveredLinesCount = 0;
for(let i = 1; i < fileLines.length; i++) {
    if(fileLines[i] !== undefined) recoveredLinesCount++;
}
console.log('Recovered ' + recoveredLinesCount + ' unique lines from view_file outputs.');
if(recoveredLinesCount > 0) {
    fs.writeFileSync('C:/Users/carlo/.gemini/antigravity-ide/scratch/alerto-poz/client/web/app_stitched.js', fileLines.join('\n'));
}

