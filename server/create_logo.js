const sharp = require('sharp');
const fs = require('fs');
const path = require('path');

async function generateLogos() {
    // 1. Adaptive Foreground (Transparent BG, White elements)
    // We'll use a viewBox of 1024x1024.
    // The podcast/radio icon is a bit complex, let's use a nice path for it.
    // Radio icon path (Material Icons: podcasts)
    const radioPath = `M654.55 410.73c-23.47-23.47-55.89-38.06-91.55-38.06s-68.08 14.59-91.55 38.06l30.13 30.13c15.74-15.74 37.49-25.53 61.42-25.53s45.68 9.79 61.42 25.53l30.13-30.13zM745.1 320.18C698.63 273.71 634.32 245 563 245s-135.63 28.71-182.1 75.18l30.13 30.13c41.36-41.36 98.47-66.97 151.97-66.97s110.61 25.61 151.97 66.97l30.13-30.13zM835.65 229.63C765.85 159.83 668.74 117.33 563 117.33S360.15 159.83 290.35 229.63l30.13 30.13C382.68 197.61 468.16 160 563 160s180.32 37.61 242.52 99.76l30.13-30.13zM563 670.67c46.94 0 85.33-38.39 85.33-85.33V500H477.67v85.33c0 46.94 38.39 85.34 85.33 85.34z`;

    const svgForeground = `
        <svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
            <g transform="translate(100, 100) scale(0.8)">
                <!-- Radio Icon Centered -->
                <path d="${radioPath}" fill="#FFFFFF" transform="translate(-50, 0) scale(1.1)"/>
                <!-- Text -->
                <text x="512" y="850" font-family="Arial, sans-serif" font-weight="900" font-size="160" fill="#FFFFFF" text-anchor="middle" letter-spacing="4">ALERTO-POZ</text>
            </g>
        </svg>
    `;

    // 2. iOS / Legacy Android (Orange BG, White elements)
    const svgFull = `
        <svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
            <!-- Orange Background -->
            <rect width="1024" height="1024" fill="#FF5722"/>
            <g transform="translate(100, 100) scale(0.8)">
                <path d="${radioPath}" fill="#FFFFFF" transform="translate(-50, 0) scale(1.1)"/>
                <text x="512" y="850" font-family="Arial, sans-serif" font-weight="900" font-size="160" fill="#FFFFFF" text-anchor="middle" letter-spacing="4">ALERTO-POZ</text>
            </g>
        </svg>
    `;

    const assetsDir = path.join(__dirname, '../mobile_app/assets');
    
    // Create high-res PNGs
    await sharp(Buffer.from(svgForeground))
        .png()
        .toFile(path.join(assetsDir, 'icon_foreground.png'));
        
    await sharp(Buffer.from(svgFull))
        .png()
        .toFile(path.join(assetsDir, 'icon_full.png'));

    console.log("Logos generated successfully!");
}

generateLogos().catch(console.error);
