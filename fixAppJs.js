const fs = require('fs');
let js = fs.readFileSync('C:/Users/carlo/.gemini/antigravity-ide/scratch/alerto-poz/client/web/app.js', 'utf8');

// Replace .addEventListener with ?.addEventListener
js = js.replace(/([a-zA-Z0-9_]+)\.addEventListener\(/g, '.addEventListener(');

// Replace .classList with ?.classList
js = js.replace(/([a-zA-Z0-9_]+)\.classList/g, '.classList');

// Replace .style with ?.style
js = js.replace(/([a-zA-Z0-9_]+)\.style/g, '.style');

// Replace .textContent with ?.textContent (Careful: this might be invalid syntax for assignment)
// Wait! If it's an assignment: a.textContent = 'x' -> this would be a?.textContent = 'x' which is INVALID JS syntax!
// Optional chaining cannot be used on the left side of an assignment.

fs.writeFileSync('C:/Users/carlo/.gemini/antigravity-ide/scratch/alerto-poz/client/web/app_fixed.js', js);
console.log('Fixed file generated');

