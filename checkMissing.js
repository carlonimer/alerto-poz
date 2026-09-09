const fs = require('fs');
const lines = fs.readFileSync('C:/Users/carlo/.gemini/antigravity-ide/scratch/alerto-poz/client/web/app_stitched.js', 'utf8').split('\n');
let missingRanges = [];
let start = null;
for(let i = 1; i <= 2686; i++) {
    if(lines[i] === undefined || lines[i] === '') {
        if(start === null) start = i;
    } else {
        if(start !== null) {
            missingRanges.push(start + '-' + (i - 1));
            start = null;
        }
    }
}
if(start !== null) missingRanges.push(start + '-2686');
console.log('Missing line ranges:', missingRanges.join(', '));

