const fs = require('fs');
let code = fs.readFileSync('client/web/app.js', 'utf8');

// Replace all instances of document.getElementById('...').addEventListener('...', () => { ... })
// with a safe check.
code = code.replace(/document\.getElementById\((['"])([^'"]+)\1\)\.addEventListener\((['"])([^'"]+)\3,\s*/g, (match, p1, id, p3, event) => {
    let varName = '__el_' + id.replace(/[^a-zA-Z0-9]/g, '_');
    return 'const ' + varName + ' = document.getElementById("' + id + '"); if (' + varName + ') ' + varName + '.addEventListener("' + event + '", ';
});

fs.writeFileSync('client/web/app.js', code);
console.log('Patched');
