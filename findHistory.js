const fs = require('fs');
const path = require('path');
const historyDir = 'C:/Users/carlo/AppData/Roaming/Code/User/History';
if(fs.existsSync(historyDir)) {
    const folders = fs.readdirSync(historyDir);
    for(let f of folders) {
        const entryFile = path.join(historyDir, f, 'entries.json');
        if(fs.existsSync(entryFile)) {
            try {
                const data = JSON.parse(fs.readFileSync(entryFile, 'utf8'));
                if(data.resource && data.resource.includes('client/web/app.js')) {
                    console.log('FOUND IT IN FOLDER:', f);
                    const files = fs.readdirSync(path.join(historyDir, f));
                    console.log('Files:', files);
                }
            } catch(e){}
        }
    }
}
