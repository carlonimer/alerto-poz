const { Jimp } = require('jimp');

async function main() {
    try {
        console.log("Reading logo.png...");
        const logo = await Jimp.read('mobile_app/assets/logo.png');
        
        // Adaptive icons need the main content to be within the inner ~60% of the image
        const canvasSize = 1024;
        const logoSize = Math.floor(canvasSize * 0.55); // 55% to be safe

        console.log(`Resizing logo to ${logoSize}x${logoSize}...`);
        logo.contain({ w: logoSize, h: logoSize });

        console.log("Creating new transparent canvas...");
        // In Jimp 1.0.0+, we create a new image using the constructor or create method
        // It's safer to just create a new transparent image this way
        const canvas = new Jimp({ width: canvasSize, height: canvasSize, color: 0x00000000 });

        console.log("Compositing...");
        const x = (canvasSize - logoSize) / 2;
        const y = (canvasSize - logoSize) / 2;
        canvas.composite(logo, x, y);

        console.log("Writing icon_foreground.png...");
        await canvas.write('mobile_app/assets/icon_foreground.png');
        console.log("Done!");
    } catch (e) {
        console.error("Error:", e);
    }
}

main();
