const fs = require('fs');
const path = require('path');
const wsDir = 'C:/Users/carlo/AppData/Roaming/Code/User/workspaceStorage';
function searchDir(dir) {
    if(!fs.existsSync(dir)) return;
    const files = fs.readdirSync(dir);
    for(let f of files) {
        const fullPath = path.join(dir, f);
        try {
            const stat = fs.statSync(fullPath);
            if(stat.isDirectory()) {
                searchDir(fullPath);
            } else if (stat.isFile() && stat.size > 50000 && stat.size < 200000) {
                const content = fs.readFileSync(fullPath, 'utf8');
                if(content.includes('class CitizenApp {')) {
                    console.log('FOUND IT IN WS STORAGE:', fullPath);
                    fs.writeFileSync('C:/Users/carlo/.gemini/antigravity-ide/scratch/alerto-poz/client/web/app_recovered.js', content);
                }
            }
        } catch(e){}
    }
}
searchDir(wsDir);

