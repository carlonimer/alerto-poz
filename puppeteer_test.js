(async () => {
    const puppeteer = await import('puppeteer');
    const browser = await puppeteer.default.launch();
    const page = await browser.newPage();
    page.on('console', msg => console.log('PAGE LOG:', msg.text()));
    page.on('pageerror', error => console.log('PAGE ERROR:', error.message));
    page.on('requestfailed', request => console.log('REQUEST FAILED:', request.url(), request.failure().errorText));
    
    await page.goto('http://localhost:3000/mobile/', { waitUntil: 'networkidle2' });
    await browser.close();
})();
