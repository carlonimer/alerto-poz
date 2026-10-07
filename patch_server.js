const fs = require('fs');
let code = fs.readFileSync('server/server.js', 'utf8');

// 1. Wrap the uploadProfile route to catch Multer errors
const targetRouteStart = "app.post('/api/user/profile-picture', uploadProfile.single('profile_image'), async (req, res) => {";
const replacementRouteStart = `app.post('/api/user/profile-picture', (req, res) => {
    uploadProfile.single('profile_image')(req, res, async (err) => {
        if (err) return res.status(400).json({ success: false, message: err.message });
`;
code = code.replace(targetRouteStart, replacementRouteStart);

// We also need to close the wrap at the end of the route
// Let's find the exact end of the route by looking for the /api/user/history route right after it
const targetRouteEnd = `        } catch(e) { res.status(500).json({ error: e.message }); }
});

app.get('/api/user/history/:id', async (req, res) => {`;
const replacementRouteEnd = `        } catch(e) { res.status(500).json({ success: false, message: e.message }); }
    });
});

app.get('/api/user/history/:id', async (req, res) => {`;
code = code.replace(targetRouteEnd, replacementRouteEnd);

// 2. Fix Multer fileFilter to be more permissive with cropped images from mobile
const targetFileFilter = `    fileFilter: (req, file, cb) => {
        const allowedTypes = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp'];
        if (allowedTypes.includes(file.mimetype)) {
            cb(null, true);
        } else {
            cb(new Error("Invalid file type. Only JPG, PNG, and WebP are allowed."));
        }
    }`;
const replacementFileFilter = `    fileFilter: (req, file, cb) => {
        const allowedTypes = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'application/octet-stream'];
        if (allowedTypes.includes(file.mimetype) || file.originalname.match(/\\.(jpg|jpeg|png|webp)$/i)) {
            cb(null, true);
        } else {
            cb(new Error("Invalid file type. Only JPG, PNG, and WebP are allowed."));
        }
    }`;
code = code.replace(targetFileFilter, replacementFileFilter);

fs.writeFileSync('server/server.js', code);
console.log("Patched server.js successfully!");
