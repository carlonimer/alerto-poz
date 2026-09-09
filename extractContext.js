const fs = require('fs');
const path = 'C:/Users/carlo/.gemini/antigravity-ide/brain/43997ce7-85c8-45e2-ad0e-478eb8e03bc4/.system_generated/logs/transcript_full.jsonl';
const lines = fs.readFileSync(path, 'utf8').split('\n');
let maxContent = '';
for (let line of lines) {
    if (!line) continue;
    try {
        const obj = JSON.parse(line);
        const text = obj.content;
        if (!text) continue;
        
        // Find if client/web/app.js is mentioned and file_content exists
        if (text.includes('client\\\\web\\\\app.js') || text.includes('client/web/app.js')) {
            let matches = text.match(/<file_content>(.*?)<\/file_content>/gs);
            if (matches) {
                for (let match of matches) {
                    if (match.length > maxContent.length && match.includes('class CitizenApp')) {
                        maxContent = match;
                    }
                }
            }
        }
    } catch(e) {}
}
if (maxContent) {
    fs.writeFileSync('C:/Users/carlo/.gemini/antigravity-ide/scratch/alerto-poz/client/web/app_recovered.js', maxContent);
    console.log('Recovered! Length:', maxContent.length);
} else {
    console.log('No file_content block found for app.js.');
}

