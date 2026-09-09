(async () => {
    const puppeteer = require('puppeteer');
    const browser = await puppeteer.launch();
    const page = await browser.newPage();
    page.on('console', msg => console.log('PAGE LOG:', msg.text()));
    page.on('pageerror', error => console.log('PAGE ERROR:', error.message));
    
    await page.goto('http://localhost:3000/mobile/', { waitUntil: 'networkidle2' });
    
    // Check if register button is visible
    const registerBtnVisible = await page.evaluate(() => {
        const btn = document.getElementById('signup-toggle-action');
        return btn !== null && btn.offsetParent !== null;
    });
    console.log("Register button visible:", registerBtnVisible);
    
    if (registerBtnVisible) {
        await page.click('#signup-toggle-action');
        
        // Wait a bit for transition
        await new Promise(r => setTimeout(r, 500));
        
        // Check if register card is visible
        const registerCardVisible = await page.evaluate(() => {
            const card = document.getElementById('auth-register-card');
            return card !== null && !card.classList.contains('hidden');
        });
        console.log("Register card visible after click:", registerCardVisible);
    }
    
    await browser.close();
})();
