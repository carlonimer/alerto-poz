require('dotenv').config();
const { initDatabase: initializeTables } = require('./database/init');
const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const mysql = require('mysql2/promise');
const bcrypt = require('bcryptjs');
const nodemailer = require('nodemailer');
const twilio = require('twilio');
const crypto = require('crypto');
const multer = require('multer');

// Configure Multer for secure profile picture uploads
const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        const uploadPath = path.join(__dirname, 'public', 'uploads', 'profiles');
        if (!fs.existsSync(uploadPath)) fs.mkdirSync(uploadPath, { recursive: true });
        cb(null, uploadPath);
    },
    filename: (req, file, cb) => {
        const ext = path.extname(file.originalname).toLowerCase();
        const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
        cb(null, 'avatar-' + uniqueSuffix + ext);
    }
});

const uploadProfile = multer({
    storage: storage,
    limits: { fileSize: 5 * 1024 * 1024 }, // 5 MB max
    fileFilter: (req, file, cb) => {
        const allowedTypes = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp'];
        if (allowedTypes.includes(file.mimetype)) {
            cb(null, true);
        } else {
            cb(new Error("Invalid file type. Only JPG, PNG, and WebP are allowed."));
        }
    }
});

// Configure Multer for chat media uploads
const chatMediaStorage = multer.diskStorage({
    destination: (req, file, cb) => {
        const uploadPath = path.join(__dirname, 'public', 'uploads', 'chat');
        if (!fs.existsSync(uploadPath)) fs.mkdirSync(uploadPath, { recursive: true });
        cb(null, uploadPath);
    },
    filename: (req, file, cb) => {
        const ext = path.extname(file.originalname).toLowerCase();
        const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
        cb(null, 'chat-' + uniqueSuffix + ext);
    }
});

const uploadChatMedia = multer({
    storage: chatMediaStorage,
    limits: { fileSize: 50 * 1024 * 1024 }, // 50 MB max for videos
    fileFilter: (req, file, cb) => {
        const allowedTypes = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'video/mp4', 'video/webm'];
        if (allowedTypes.includes(file.mimetype)) {
            cb(null, true);
        } else {
            cb(new Error("Invalid file type. Only JPG, PNG, WebP, MP4, and WebM are allowed."));
        }
    }
});

const app = express();
app.use(cors());
app.use(express.json());

// Serve static client assets directly from server
app.use('/public', express.static(path.join(__dirname, 'public')));
app.use('/uploads', express.static(path.join(__dirname, 'public/uploads')));
app.use('/web', express.static(path.join(__dirname, '../client/web')));
app.use('/dashboard', express.static(path.join(__dirname, '../client/dashboard')));
app.use('/responder', express.static(path.join(__dirname, '../client/responder')));

// Redirect root path dynamically: Mobile devices to /web, Desktops/Laptops to /dashboard
app.get('/', (req, res) => {
    const ua = req.headers['user-agent'] || '';
    const isMobile = /Mobi|Android|iPhone|iPad|Windows Phone|Mobile/i.test(ua);
    if (isMobile) {
        res.redirect('/web');
    } else {
        res.redirect('/dashboard');
    }
});

const server = http.createServer(app);
const io = socketIo(server, {
    cors: {
        origin: "*",
        methods: ["GET", "POST"]
    }
});

// MySQL Database Credentials Configuration
const dbConfig = {
    host: process.env.DB_HOST || '127.0.0.1',
    port: process.env.DB_PORT || 3306,
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD || '',
    database: process.env.DB_NAME || 'alerto_poz',
    ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : undefined
};

// JSON Local Fallback File Database Configuration
const JSON_DB_FILE = path.join(__dirname, 'db.json');
const INITIAL_JSON_DB = {
    users: [
        { id: 1, phone: "09998887777", email: "admin@pozorrubio.gov.ph", password: "$2a$10$ct27geiwLgHJM4GHGgmKbOGGYp67zMdbM1y0XN7ys3hfw6JxV6uUm", name: "Pozorrubio MDRRMO Admin", type: "authority", active: 1, otp_code: null, otp_expires: null, otp_type: null }
    ],
    incidents: [],
    responders: [
        { id: "poz-ems-1", name: "Pozorrubio Ambulance 1", type: "medical", lat: 16.106524, lng: 120.540172, base_lat: 16.106524, base_lng: 120.540172, status: "available", icon: "fa-truck-medical" },
        { id: "poz-ems-2", name: "Pangasinan Red Cross (Manaoag Sub)", type: "medical", lat: 16.0448, lng: 120.4862, base_lat: 16.0448, base_lng: 120.4862, status: "available", icon: "fa-plus-square" },
        { id: "poz-fire-1", name: "Pozorrubio BFP Fire Truck 1", type: "fire", lat: 16.113999, lng: 120.546323, base_lat: 16.113999, base_lng: 120.546323, status: "available", icon: "fa-fire-extinguisher" },
        { id: "poz-police-1", name: "Pozorrubio PNP Mobile Patrol 1", type: "police", lat: 16.109908, lng: 120.545195, base_lat: 16.109908, base_lng: 120.545195, status: "available", icon: "fa-shield-halved" },
        { id: "poz-police-2", name: "Pozorrubio PNP Mobile Patrol 2", type: "police", lat: 16.109908, lng: 120.545195, base_lat: 16.109908, base_lng: 120.545195, status: "available", icon: "fa-shield-halved" }
    ],
    broadcasts: [],
    rescue_vehicles: [],
    water_devices: []
};

let pool = null;
let useMySQL = false;

// 1. Initialise MySQL Connection and Geofenced tables
async function initDatabase() {
    try {
        // Connect without db parameter first to ensure db exists
        const initConn = await mysql.createConnection({
            host: dbConfig.host,
            user: dbConfig.user,
            password: dbConfig.password
        });
        await initConn.query(`CREATE DATABASE IF NOT EXISTS \`${dbConfig.database}\`;`);
        await initConn.end();

        // Instantiate pool
        pool = mysql.createPool(dbConfig);
        
        // Self-healing database structure check
        try {
            const [columns] = await pool.query("SHOW COLUMNS FROM users");
            const hasEmail = columns.some(col => col.Field === 'email');
            if (!hasEmail) {
                console.log("Database schema upgrade: Dropping and recreating users table.");
                await pool.query("DROP TABLE IF EXISTS users;");
            }
        } catch (e) {
            // Table doesn't exist yet, which is fine
        }

        await initializeTables(pool);

        useMySQL = true;
        console.log(`ALERTO-POZ Database Status: MySQL Database "${dbConfig.database}" Initialized Successfully.`);
    } catch (err) {
        useMySQL = false;
        console.warn("ALERTO-POZ Database Status Warning: MySQL Server connection failed.");
        console.warn(`Reason: ${err.message}`);
        console.log("SYSTEM ACTION: falling back to local JSON database simulation (db.json) for offline testing.");
        
        // Setup initial local JSON database if not exists
        if (!fs.existsSync(JSON_DB_FILE)) {
            fs.writeFileSync(JSON_DB_FILE, JSON.stringify(INITIAL_JSON_DB, null, 4));
        }
    }
}

// 2. Database Action Wrappers (Toggles MySQL vs JSON DB seamlessly)
async function logActivity(userId, action, req) {
    const ipAddress = req.headers['x-forwarded-for'] || req.connection.remoteAddress;
    const device = req.headers['user-agent'] || 'Unknown Device';
    const now = new Date();
    const date = now.toISOString().split('T')[0];
    const time = now.toTimeString().split(' ')[0];
    
    if (useMySQL) {
        // Assume activity_logs table exists if mysql is used
        try {
            await pool.query(
                "INSERT INTO activity_logs (userId, action, ipAddress, device, date, time) VALUES (?, ?, ?, ?, ?, ?)",
                [userId, action, ipAddress, device, date, time]
            );
        } catch(e) { console.error("Log error", e); }
    } else {
        const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
        if (!db.activityLogs) db.activityLogs = [];
        db.activityLogs.push({
            id: Date.now(),
            userId,
            action,
            ipAddress,
            device,
            date,
            time
        });
    }
}

async function recordIncidentEvent(incidentId, ticketNumber, eventStatus, previousStatus, newStatus, actorSource) {
    if (!useMySQL) return; // We only support this for MySQL as per instructions
    try {
        const now = new Date();
        const optionsDate = { timeZone: 'Asia/Manila', year: 'numeric', month: 'short', day: '2-digit' };
        const optionsTime = { timeZone: 'Asia/Manila', hour: '2-digit', minute: '2-digit', hour12: true };
        
        const dateStr = new Intl.DateTimeFormat('en-US', optionsDate).format(now);
        const timeStr = new Intl.DateTimeFormat('en-US', optionsTime).format(now);
        const timestamp = now.getTime();

        await pool.query(
            "INSERT INTO incident_events (incident_id, ticket_number, event_status, previous_status, new_status, actor_source, date_str, time_str, timestamp) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [incidentId, ticketNumber || null, eventStatus, previousStatus || null, newStatus || null, actorSource, dateStr, timeStr, timestamp]
        );
        
        // Broadcast the event so active admins/clients can update their history view
        io.emit('incident-event-recorded', {
            incident_id: incidentId,
            ticket_number: ticketNumber,
            event_status: eventStatus,
            previous_status: previousStatus,
            new_status: newStatus,
            actor_source: actorSource,
            date_str: dateStr,
            time_str: timeStr,
            timestamp
        });
    } catch(e) {
        console.error("Failed to record incident event:", e);
    }
}

async function getDBState() {
    if (useMySQL) {
        const [users] = await pool.query("SELECT * FROM users");
        const [incidents] = await pool.query(`
            SELECT i.*, u.profile_image, u.gender 
            FROM incidents i 
            LEFT JOIN users u ON (BINARY i.reporterId = BINARY CAST(u.id AS CHAR) OR BINARY i.reporterPhone = BINARY u.phone) 
            ORDER BY i.createdAt DESC
        `);
        const parsedIncidents = incidents.map(inc => {
            if (inc.media && typeof inc.media === 'string') {
                try { inc.media = JSON.parse(inc.media); } catch(e) { inc.media = []; }
            }
            return inc;
        });
        const [responders] = await pool.query("SELECT * FROM responders");
        const [broadcasts] = await pool.query("SELECT * FROM broadcasts ORDER BY timestamp DESC");
        const [rescue_vehicles] = await pool.query("SELECT * FROM rescue_vehicles");
        const [water_devices] = await pool.query("SELECT * FROM water_devices");
        return { users, incidents: parsedIncidents, responders, broadcasts, rescue_vehicles, water_devices };
    } else {
        const data = fs.readFileSync(JSON_DB_FILE, 'utf8');
        return JSON.parse(data);
    }
}

async function registerUser(phone, pin, name) {
    if (useMySQL) {
        const [exists] = await pool.query("SELECT * FROM users WHERE phone = ?", [phone]);
        if (exists.length > 0) return false;
        
        await pool.query("INSERT INTO users (phone, pin, name, type) VALUES (?, ?, ?, 'citizen')", [phone, pin, name]);
        return true;
    } else {
        const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
        const exists = db.users.find(u => u.phone === phone);
        if (exists) return false;
        
        db.users.push({ phone, pin, name, type: 'citizen' });
        fs.writeFileSync(JSON_DB_FILE, JSON.stringify(db, null, 4));
        return true;
    }
}

async function addIncident(report) {
    if (useMySQL) {
        // Try to get reporter's barangay if missing
        if (!report.barangay && report.reporterPhone) {
            const [u] = await pool.query("SELECT barangay FROM users WHERE phone = ?", [report.reporterPhone]);
            if (u.length > 0 && u[0].barangay) report.barangay = u[0].barangay;
        }
        // Try to resolve reporterId from reporterPhone if not provided
        let reporterId = report.reporterId || null;
        if (!reporterId && report.reporterPhone) {
            const [u] = await pool.query("SELECT id FROM users WHERE phone = ?", [report.reporterPhone]);
            if (u.length > 0) reporterId = u[0].id;
        }
        
        // Try to resolve reporterPhone from reporterId if not provided
        if (!report.reporterPhone && reporterId) {
            const [u] = await pool.query("SELECT phone FROM users WHERE id = ?", [reporterId]);
            if (u.length > 0 && u[0].phone) report.reporterPhone = u[0].phone;
        }

        await pool.query(
            "INSERT INTO incidents (id, category, details, media, lat, lng, reporter, reporterPhone, reporterId, createdAt, networkReceivedAt, barangay, status, assignedUnit, responseProgress) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE category = VALUES(category), details = VALUES(details), media = VALUES(media), status = VALUES(status), assignedUnit = VALUES(assignedUnit), responseProgress = VALUES(responseProgress)",
            [report.id, report.category, report.details, JSON.stringify(report.media || []), report.lat, report.lng, report.reporter, report.reporterPhone, reporterId, report.createdAt, report.networkReceivedAt, report.barangay || null, report.status, report.assignedUnit, report.responseProgress || null]
        );
    } else {
        const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
        const index = db.incidents.findIndex(i => i.id === report.id);
        if (index > -1) {
            db.incidents[index] = report;
        } else {
            db.incidents.unshift(report);
        }
        fs.writeFileSync(JSON_DB_FILE, JSON.stringify(db, null, 4));
    }
}

async function updateIncidentAndResponder(incidentId, responderId, status, responderStatus) {
    if (useMySQL) {
        await pool.query("UPDATE incidents SET status = ?, assignedUnit = ? WHERE id = ?", [status, responderId, incidentId]);
        await pool.query("UPDATE responders SET status = ? WHERE id = ?", [responderStatus, responderId]);
        
        const [inc] = await pool.query("SELECT * FROM incidents WHERE id = ?", [incidentId]);
        const [rep] = await pool.query("SELECT * FROM responders WHERE id = ?", [responderId]);
        return { incident: inc[0], responder: rep[0] };
    } else {
        const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
        const incident = db.incidents.find(i => i.id === incidentId);
        const responder = db.responders.find(r => r.id === responderId);
        
        if (incident && responder) {
            incident.status = status;
            incident.assignedUnit = responderId;
            responder.status = responderStatus;
            fs.writeFileSync(JSON_DB_FILE, JSON.stringify(db, null, 4));
            return { incident, responder };
        }
        return null;
    }
}

async function updateResponderGPS(responderId, lat, lng) {
    if (useMySQL) {
        await pool.query("UPDATE responders SET lat = ?, lng = ? WHERE id = ?", [lat, lng, responderId]);
    } else {
        const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
        const responder = db.responders.find(r => r.id === responderId);
        if (responder) {
            responder.lat = lat;
            responder.lng = lng;
            fs.writeFileSync(JSON_DB_FILE, JSON.stringify(db, null, 4));
        }
    }
}

async function saveBroadcast(broadcast) {
    if (useMySQL) {
        await pool.query(
            "INSERT INTO broadcasts (id, title, category, message, timestamp) VALUES (?, ?, ?, ?, ?)",
            [broadcast.id, broadcast.title, broadcast.category, broadcast.message, broadcast.timestamp]
        );
    } else {
        const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
        db.broadcasts.unshift(broadcast);
        fs.writeFileSync(JSON_DB_FILE, JSON.stringify(db, null, 4));
    }
}

// 3. API Endpoints
app.get('/api/db-type', (req, res) => {
    res.json({ type: useMySQL ? 'mysql' : 'json' });
});

app.get('/api/db-state', async (req, res) => {
    try {
        const state = await getDBState();
        res.json(state);
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// --- Secure Authentication Endpoints ---

// Helper function to generate 6-digit OTP
function generateOTP() {
    return String(100000 + Math.floor(Math.random() * 900000));
}

// Helper function to send OTP via Email (Nodemailer) or SMS (Twilio)
async function sendOTP(target, code, contextName, targetDesc) {
    // 1. Log to console regardless
    console.log(`\n======================================================\n[OTP GATEWAY] ${contextName} for (${targetDesc}): Code = ${code}\n======================================================\n`);

    const isEmail = target.includes('@');

    if (isEmail) {
        // Send via Nodemailer if SMTP is configured
        if (process.env.SMTP_USER && process.env.SMTP_PASS) {
            try {
                const transporter = nodemailer.createTransport({
                    host: process.env.SMTP_HOST || 'smtp.gmail.com',
                    port: process.env.SMTP_PORT || 465,
                    secure: true,
                    auth: {
                        user: process.env.SMTP_USER,
                        pass: process.env.SMTP_PASS
                    }
                });
                await transporter.sendMail({
                    from: process.env.SMTP_FROM || '"ALERTO POZ" <noreply@alerto.pozorrubio.gov.ph>',
                    to: target,
                    subject: 'ALERTO POZ - Verification Code',
                    text: `Your Alerto verification code is: ${code}. This code will expire in 5 minutes.`
                });
                console.log(`[SMTP] Email OTP sent to ${target}`);
            } catch (err) {
                console.error(`[SMTP] Failed to send email to ${target}:`, err.message);
            }
        } else {
            console.log(`[SMTP] Skipped sending to ${target} (SMTP credentials not configured)`);
        }
    } else {
        // Send via Twilio if configured
        if (process.env.TWILIO_ACCOUNT_SID && process.env.TWILIO_AUTH_TOKEN && process.env.TWILIO_PHONE_NUMBER) {
            try {
                const client = twilio(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN);
                await client.messages.create({
                    body: `Your Alerto verification code is: ${code}. This code will expire in 5 minutes.`,
                    from: process.env.TWILIO_PHONE_NUMBER,
                    to: target.startsWith('0') ? '+63' + target.substring(1) : target // naive PH number conversion
                });
                console.log(`[Twilio] SMS OTP sent to ${target}`);
            } catch (err) {
                console.error(`[Twilio] Failed to send SMS to ${target}:`, err.message);
            }
        } else {
            console.log(`[Twilio] Skipped sending to ${target} (Twilio credentials not configured)`);
        }
    }
}

// 1. User Registration (active = 0, requires OTP)
app.post('/api/auth/register', async (req, res) => {
    try {
        const { name, email, phone, password, registrationMethod } = req.body;
        
        if (!name || !password || !registrationMethod) {
            return res.status(400).json({ error: "All required fields must be completed." });
        }

        if (registrationMethod === 'email' && !email) {
            return res.status(400).json({ error: "Email address is required." });
        }
        
        if (registrationMethod === 'phone' && !phone) {
            return res.status(400).json({ error: "Phone number is required." });
        }

        // Email format validation
        if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
            return res.status(400).json({ error: "Invalid email address format." });
        }

        // Phone format validation
        if (phone && !/^(09|\+639)\d{9}$/.test(phone)) {
            return res.status(400).json({ error: "Invalid mobile number format. Must starts with 09 or +639." });
        }

        // Password requirements: 8+ chars, 1 uppercase, 1 lowercase, 1 digit, 1 symbol
        const pRegex = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?]).{8,}$/;
        if (!pRegex.test(password)) {
            return res.status(400).json({ error: "Password does not meet complexity requirements." });
        }

        const hashedPassword = bcrypt.hashSync(password, 10);
        const otpCode = generateOTP();
        const otpExpires = Date.now() + 5 * 60 * 1000; // 5 mins

        if (useMySQL) {
            // Check duplicates
            if (email) {
                const [existsEmail] = await pool.query("SELECT * FROM users WHERE email = ?", [email]);
                if (existsEmail.length > 0) return res.status(400).json({ error: "Email address already registered." });
            }
            if (phone) {
                const [existsPhone] = await pool.query("SELECT * FROM users WHERE phone = ?", [phone]);
                if (existsPhone.length > 0) return res.status(400).json({ error: "Mobile number already registered." });
            }

            await pool.query(
                "INSERT INTO users (name, email, phone, password, active, otp_code, otp_expires, otp_type) VALUES (?, ?, ?, ?, 0, ?, ?, 'register')",
                [name, email || null, phone || null, hashedPassword, otpCode, otpExpires]
            );
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            if (email && db.users.some(u => u.email === email)) {
                return res.status(400).json({ error: "Email address already registered." });
            }
            if (phone && db.users.some(u => u.phone === phone)) {
                return res.status(400).json({ error: "Mobile number already registered." });
            }

            db.users.push({
                id: db.users.length + 1,
                name,
                email: email || null,
                phone: phone || null,
                password: hashedPassword,
                active: 0,
                otp_code: otpCode,
                otp_expires: otpExpires,
                otp_type: 'register'
            });
            fs.writeFileSync(JSON_DB_FILE, JSON.stringify(db, null, 4));
        }

        // Send real OTP
        const targetDesc = email ? `Email to ${email}` : `SMS to ${phone}`;
        await sendOTP(email || phone, otpCode, `REGISTER OTP for ${name}`, targetDesc);

        res.json({ success: true, otpRequired: true, target: email || phone, otpDevVal: otpCode });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// 2a. Responder Sign In (Direct login without OTP for rapid field access)
app.post('/api/auth/responder-login', async (req, res) => {
    try {
        const { loginId, password } = req.body;
        if (!loginId || !password) {
            return res.status(400).json({ error: "All required fields must be completed." });
        }

        let user = null;
        if (useMySQL) {
            const [rows] = await pool.query("SELECT * FROM users WHERE (email = ? OR phone = ?) AND type = 'responder'", [loginId, loginId]);
            if (rows.length > 0) user = rows[0];
        }

        if (!user) {
            return res.status(400).json({ error: "Invalid responder credentials." });
        }

        // Verify password
        const isMatch = bcrypt.compareSync(password, user.password);
        if (!isMatch) {
            return res.status(400).json({ error: "Invalid responder credentials." });
        }

        // Fetch associated unit details
        let unitDetails = null;
        if (user.unit_id) {
            const [units] = await pool.query("SELECT * FROM responders WHERE id = ?", [user.unit_id]);
            if (units.length > 0) unitDetails = units[0];
        }

        res.json({
            success: true,
            user: {
                id: user.id,
                name: user.name,
                email: user.email,
                phone: user.phone,
                type: user.type,
                unit_id: user.unit_id,
                unit_details: unitDetails
            }
        });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// 2b. User Sign In (Verify credentials -> Generate OTP -> 2FA Verification required)
app.post('/api/auth/login', async (req, res) => {
    try {
        const { loginId, password } = req.body;
        if (!loginId || !password) {
            return res.status(400).json({ error: "All required fields must be completed." });
        }

        let user = null;
        if (useMySQL) {
            try {
                const [rows] = await pool.query("SELECT * FROM users WHERE email = ? OR phone = ?", [loginId, loginId]);
                if (rows.length > 0) user = rows[0];
            } catch (dbErr) {
                console.warn("MySQL connection lost during login. Falling back to JSON simulation.", dbErr.message);
                useMySQL = false;
                const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
                user = db.users.find(u => u.email === loginId || u.phone === loginId);
            }
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            user = db.users.find(u => u.email === loginId || u.phone === loginId);
        }

        if (!user) {
            return res.status(400).json({ error: "Invalid email/mobile number or password." });
        }
        
        if (!user.active) {
            return res.status(401).json({ error: "Your account is not verified. Please contact support or register again." });
        }

        // Verify password
        const isMatch = bcrypt.compareSync(password, user.password);
        if (!isMatch) {
            return res.status(400).json({ error: "Invalid email/mobile number or password." });
        }

        // Generate 2FA login OTP
        const otpCode = generateOTP();
        const otpExpires = Date.now() + 5 * 60 * 1000; // 5 mins

        if (useMySQL) {
            await pool.query(
                "UPDATE users SET otp_code = ?, otp_expires = ?, otp_type = 'login' WHERE id = ?",
                [otpCode, otpExpires, user.id]
            );
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            const u = db.users.find(x => x.id === user.id);
            if (u) {
                u.otp_code = otpCode;
                u.otp_expires = otpExpires;
                u.otp_type = 'login';
                fs.writeFileSync(JSON_DB_FILE, JSON.stringify(db, null, 4));
            }
        }

        // Send real OTP
        const targetDesc = user.email && loginId.includes('@') ? `Email to ${user.email}` : `SMS to ${user.phone}`;
        await sendOTP(loginId.includes('@') ? user.email : user.phone, otpCode, `LOGIN 2FA OTP for ${user.name}`, targetDesc);

        res.json({ success: true, otpRequired: true, target: user.email || user.phone, otpDevVal: otpCode, userActive: user.active });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// 3. Verify OTP Code
app.post('/api/auth/verify-otp', async (req, res) => {
    try {
        const { target, code, type } = req.body;
        if (!target || !code || !type) {
            return res.status(400).json({ error: "OTP validation fields incomplete." });
        }

        let user = null;
        if (useMySQL) {
            const [rows] = await pool.query(
                "SELECT * FROM users WHERE (email = ? OR phone = ?) AND otp_code = ? AND otp_type = ?",
                [target, target, code, type]
            );
            if (rows.length > 0) user = rows[0];
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            user = db.users.find(u => (u.email === target || u.phone === target) && u.otp_code === code && u.otp_type === type);
        }

        if (!user) {
            return res.status(400).json({ error: "Invalid or incorrect OTP verification code." });
        }

        if (Date.now() > user.otp_expires) {
            return res.status(400).json({ error: "OTP code has expired. Please request a new one." });
        }

        // OTP Validated! Update user state
        let resetToken = null;
        if (useMySQL) {
            if (type === 'register') {
                await pool.query("UPDATE users SET active = 1, otp_code = NULL, otp_expires = NULL, otp_type = NULL WHERE id = ?", [user.id]);
            } else if (type === 'forgot') {
                resetToken = crypto.randomBytes(32).toString('hex');
                const expires = Date.now() + 15 * 60 * 1000; // 15 mins validity
                await pool.query("UPDATE users SET otp_code = ?, otp_expires = ?, otp_type = 'reset_token' WHERE id = ?", [resetToken, expires, user.id]);
            } else {
                await pool.query("UPDATE users SET otp_code = NULL, otp_expires = NULL, otp_type = NULL WHERE id = ?", [user.id]);
            }
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            const u = db.users.find(x => x.id === user.id);
            if (u) {
                if (type === 'register') u.active = 1;
                
                if (type === 'forgot') {
                    resetToken = crypto.randomBytes(32).toString('hex');
                    u.otp_code = resetToken;
                    u.otp_expires = Date.now() + 15 * 60 * 1000;
                    u.otp_type = 'reset_token';
                } else {
                    u.otp_code = null;
                    u.otp_expires = null;
                    u.otp_type = null;
                }
                fs.writeFileSync(JSON_DB_FILE, JSON.stringify(db, null, 4));
            }
        }

        // Return a mock authentication session token
        res.json({
            success: true,
            user: {
                id: user.id,
                name: user.name,
                email: user.email,
                phone: user.phone,
                type: user.type,
                hasPasscode: !!user.passcode
            },
            token: `alerto-session-${user.id}-${Date.now()}`,
            reset_token: resetToken
        });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// Session Validation Endpoint
app.post('/api/auth/validate', async (req, res) => {
    try {
        const { token } = req.body;
        if (!token || !token.startsWith('alerto-session-')) {
            return res.status(401).json({ valid: false, error: "Invalid token format." });
        }

        const parts = token.split('-');
        if (parts.length < 4) {
            return res.status(401).json({ valid: false, error: "Malformed token." });
        }
        
        const userId = parseInt(parts[2], 10);
        let user = null;

        if (useMySQL) {
            const [rows] = await pool.query("SELECT * FROM users WHERE id = ?", [userId]);
            if (rows.length > 0) user = rows[0];
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            user = db.users.find(u => u.id === userId);
        }

        // Active state check might be 1 (int) or true (boolean)
        if (!user || !user.active) {
            return res.status(401).json({ valid: false, error: "User is inactive or not found." });
        }

        res.json({
            valid: true,
            user: {
                id: user.id,
                name: user.name,
                email: user.email,
                phone: user.phone,
                type: user.type,
                hasPasscode: !!user.passcode,
                profile_image: user.profile_image
            }
        });
    } catch (e) {
        res.status(500).json({ valid: false, error: e.message });
    }
});

// 4. Resend OTP Code
app.post('/api/auth/resend-otp', async (req, res) => {
    try {
        const { target, type } = req.body;
        if (!target || !type) {
            return res.status(400).json({ error: "Required fields missing." });
        }

        let user = null;
        if (useMySQL) {
            const [rows] = await pool.query("SELECT * FROM users WHERE email = ? OR phone = ?", [target, target]);
            if (rows.length > 0) user = rows[0];
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            user = db.users.find(u => u.email === target || u.phone === target);
        }

        if (!user) {
            return res.status(400).json({ error: "Account details not found." });
        }

        const otpCode = generateOTP();
        const otpExpires = Date.now() + 5 * 60 * 1000;

        if (useMySQL) {
            await pool.query(
                "UPDATE users SET otp_code = ?, otp_expires = ?, otp_type = ? WHERE id = ?",
                [otpCode, otpExpires, type, user.id]
            );
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            const u = db.users.find(x => x.id === user.id);
            if (u) {
                u.otp_code = otpCode;
                u.otp_expires = otpExpires;
                u.otp_type = type;
                fs.writeFileSync(JSON_DB_FILE, JSON.stringify(db, null, 4));
            }
        }

        const targetDesc = user.email && target.includes('@') ? `Email to ${user.email}` : `SMS to ${user.phone}`;
        await sendOTP(target.includes('@') ? user.email : user.phone, otpCode, `RESENT OTP (${type}) for ${user.name}`, targetDesc);

        res.json({ success: true, otpDevVal: otpCode });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// 5. Forgot Password Trigger
app.post('/api/auth/forgot-password', async (req, res) => {
    try {
        const { target } = req.body;
        if (!target) {
            return res.status(400).json({ error: "Please enter your email or mobile number." });
        }

        let user = null;
        if (useMySQL) {
            const [rows] = await pool.query("SELECT * FROM users WHERE email = ? OR phone = ?", [target, target]);
            if (rows.length > 0) user = rows[0];
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            user = db.users.find(u => u.email === target || u.phone === target);
        }

        if (!user) {
            return res.status(400).json({ error: "No account registered under this email/phone number." });
        }

        const otpCode = generateOTP();
        const otpExpires = Date.now() + 5 * 60 * 1000;

        if (useMySQL) {
            await pool.query(
                "UPDATE users SET otp_code = ?, otp_expires = ?, otp_type = 'forgot' WHERE id = ?",
                [otpCode, otpExpires, user.id]
            );
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            const u = db.users.find(x => x.id === user.id);
            if (u) {
                u.otp_code = otpCode;
                u.otp_expires = otpExpires;
                u.otp_type = 'forgot';
                fs.writeFileSync(JSON_DB_FILE, JSON.stringify(db, null, 4));
            }
        }

        const targetDesc = user.email && target.includes('@') ? `Email to ${user.email}` : `SMS to ${user.phone}`;
        await sendOTP(target.includes('@') ? user.email : user.phone, otpCode, `FORGOT PASSWORD OTP for ${user.name}`, targetDesc);

        res.json({ success: true, otpDevVal: otpCode });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// 6. Reset Password via Secure Token
app.post('/api/auth/reset-password', async (req, res) => {
    try {
        const { target, token, password } = req.body;
        if (!target || !token || !password) {
            return res.status(400).json({ error: "All required fields must be completed." });
        }

        // Validate new password complexity
        const pRegex = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?]).{8,}$/;
        if (!pRegex.test(password)) {
            return res.status(400).json({ error: "Password does not meet complexity requirements." });
        }

        let user = null;
        if (useMySQL) {
            const [rows] = await pool.query(
                "SELECT * FROM users WHERE (email = ? OR phone = ?) AND otp_code = ? AND otp_type = 'reset_token'",
                [target, target, token]
            );
            if (rows.length > 0) user = rows[0];
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            user = db.users.find(u => (u.email === target || u.phone === target) && u.otp_code === token && u.otp_type === 'reset_token');
        }

        if (!user) {
            return res.status(400).json({ error: "Invalid or expired reset session. Please restart the password recovery process." });
        }

        if (Date.now() > user.otp_expires) {
            return res.status(400).json({ error: "Reset session has expired. Please restart the password recovery process." });
        }

        const hashedPassword = bcrypt.hashSync(password, 10);

        if (useMySQL) {
            await pool.query(
                "UPDATE users SET password = ?, otp_code = NULL, otp_expires = NULL, otp_type = NULL, active = 1 WHERE id = ?",
                [hashedPassword, user.id]
            );
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            const u = db.users.find(x => x.id === user.id);
            if (u) {
                u.password = hashedPassword;
                u.otp_code = null;
                u.otp_expires = null;
                u.otp_type = null;
                u.active = 1;
                fs.writeFileSync(JSON_DB_FILE, JSON.stringify(db, null, 4));
            }
        }

        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

async function logActivity(userId, action, req) {
    if (!useMySQL || !userId) return;
    try {
        const ip = req.headers['x-forwarded-for'] || req.socket.remoteAddress;
        const device = req.headers['user-agent'] || 'Unknown Device';
        const d = new Date();
        const dateStr = d.toISOString().split('T')[0];
        const timeStr = d.toTimeString().split(' ')[0];
        const ts = Date.now();
        await pool.query("INSERT INTO activity_logs (user_id, action, date, time, ip_address, device, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)", [userId, action, dateStr, timeStr, ip, device, ts]);
    } catch(e) {
        console.error("Activity log error:", e);
    }
}
// --- Profile & Settings Routes ---
app.post('/api/user/profile', async (req, res) => {
    try {
        const { id, name, email, phone, profile_image, first_name, middle_name, last_name, suffix, birthdate, gender, address } = req.body;
        if (!id) return res.status(400).json({ error: "User ID required" });
        let updatedUser = null;
        if (useMySQL) {
            // Check email/phone uniqueness
            if (email || phone) {
                let checkQuery = "SELECT id FROM users WHERE (email = ? OR phone = ?) AND id != ?";
                const [existing] = await pool.query(checkQuery, [email || '', phone || '', id]);
                if (existing.length > 0) {
                    return res.status(400).json({ error: "Email or Phone Number is already in use by another account." });
                }
            }
            await pool.query("UPDATE users SET name = ?, email = ?, phone = ?, profile_image = ?, first_name = ?, middle_name = ?, last_name = ?, suffix = ?, birthdate = ?, gender = ?, address = ?, updated_at = ? WHERE id = ?", 
                [name, email, phone, profile_image, first_name, middle_name, last_name, suffix, birthdate, gender, address, Date.now(), id]);
            await logActivity(id, "Updated profile", req);
            const [rows] = await pool.query("SELECT * FROM users WHERE id = ?", [id]);
            updatedUser = rows[0];
            if (updatedUser) delete updatedUser.password;
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            const u = db.users.find(x => x.id == id);
            if(u) {
                if (email || phone) {
                    const existing = db.users.find(x => (x.email === email || x.phone === phone) && x.id != id);
                    if (existing) {
                        return res.status(400).json({ error: "Email or Phone Number is already in use by another account." });
                    }
                }
                u.name = name; u.email = email; u.phone = phone; u.profile_image = profile_image;
                u.first_name = first_name; u.middle_name = middle_name; u.last_name = last_name;
                u.suffix = suffix; u.birthdate = birthdate; u.gender = gender; u.address = address;
                u.updated_at = Date.now();
                fs.writeFileSync(JSON_DB_FILE, JSON.stringify(db, null, 4));
                updatedUser = { ...u };
                delete updatedUser.password;
            }
        }
        
        io.emit('profile-updated', updatedUser || { id });
        
        res.json({ success: true, user: updatedUser });
    } catch(e) { res.status(500).json({ error: e.message }); }
});
app.post('/api/user/passcode', async (req, res) => {
    try {
        const { id, currentPasscode, newPasscode } = req.body;
        if (!id || !newPasscode) return res.status(400).json({ error: "Missing required fields" });
        
        let user;
        if (useMySQL) {
            const [rows] = await pool.query("SELECT * FROM users WHERE id = ?", [id]);
            user = rows[0];
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            user = db.users.find(x => x.id == id);
        }

        if (!user) return res.status(404).json({ error: "User not found" });

        if (user.passcode) {
             if (!currentPasscode) return res.status(400).json({ error: "Current passcode is required." });
             const isMatch = bcrypt.compareSync(currentPasscode, user.passcode);
             if (!isMatch) return res.status(400).json({ error: "Current passcode is incorrect." });
        }

        const hashedPasscode = bcrypt.hashSync(newPasscode, 10);

        if (useMySQL) {
            await pool.query("UPDATE users SET passcode = ? WHERE id = ?", [hashedPasscode, id]);
            await logActivity(id, "Changed passcode", req);
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            const u = db.users.find(x => x.id == id);
            if(u) { u.passcode = hashedPasscode; fs.writeFileSync(JSON_DB_FILE, JSON.stringify(db, null, 4)); }
        }
        io.emit('profile-updated', { id });
        res.json({ success: true });
    } catch(e) { res.status(500).json({ error: e.message }); }
});

app.post('/api/user/passcode/verify', async (req, res) => {
    try {
        const { id, passcode } = req.body;
        if (!id || !passcode) return res.status(400).json({ error: "Missing required fields" });
        
        let user;
        if (useMySQL) {
            const [rows] = await pool.query("SELECT * FROM users WHERE id = ?", [id]);
            user = rows[0];
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            user = db.users.find(x => x.id == id);
        }

        if (!user) return res.status(404).json({ error: "User not found" });
        if (!user.passcode) return res.status(400).json({ error: "No passcode set for user." });

        const isMatch = bcrypt.compareSync(passcode, user.passcode);
        if (isMatch) {
            res.json({ success: true });
        } else {
            res.status(400).json({ success: false, error: "Incorrect passcode." });
        }
    } catch(e) { res.status(500).json({ error: e.message }); }
});
app.post('/api/feedback', async (req, res) => {
    try {
        const { user_id, subject, category, message, media_path } = req.body;
        const ts = Date.now();
        if (useMySQL) {
            await pool.query("INSERT INTO feedbacks (user_id, subject, category, message, media_path, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)", [user_id, subject, category, message, media_path, ts, ts]);
            await logActivity(user_id, "Submitted feedback", req);
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            if (!db.feedbacks) db.feedbacks = [];
            db.feedbacks.push({ id: ts, user_id, subject, category, message, media_path, created_at: ts, updated_at: ts, status: 'New' });
            fs.writeFileSync(JSON_DB_FILE, JSON.stringify(db, null, 4));
            await logActivity(user_id, "Submitted feedback", req);
        }
        res.json({ success: true });
    } catch(e) { res.status(500).json({ error: e.message }); }
});

app.post('/api/user/map-settings', async (req, res) => {
    try {
        const { user_id, map_type, live_location, gps_enabled, show_traffic, show_disaster_zones, show_evacuation_centers, show_barangay_boundaries, navigation_preference, notification_radius, emergency_alert_radius, auto_refresh, dark_mode } = req.body;
        const ts = Date.now();
        if (useMySQL) {
            await pool.query("INSERT INTO map_settings (user_id, map_type, live_location, gps_enabled, show_traffic, show_disaster_zones, show_evacuation_centers, show_barangay_boundaries, navigation_preference, notification_radius, emergency_alert_radius, auto_refresh, dark_mode, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE map_type=VALUES(map_type), live_location=VALUES(live_location), gps_enabled=VALUES(gps_enabled), show_traffic=VALUES(show_traffic), show_disaster_zones=VALUES(show_disaster_zones), show_evacuation_centers=VALUES(show_evacuation_centers), show_barangay_boundaries=VALUES(show_barangay_boundaries), navigation_preference=VALUES(navigation_preference), notification_radius=VALUES(notification_radius), emergency_alert_radius=VALUES(emergency_alert_radius), auto_refresh=VALUES(auto_refresh), dark_mode=VALUES(dark_mode), updated_at=VALUES(updated_at)", 
                [user_id, map_type, live_location, gps_enabled, show_traffic, show_disaster_zones, show_evacuation_centers, show_barangay_boundaries, navigation_preference || 'Fastest Route', notification_radius || 500, emergency_alert_radius || 1000, auto_refresh !== undefined ? auto_refresh : 1, dark_mode !== undefined ? dark_mode : 0, ts, ts]);
            await logActivity(user_id, "Updated map settings", req);
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            const user = db.users.find(u => u.id == user_id);
            if (user) {
                user.map_settings = { map_type, live_location, gps_enabled, show_traffic, show_disaster_zones, show_evacuation_centers, show_barangay_boundaries, navigation_preference: navigation_preference || 'Fastest Route', notification_radius: notification_radius || 500, emergency_alert_radius: emergency_alert_radius || 1000, auto_refresh: auto_refresh !== undefined ? auto_refresh : 1, dark_mode: dark_mode !== undefined ? dark_mode : 0, updated_at: ts };
                fs.writeFileSync(JSON_DB_FILE, JSON.stringify(db, null, 4));
            }
            await logActivity(user_id, "Updated map settings", req);
        }
        res.json({ success: true });
    } catch(e) { res.status(500).json({ error: e.message }); }
});

app.get('/api/user/map-settings/:id', async (req, res) => {
    try {
        if (useMySQL) {
            const [rows] = await pool.query("SELECT * FROM map_settings WHERE user_id = ?", [req.params.id]);
            if(rows.length > 0) return res.json(rows[0]);
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            const user = db.users.find(u => u.id == req.params.id);
            if (user && user.map_settings) return res.json(user.map_settings);
        }
        res.json({});
    } catch(e) { res.status(500).json({ error: e.message }); }
});

app.post('/api/user/profile-picture', uploadProfile.single('profile_image'), async (req, res) => {
    try {
        const { id } = req.body;
        if (!id || !req.file) return res.status(400).json({ error: "Missing ID or Image" });
        
        const relativePath = '/uploads/profiles/' + req.file.filename;

        // Helper to delete old image
        const deleteOldImage = (oldPath) => {
            if (oldPath && oldPath.startsWith('/uploads/profiles/')) {
                const fullPath = path.join(__dirname, 'public', oldPath);
                if (fs.existsSync(fullPath)) {
                    fs.unlinkSync(fullPath);
                }
            }
        };

        if (useMySQL) {
            // Get old image first
            const [oldRows] = await pool.query("SELECT profile_image FROM users WHERE id = ?", [id]);
            if (oldRows.length > 0) deleteOldImage(oldRows[0].profile_image);

            await pool.query("UPDATE users SET profile_image = ?, updated_at = ? WHERE id = ?", [relativePath, Date.now(), id]);
            await logActivity(id, "Updated profile picture", req);
            
            const [rows] = await pool.query("SELECT * FROM users WHERE id = ?", [id]);
            const updatedUser = rows[0];
            if(updatedUser) delete updatedUser.password;
            io.emit('profile-updated', updatedUser || { id });
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            const u = db.users.find(x => x.id == id);
            if (u) {
                deleteOldImage(u.profile_image);
                u.profile_image = relativePath;
                u.updated_at = Date.now();
                fs.writeFileSync(JSON_DB_FILE, JSON.stringify(db, null, 4));
                await logActivity(id, "Updated profile picture", req);
                const updatedUser = { ...u };
                delete updatedUser.password;
                io.emit('profile-updated', updatedUser);
            }
        }
        res.json({ success: true, url: relativePath });
    } catch(e) { res.status(500).json({ error: e.message }); }
});

app.get('/api/user/activity-logs', async (req, res) => {
    try {
        if (useMySQL) {
            const [rows] = await pool.query("SELECT a.*, u.name as user_name, u.email FROM activity_logs a LEFT JOIN users u ON a.user_id = u.id ORDER BY a.created_at DESC");
            res.json(rows);
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            const logs = (db.activityLogs || []).map(log => {
                const u = db.users.find(x => x.id == log.userId);
                return { ...log, user_name: u ? u.name : 'Unknown', email: u ? u.email : '' };
            }).sort((a,b) => b.id - a.id);
            res.json(logs);
        }
    } catch(e) { res.status(500).json({ error: e.message }); }
});

app.get('/api/user/history/:id', async (req, res) => {
    try {
        const { id } = req.params;
        if (!id) return res.status(400).json({ error: "User ID required" });
        if (useMySQL) {
            const [rows] = await pool.query("SELECT * FROM incidents WHERE reporterId = ? OR reporterPhone = ? ORDER BY createdAt DESC", [id, id]);
            
            // Attach chronological events for each incident
            for (let inc of rows) {
                const [events] = await pool.query("SELECT * FROM incident_events WHERE incident_id = ? ORDER BY timestamp ASC", [inc.id]);
                inc.events = events;
            }
            
            res.json(rows);
        } else {
            const dbState = await loadDB();
            const userIncidents = dbState.incidents.filter(i => i.reporterId == id || i.reporterPhone == id).sort((a,b) => b.createdAt - a.createdAt);
            
            // For JSON, attach chronological events if they exist
            if (dbState.incident_events) {
                for (let inc of userIncidents) {
                    inc.events = dbState.incident_events.filter(e => e.incident_id === inc.id).sort((a,b) => a.timestamp - b.timestamp);
                }
            }
            
            res.json(userIncidents);
        }
    } catch(e) { res.status(500).json({ error: e.message }); }
});

app.get('/api/feedbacks', async (req, res) => {
    try {
        if (useMySQL) {
            const [rows] = await pool.query("SELECT f.*, u.name as user_name, u.email FROM feedbacks f LEFT JOIN users u ON f.user_id = u.id ORDER BY f.created_at DESC");
            res.json(rows);
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            const fbs = (db.feedbacks || []).map(fb => {
                const u = db.users.find(x => x.id == fb.user_id);
                return { ...fb, user_name: u ? u.name : 'Unknown', email: u ? u.email : '' };
            }).sort((a,b) => b.id - a.id);
            res.json(fbs);
        }
    } catch(e) { res.status(500).json({ error: e.message }); }
});

app.put('/api/feedbacks/:id/status', async (req, res) => {
    try {
        if (!useMySQL) return res.json({ success: true });
        const { status } = req.body;
        await pool.query("UPDATE feedbacks SET status = ?, updated_at = ? WHERE id = ?", [status, Date.now(), req.params.id]);
        res.json({ success: true });
    } catch(e) { res.status(500).json({ error: e.message }); }
});

// ==========================================
// ADMIN DASHBOARD & RESPONDER MANAGEMENT API
// ==========================================

app.post('/api/auth/admin-login', async (req, res) => {
    try {
        const { username, password } = req.body;
        if (!username || !password) return res.status(400).json({ error: "Username and password required." });

        if (useMySQL) {
            const [rows] = await pool.query("SELECT * FROM users WHERE email = ? AND type = 'authority'", [username]);
            if (rows.length === 0) return res.status(401).json({ error: "Invalid credentials." });
            const user = rows[0];
            const isMatch = bcrypt.compareSync(password, user.password);
            if (!isMatch) return res.status(401).json({ error: "Invalid credentials." });
            
            // Bypass OTP for admin panel
            res.json({ success: true, user: { id: user.id, name: user.name, type: user.type, active: user.active, barangay: user.barangay } });
        } else {
            res.status(500).json({ error: "MySQL required for admin operations." });
        }
    } catch(e) {
        res.status(500).json({ error: e.message });
    }
});

app.post('/api/responders', async (req, res) => {
    try {
        const { id, name, type, lat, lng, status, icon } = req.body;
        if (useMySQL) {
            await pool.query("INSERT INTO responders (id, name, type, lat, lng, base_lat, base_lng, status, icon) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", [id, name, type, lat, lng, lat, lng, status, icon]);
            const dbState = await getDBState();
            io.emit('init-state', dbState); // Broadcast update
            res.json({ success: true });
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            db.responders.push({ id, name, type, lat, lng, base_lat: lat, base_lng: lng, status, icon });
            fs.writeFileSync(JSON_DB_FILE, JSON.stringify(db, null, 4));
            io.emit('init-state', db);
            res.json({ success: true });
        }
    } catch(e) { res.status(500).json({ error: e.message }); }
});

app.put('/api/responders/:id', async (req, res) => {
    try {
        const { name, type, lat, lng, status, icon } = req.body;
        if (useMySQL) {
            await pool.query("UPDATE responders SET name=?, type=?, lat=?, lng=?, base_lat=?, base_lng=?, status=?, icon=? WHERE id=?", [name, type, lat, lng, lat, lng, status, icon, req.params.id]);
            const dbState = await getDBState();
            io.emit('init-state', dbState);
            res.json({ success: true });
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            const r = db.responders.find(res => res.id === req.params.id);
            if (r) {
                r.name = name; r.type = type; r.lat = lat; r.lng = lng; r.base_lat = lat; r.base_lng = lng; r.status = status; r.icon = icon;
                fs.writeFileSync(JSON_DB_FILE, JSON.stringify(db, null, 4));
                io.emit('init-state', db);
                res.json({ success: true });
            } else {
                res.status(404).json({ error: "Responder not found" });
            }
        }
    } catch(e) { res.status(500).json({ error: e.message }); }
});

app.delete('/api/responders/:id', async (req, res) => {
    try {
        if (useMySQL) {
            await pool.query("DELETE FROM responders WHERE id=?", [req.params.id]);
            const dbState = await getDBState();
            io.emit('init-state', dbState);
            res.json({ success: true });
        }
    } catch(e) { res.status(500).json({ error: e.message }); }
});

// Rescue Vehicles API
app.post('/api/rescue_vehicles', async (req, res) => {
    try {
        const { name, number, type, agency, driver, status, fuel_status, lat, lng } = req.body;
        if (useMySQL) {
            await pool.query("INSERT INTO rescue_vehicles (name, number, type, agency, driver, status, fuel_status, lat, lng) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", [name, number, type, agency, driver, status, fuel_status, lat, lng]);
            const dbState = await getDBState();
            io.emit('init-state', dbState);
            io.emit('vehicle_updated', dbState.rescue_vehicles);
            res.json({ success: true });
        }
    } catch(e) { res.status(500).json({ error: e.message }); }
});

app.put('/api/rescue_vehicles/:id', async (req, res) => {
    try {
        const { name, number, type, agency, driver, status, fuel_status, lat, lng } = req.body;
        if (useMySQL) {
            await pool.query("UPDATE rescue_vehicles SET name=?, number=?, type=?, agency=?, driver=?, status=?, fuel_status=?, lat=?, lng=? WHERE id=?", [name, number, type, agency, driver, status, fuel_status, lat, lng, req.params.id]);
            const dbState = await getDBState();
            io.emit('init-state', dbState);
            io.emit('vehicle_updated', dbState.rescue_vehicles);
            res.json({ success: true });
        }
    } catch(e) { res.status(500).json({ error: e.message }); }
});

app.delete('/api/rescue_vehicles/:id', async (req, res) => {
    try {
        if (useMySQL) {
            await pool.query("DELETE FROM rescue_vehicles WHERE id=?", [req.params.id]);
            const dbState = await getDBState();
            io.emit('init-state', dbState);
            res.json({ success: true });
        }
    } catch(e) { res.status(500).json({ error: e.message }); }
});

// Water Devices API
app.post('/api/water_devices', async (req, res) => {
    try {
        const { device_id, name, type, barangay, location, lat, lng, status, capacity, last_inspection, personnel, notes } = req.body;
        if (useMySQL) {
            await pool.query("INSERT INTO water_devices (device_id, name, type, barangay, location, lat, lng, status, capacity, last_inspection, personnel, notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", [device_id, name, type, barangay, location, lat, lng, status, capacity, last_inspection, personnel, notes]);
            const dbState = await getDBState();
            io.emit('init-state', dbState);
            io.emit('water_device_updated', dbState.water_devices);
            res.json({ success: true });
        }
    } catch(e) { res.status(500).json({ error: e.message }); }
});

app.put('/api/water_devices/:id', async (req, res) => {
    try {
        const { device_id, name, type, barangay, location, lat, lng, status, capacity, last_inspection, personnel, notes } = req.body;
        if (useMySQL) {
            await pool.query("UPDATE water_devices SET device_id=?, name=?, type=?, barangay=?, location=?, lat=?, lng=?, status=?, capacity=?, last_inspection=?, personnel=?, notes=? WHERE id=?", [device_id, name, type, barangay, location, lat, lng, status, capacity, last_inspection, personnel, notes, req.params.id]);
            const dbState = await getDBState();
            io.emit('init-state', dbState);
            io.emit('water_device_updated', dbState.water_devices);
            res.json({ success: true });
        }
    } catch(e) { res.status(500).json({ error: e.message }); }
});

app.delete('/api/water_devices/:id', async (req, res) => {
    try {
        if (useMySQL) {
            await pool.query("DELETE FROM water_devices WHERE id=?", [req.params.id]);
            const dbState = await getDBState();
            io.emit('init-state', dbState);
            res.json({ success: true });
        }
    } catch(e) { res.status(500).json({ error: e.message }); }
});

// Get Active Emergency for User (used to prevent duplicates)
app.get('/api/incidents/active/:userId', async (req, res) => {
    try {
        const userId = req.params.userId;
        const activeStatuses = ['draft', 'pending', 'dispatching', 'enroute', 'onscene', 'inprogress'];
        
        if (useMySQL) {
            const placeholders = activeStatuses.map(() => '?').join(',');
            const [rows] = await pool.query(
                `SELECT * FROM incidents WHERE reporterId = ? AND status IN (${placeholders}) ORDER BY createdAt DESC LIMIT 1`,
                [userId, ...activeStatuses]
            );
            if (rows.length > 0) {
                return res.json({ success: true, active: true, incident: rows[0] });
            }
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            const active = db.incidents.find(i => 
                String(i.reporterId) === String(userId) && 
                activeStatuses.includes((i.status || '').toLowerCase())
            );
            if (active) {
                return res.json({ success: true, active: true, incident: active });
            }
        }
        
        res.json({ success: true, active: false });
    } catch (e) {
        console.error("Active check API error:", e);
        res.status(500).json({ success: false, error: "Internal server error" });
    }
});

// Draft Creation endpoint (Creates a temporary draft record)
app.post('/api/incidents/draft', async (req, res) => {
    try {
        const { reporterId, reporterPhone, lat, lng, reporter, createdAt } = req.body;
        let phone = reporterPhone;
        
        if (useMySQL && !phone && reporterId) {
            const [u] = await pool.query("SELECT phone FROM users WHERE id = ?", [reporterId]);
            if (u.length > 0 && u[0].phone) phone = u[0].phone;
        }

        if (!phone || phone.trim() === '') {
            return res.status(400).json({ error: "Your account is missing a phone number. Please update your profile." });
        }

        const draftId = `DRAFT-${reporterId}`;
        
        if (useMySQL) {
            // Check if active incident exists (including any existing draft)
            const [existing] = await pool.query(
                "SELECT * FROM incidents WHERE (reporterId = ? OR reporterPhone = ?) AND status NOT IN ('resolved', 'cancelled', 'closed')",
                [reporterId, reporterPhone]
            );
            
            if (existing.length > 0) {
                // Already has an active emergency or draft
                const inc = existing[0];
                const [events] = await pool.query("SELECT * FROM incident_events WHERE incident_id = ? ORDER BY timestamp ASC", [inc.id]);
                inc.events = events;
                return res.status(409).json({ error: "Existing emergency found.", incident: inc });
            }
            
            // Explicitly delete any old cancelled/resolved draft data to ensure a fresh session
            await pool.query("DELETE FROM incident_events WHERE incident_id = ?", [draftId]);
            await pool.query("DELETE FROM incidents WHERE id = ?", [draftId]);
            
            // Create temporary draft ticket
            const ts = createdAt || Date.now();
            const normalizedReport = {
                id: draftId,
                category: 'draft',
                details: `Emergency report prepared by ${reporter}`,
                lat: lat || 16.1086,
                lng: lng || 120.5424,
                reporter: reporter || 'Unknown Citizen',
                reporterPhone: phone,
                media: [],
                createdAt: ts,
                networkReceivedAt: Date.now(),
                status: 'draft',
                assignedUnit: null,
                reporterId: reporterId,
                responseProgress: null,
                has_sent_messages: false
            };
            
            await addIncident(normalizedReport);
            io.emit('new-incident-alert', normalizedReport);
            return res.json({ success: true, incident: normalizedReport });
        } else {
            return res.status(501).json({ error: "Drafts only supported on MySQL" });
        }
    } catch(e) {
        console.error("Draft creation error:", e);
        res.status(500).json({ error: e.message });
    }
});

// Delete Draft endpoint
app.delete('/api/incidents/draft/:userId', async (req, res) => {
    try {
        const userId = req.params.userId;
        const draftId = `DRAFT-${userId}`;
        if (useMySQL) {
            await pool.query("DELETE FROM incidents WHERE id = ?", [draftId]);
            io.emit('incident-deleted', { id: draftId });
            res.json({ success: true });
        } else {
            res.status(501).json({ error: "Drafts only supported on MySQL" });
        }
    } catch(e) {
        console.error("Draft deletion error:", e);
        res.status(500).json({ error: e.message });
    }
});

// --- NEW MESSAGE ENDPOINTS ---
app.get('/api/incidents/:id/messages', async (req, res) => {
    try {
        if (!useMySQL) return res.status(501).json({ error: "Only supported on MySQL" });
        const [rows] = await pool.query(`
            SELECT m.*, u.profile_image as sender_profile_image, u.gender as sender_gender
            FROM messages m
            LEFT JOIN users u ON BINARY m.sender_id = BINARY CAST(u.id AS CHAR)
            WHERE m.incident_id = ?
            ORDER BY m.timestamp ASC
        `, [req.params.id]);
        res.json({ success: true, messages: rows });
    } catch(e) {
        console.error("Fetch messages error:", e);
        res.status(500).json({ error: e.message });
    }
});

app.post('/api/incidents/:id/messages', uploadChatMedia.single('media'), async (req, res) => {
    try {
        if (!useMySQL) return res.status(501).json({ error: "Only supported on MySQL" });
        const { senderId, senderRole, messageType, messageContent } = req.body;
        const incidentId = req.params.id;
        
        let mediaUrl = null;
        if (req.file) {
            mediaUrl = `/uploads/chat/${req.file.filename}`;
        }
        
        const timestamp = Date.now();
        
        const [result] = await pool.query(
            "INSERT INTO messages (incident_id, sender_id, sender_role, message_type, message_content, media_url, timestamp) VALUES (?, ?, ?, ?, ?, ?, ?)",
            [incidentId, senderId, senderRole, messageType || 'text', messageContent || null, mediaUrl, timestamp]
        );
        
        let userProfile = null;
        let userGender = null;
        if (senderRole !== 'Command Center' && senderId !== 'ADMIN') {
            const [userRows] = await pool.query("SELECT profile_image, gender FROM users WHERE id = ?", [senderId]);
            if (userRows && userRows.length > 0) {
                userProfile = userRows[0].profile_image;
                userGender = userRows[0].gender;
            }
        }

        const newMessage = {
            id: result.insertId,
            incident_id: incidentId,
            sender_id: senderId,
            sender_role: senderRole,
            message_type: messageType || 'text',
            message_content: messageContent || null,
            media_url: mediaUrl,
            timestamp: timestamp,
            sender_profile_image: userProfile,
            sender_gender: userGender
        };
        
        // Update has_sent_messages flag if this is the first message
        await pool.query("UPDATE incidents SET has_sent_messages = 1 WHERE id = ?", [incidentId]);
        
        // Broadcast the new message via WebSocket
        io.emit('chat-message-receive', newMessage);
        
        res.json({ success: true, message: newMessage });
    } catch(e) {
        console.error("Save message error:", e);
        res.status(500).json({ error: e.message });
    }
});
// -----------------------------

app.put('/api/incidents/:id', async (req, res) => {
    try {
        const { status, assignedUnit, assignedVehicle, assignedResponders, resolutionDate, notes, responseProgress } = req.body;
        if (useMySQL) {
            const [oldIncRows] = await pool.query("SELECT * FROM incidents WHERE id=?", [req.params.id]);
            if (oldIncRows.length === 0) {
                return res.status(404).json({ error: "Incident not found" });
            }
            const oldInc = oldIncRows[0];
            const oldUnit = oldInc.assignedUnit;
            const oldVehicle = oldInc.assignedVehicle;
            
            const finalStatus = status !== undefined ? status : oldInc.status;
            const finalAssignedUnit = assignedUnit !== undefined ? assignedUnit : oldUnit;
            const finalAssignedVehicle = assignedVehicle !== undefined ? assignedVehicle : oldVehicle;
            const finalAssignedResponders = assignedResponders !== undefined ? assignedResponders : oldInc.assignedResponders;
            const finalResolutionDate = resolutionDate !== undefined ? resolutionDate : oldInc.resolutionDate;
            const finalNotes = notes !== undefined ? notes : oldInc.notes;
            const finalResponseProgress = responseProgress !== undefined ? (responseProgress || null) : oldInc.responseProgress;

            await pool.query("UPDATE incidents SET status=?, assignedUnit=?, assignedVehicle=?, assignedResponders=?, resolutionDate=?, notes=?, responseProgress=? WHERE id=?", 
                [finalStatus, finalAssignedUnit, finalAssignedVehicle, finalAssignedResponders, finalResolutionDate, finalNotes, finalResponseProgress, req.params.id]);
            
            if (oldUnit && oldUnit !== finalAssignedUnit) {
                await pool.query("UPDATE responders SET status='available', lat = COALESCE(base_lat, lat), lng = COALESCE(base_lng, lng) WHERE id=?", [oldUnit]);
            }
            if (oldVehicle && oldVehicle !== finalAssignedVehicle) {
                await pool.query("UPDATE rescue_vehicles SET status='Available' WHERE id=? OR name=?", [oldVehicle, oldVehicle]);
            }
            
            if (finalStatus === 'resolved' || finalStatus === 'cancelled' || finalStatus === 'closed') {
                if (finalAssignedVehicle) await pool.query("UPDATE rescue_vehicles SET status='Available' WHERE id=? OR name=?", [finalAssignedVehicle, finalAssignedVehicle]);
                if (finalAssignedUnit) await pool.query("UPDATE responders SET status='available', lat = COALESCE(base_lat, lat), lng = COALESCE(base_lng, lng) WHERE id=?", [finalAssignedUnit]);
            } else {
                if (finalAssignedUnit) await pool.query("UPDATE responders SET status='busy' WHERE id=?", [finalAssignedUnit]);
                if (finalAssignedVehicle && finalStatus === 'dispatching' && finalResponseProgress === 'en_route') {
                    await pool.query("UPDATE rescue_vehicles SET status='Assigned' WHERE id=? OR name=?", [finalAssignedVehicle, finalAssignedVehicle]);
                }
            }
            
            const dbState = await getDBState();
            io.emit('init-state', dbState);
            const updated = dbState.incidents.find(i => i.id === req.params.id);
            if (updated) {
                io.emit('incident_status_changed', updated);
                io.emit('incident-updated', updated);
            }
            res.json({ success: true });
        } else {
            const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
            const incident = db.incidents.find(i => i.id === req.params.id);
            if (incident) {
                const oldUnit = incident.assignedUnit;
                const oldVehicle = incident.assignedVehicle;
                
                incident.status = status;
                if (assignedUnit !== undefined) incident.assignedUnit = assignedUnit;
                if (assignedVehicle !== undefined) incident.assignedVehicle = assignedVehicle;
                if (assignedResponders !== undefined) incident.assignedResponders = assignedResponders;
                if (resolutionDate !== undefined) incident.resolutionDate = resolutionDate;
                if (notes !== undefined) incident.notes = notes;
                if (responseProgress !== undefined) incident.responseProgress = responseProgress || null;
                
                if (oldUnit && oldUnit !== assignedUnit) {
                    const r = db.responders.find(r => r.id === oldUnit);
                    if (r) {
                        r.status = 'available';
                        r.lat = r.base_lat !== undefined ? r.base_lat : r.lat;
                        r.lng = r.base_lng !== undefined ? r.base_lng : r.lng;
                    }
                }
                if (oldVehicle && oldVehicle !== assignedVehicle) {
                    const v = db.rescue_vehicles.find(v => v.id === oldVehicle || v.name === oldVehicle);
                    if (v) v.status = 'Available';
                }
                
                if (status === 'resolved' || status === 'cancelled' || status === 'closed') {
                    if (incident.assignedUnit) {
                        const r = db.responders.find(r => r.id === incident.assignedUnit);
                        if (r) {
                            r.status = 'available';
                            r.lat = r.base_lat !== undefined ? r.base_lat : r.lat;
                            r.lng = r.base_lng !== undefined ? r.base_lng : r.lng;
                        }
                    }
                    if (incident.assignedVehicle) {
                        const v = db.rescue_vehicles.find(v => v.id === incident.assignedVehicle || v.name === incident.assignedVehicle);
                        if (v) v.status = 'Available';
                    }
                } else {
                    if (incident.assignedUnit) {
                        const r = db.responders.find(r => r.id === incident.assignedUnit);
                        if (r) r.status = 'busy';
                    }
                    if (incident.assignedVehicle && status === 'dispatching' && responseProgress === 'en_route') {
                        const v = db.rescue_vehicles.find(v => v.id === incident.assignedVehicle || v.name === incident.assignedVehicle);
                        if (v) v.status = 'Assigned';
                    }
                }
                
                fs.writeFileSync(JSON_DB_FILE, JSON.stringify(db, null, 4));
                io.emit('init-state', db);
                io.emit('incident_status_changed', incident);
                io.emit('incident-updated', incident);
                res.json({ success: true });
            } else {
                res.status(404).json({ error: "Incident not found" });
            }
        }
    } catch(e) { res.status(500).json({ error: e.message }); }
});

app.post('/api/incidents/:id/cancel', async (req, res) => {
    try {
        const { phone, userId, passcode } = req.body;
        const incidentId = req.params.id;
        
        if (!phone && !userId) return res.status(400).json({ error: "User ID or Phone number is required." });
        
        if (useMySQL) {
            const [rows] = await pool.query("SELECT * FROM incidents WHERE id=?", [incidentId]);
            if (rows.length === 0) {
                return res.json({ success: true, message: "Unsubmitted incident closed." });
            }
            const incident = rows[0];
            
            if (incident.status === 'cancelled' || incident.status === 'resolved' || incident.status === 'closed') {
                return res.status(400).json({ success: false, error: `Incident is already ${incident.status}. Cannot cancel.` });
            }
            
            let users;
            if (userId) {
                [users] = await pool.query("SELECT * FROM users WHERE id=?", [userId]);
            } else {
                [users] = await pool.query("SELECT * FROM users WHERE phone=?", [phone]);
            }
            
            if (users.length === 0) {
                return res.status(404).json({ error: "User not found." });
            }
            const user = users[0];
            
            // CASE B logic
            const hasInteraction = incident.has_sent_messages || (incident.status !== 'draft' && incident.status !== 'pending');
            
            if (hasInteraction && user.passcode) {
                if (passcode === undefined || !passcode) {
                    return res.status(401).json({ 
                        success: false, 
                        passcodeRequired: true, 
                        error: "This incident has active interactions. Passcode required to cancel." 
                    });
                }
                const isMatch = await bcrypt.compare(passcode, user.passcode);
                if (!isMatch) {
                    return res.status(400).json({ success: false, error: "Incorrect passcode. Please try again.", passcodeRequired: true });
                }
            }
            
            // Cancel it
            await pool.query("UPDATE incidents SET status='cancelled' WHERE id=?", [incidentId]);
            
            if (incident.assignedVehicle) {
                await pool.query("UPDATE rescue_vehicles SET status='Available' WHERE id=? OR name=?", [incident.assignedVehicle, incident.assignedVehicle]);
            }
            if (incident.assignedUnit) {
                await pool.query("UPDATE responders SET status='available' WHERE id=?", [incident.assignedUnit]);
            }
            
            await logActivity(user.id, `Citizen ${phone} manually cancelled incident.`, req);
            
            await recordIncidentEvent(incidentId, incidentId, 'Cancelled', incident.status, 'cancelled', 'Citizen App');

            const dbState = await getDBState();
            io.emit('init-state', dbState);
            const updated = dbState.incidents.find(i => i.id === incidentId);
            if (updated) {
                io.emit('incident_status_changed', updated);
                io.emit('incident-updated', updated);
            }
            return res.json({ success: true, message: "Incident cancelled successfully." });
        } else {
            // JSON fallback logic
            const data = JSON.parse(fs.readFileSync(DB_FILE, 'utf8'));
            const idx = data.incidents.findIndex(i => i.id === incidentId);
            if (idx === -1) {
                return res.json({ success: true, message: "Unsubmitted incident closed." });
            }
            const incident = data.incidents[idx];
            
            if (incident.status === 'cancelled' || incident.status === 'resolved' || incident.status === 'closed') {
                return res.status(400).json({ success: false, error: `Incident is already ${incident.status}. Cannot cancel.` });
            }
            
            let user;
            if (userId) {
                user = data.users.find(u => u.id === userId);
            } else {
                user = data.users.find(u => u.phone === phone);
            }
            if (!user) return res.status(404).json({ error: "User not found." });
            
            const hasInteraction = incident.has_sent_messages || (incident.status !== 'draft' && incident.status !== 'pending');
            if (hasInteraction && user.passcode) {
                if (passcode === undefined || !passcode) {
                    return res.status(401).json({ 
                        success: false, 
                        passcodeRequired: true, 
                        error: "This incident has active interactions. Passcode required to cancel." 
                    });
                }
                const isMatch = await bcrypt.compare(passcode, user.passcode);
                if (!isMatch) {
                    return res.status(400).json({ success: false, error: "Incorrect passcode. Please try again.", passcodeRequired: true });
                }
            }
            
            data.incidents[idx].status = 'cancelled';
            const inc = data.incidents[idx];
            
            if (inc.assignedVehicle) {
                const v = data.rescue_vehicles.find(vh => vh.id === inc.assignedVehicle || vh.name === inc.assignedVehicle);
                if (v) v.status = 'Available';
            }
            if (inc.assignedUnit) {
                const r = data.responders.find(rp => rp.id === inc.assignedUnit);
                if (r) r.status = 'available';
            }
            
            fs.writeFileSync(DB_FILE, JSON.stringify(data, null, 2));
            
            io.emit('init-state', data);
            io.emit('incident_status_changed', inc);
            io.emit('incident-updated', inc);
            return res.json({ success: true, message: "Incident cancelled successfully." });
        }
    } catch(e) { res.status(500).json({ error: e.message }); }
});



app.get('/api/admin/stats', async (req, res) => {
    try {
        if (!useMySQL) return res.status(500).json({ error: "MySQL required." });
        const [[{ totalUsers }]] = await pool.query("SELECT COUNT(*) AS totalUsers FROM users WHERE type='citizen'");
        const [[{ totalResponders }]] = await pool.query("SELECT COUNT(*) AS totalResponders FROM responders");
        const [[{ activeResponders }]] = await pool.query("SELECT COUNT(*) AS activeResponders FROM responders WHERE status='available'");
        const [[{ totalSOS }]] = await pool.query("SELECT COUNT(*) AS totalSOS FROM incidents");
        const [[{ dispatchingIncidents }]] = await pool.query("SELECT COUNT(*) AS dispatchingIncidents FROM incidents WHERE status='dispatching'");
        const [[{ resolvedIncidents }]] = await pool.query("SELECT COUNT(*) AS resolvedIncidents FROM incidents WHERE status='resolved'");
        const [[{ cancelledIncidents }]] = await pool.query("SELECT COUNT(*) AS cancelledIncidents FROM incidents WHERE status='cancelled'");
        
        res.json({
            success: true,
            stats: {
                totalUsers, totalResponders, activeResponders, totalSOS, dispatchingIncidents, resolvedIncidents, cancelledIncidents
            }
        });
} catch(e) { res.status(500).json({ error: e.message }); }
});

app.get('/api/admin/feedbacks', async (req, res) => {
    try {
        if (!useMySQL) return res.status(500).json({ error: "MySQL required." });
        const query = `
            SELECT f.*, u.name as user_name, u.email as user_email 
            FROM feedbacks f 
            LEFT JOIN users u ON f.user_id = u.id 
            ORDER BY f.created_at DESC
        `;
        const [feedbacks] = await pool.query(query);
        res.json({ success: true, feedbacks });
    } catch(e) {
        res.status(500).json({ error: e.message });
    }
});

async function generateUniqueTicketNumber() {
    const year = new Date().getFullYear().toString().slice(-2);
    while (true) {
        const randomCode = Math.floor(100000 + Math.random() * 900000);
        const candidate = `ALERTOPOZ-${year}-${randomCode}`;
        
        const state = await getDBState();
        const exists = state.incidents.find(i => i.id === candidate);
        if (!exists) {
            return candidate;
        }
    }
}

// 4. Socket.io Event Handling
io.on('connection', async (socket) => {
    console.log(`WebSocket Client Connected: ${socket.id}`);
    
    // Send hydrated DB state upon socket connection
    try {
        const dbState = await getDBState();
        socket.emit('init-state', dbState);
    } catch (e) {
        console.error("Socket initial sync state error:", e);
    }

    // Citizen SOS dispatch & chat
    socket.on('citizen-sos-report', async (report, callback) => {
        try {
            let isNewEmergency = false;
            let oldDraftId = null;

            if (!report.id || report.id === 'draft' || report.id.startsWith('DRAFT-')) {
                isNewEmergency = true;
                if (report.id && report.id.startsWith('DRAFT-')) {
                    oldDraftId = report.id;
                }
                report.id = await generateUniqueTicketNumber();
            }

            // Fetch previous state to detect if this is an activation
            let previousStatus = null;
            if (!isNewEmergency && useMySQL) {
                const [rows] = await pool.query("SELECT status FROM incidents WHERE id=?", [report.id]);
                if (rows.length > 0) previousStatus = rows[0].status;
            }

            const isActivation = isNewEmergency || (previousStatus && previousStatus.toLowerCase() === 'draft' && report.status.toLowerCase() !== 'draft');

            // This is an update (or new insert) to an existing incident
            await addIncident(report);
            
            // Delete the old draft record if one existed
            if (oldDraftId) {
                if (useMySQL) {
                    await pool.query("DELETE FROM incidents WHERE id = ?", [oldDraftId]);
                } else {
                    const db = JSON.parse(fs.readFileSync(JSON_DB_FILE, 'utf8'));
                    db.incidents = db.incidents.filter(i => i.id !== oldDraftId);
                    fs.writeFileSync(JSON_DB_FILE, JSON.stringify(db, null, 4));
                }
                io.emit('incident-deleted', { id: oldDraftId });
            }
            
            if (isNewEmergency) {
                io.emit('new-incident-alert', report);
            } else {
                io.emit('incident-updated', report);
            }
            console.log(`SOS Saved: ${report.id}`);
            
            if (isActivation) {
                await recordIncidentEvent(report.id, report.id, 'SOS alert activated', previousStatus, report.status, 'Citizen App');
                io.emit('incident_status_changed', report);
            } else {
                await recordIncidentEvent(report.id, report.id, 'Emergency Details Updated', null, report.status, 'Citizen App');
            }

            if (typeof callback === 'function') {
                callback({ success: true, ticketNumber: report.id, incident: report });
            }
        } catch (e) {
            console.error("SOS Socket save error:", e);
            if (typeof callback === 'function') {
                callback({ success: false, error: e.message });
            }
        }
    });
    // Admin chat message
    socket.on('dispatcher-chat-message', async (data) => {
        try {
            const { incidentId, message, media } = data;
            const dbState = await getDBState();
            let incident = dbState.incidents.find(i => i.id === incidentId);
            if (incident) {
                if (message) {
                    incident.details += ` | Dispatcher: ${message}`;
                }
                if (media) {
                    incident.media = incident.media || [];
                    incident.media.push(media);
                    incident.details += ` | Dispatcher attached a file.`;
                }
                await addIncident(incident);
                io.emit('incident-updated', incident);
            }
        } catch (e) {
            console.error("Dispatcher chat error:", e);
        }
    });

    // Admin call initiate
    socket.on('admin-call-initiate', (data) => {
        const { incidentId, type } = data;
        io.emit('call-status-updated', { type: type, status: 'ringing', caller: 'Command Center' });
    });

    // Dispatch responder unit
    socket.on('dispatch-responder-unit', async (data) => {
        try {
            const { incidentId, responderId } = data;
            const updates = await updateIncidentAndResponder(incidentId, responderId, 'enroute', 'busy');
            if (updates) {
                io.emit('incident-updated', updates.incident);
                io.emit('responder-updated', updates.responder);
                console.log(`Unit Dispatched: ${responderId} -> ${incidentId}`);
                await recordIncidentEvent(incidentId, incidentId, 'Responder Dispatched', 'pending', 'enroute', 'Command Center');
                await recordIncidentEvent(incidentId, incidentId, 'Responders En Route', 'pending', 'enroute', 'System');
            }
        } catch (e) {
            console.error("Dispatch socket update error:", e);
        }
    });

    // Responder coordinates update
    socket.on('responder-gps-update', async (data) => {
        try {
            const { id, lat, lng } = data;
            await updateResponderGPS(id, lat, lng);
            io.emit('responder-gps-changed', { id, lat, lng });
        } catch (e) {
            console.error("GPS Socket coordinates update error:", e);
        }
    });

    // Resolve incident
    socket.on('resolve-incident-status', async (data) => {
        try {
            const { incidentId, responderId } = data;
            const updates = await updateIncidentAndResponder(incidentId, responderId, 'resolved', 'available');
            if (updates) {
                // Also clear responseProgress and release vehicle
                if (useMySQL) {
                    await pool.query("UPDATE incidents SET responseProgress=NULL WHERE id=?", [incidentId]);
                    const [inc] = await pool.query("SELECT assignedVehicle FROM incidents WHERE id=?", [incidentId]);
                    if (inc[0] && inc[0].assignedVehicle) {
                        await pool.query("UPDATE rescue_vehicles SET status='Available' WHERE id=? OR name=?", [inc[0].assignedVehicle, inc[0].assignedVehicle]);
                        io.emit('vehicle_updated');
                    }
                    // Re-fetch updated incident
                    const [updatedInc] = await pool.query("SELECT * FROM incidents WHERE id=?", [incidentId]);
                    if (updatedInc[0]) updates.incident = updatedInc[0];
                }
                
                io.emit('incident-updated', updates.incident);
                io.emit('responder-updated', updates.responder);
                console.log(`Incident Resolved: ${incidentId}`);
                await recordIncidentEvent(incidentId, incidentId, 'Resolved', 'enroute', 'resolved', 'Command Center');
                await recordIncidentEvent(incidentId, incidentId, 'Closed', 'resolved', 'closed', 'System');
            }
        } catch (e) {
            console.error("Incident resolution socket update error:", e);
        }
    });

    // Global Command Warning Broadcast
    socket.on('broadcast-command-warning', async (broadcast) => {
        try {
            await saveBroadcast(broadcast);
            io.emit('broadcast-advisory', broadcast);
            console.log(`Advisory Broadcast: ${broadcast.title}`);
        } catch (e) {
            console.error("Advisory broadcast Socket save error:", e);
        }
    });

    // Call Status Sync relay (voice/video calls)
    socket.on('citizen-call-status-change', (data) => {
        io.emit('call-status-updated', data);
        console.log(`Call Status Change: ${data.reporter} (${data.type}) is ${data.status}`);
    });

    // Check-in coordinates mapping relay
    socket.on('citizen-checkin-alert', (data) => {
        io.emit('new-checkin-received', data);
        console.log(`Citizen Check-in: ${data.name} at [${data.lat}, ${data.lng}]`);
    });


    socket.on('disconnect', () => {
        console.log(`WebSocket Client Disconnected: ${socket.id}`);
    });
});

// Boot Database first, then launch Web Server
const PORT = process.env.PORT || 3000;
initDatabase().then(() => {
    server.listen(PORT, () => {
        console.log(`ALERTO-POZ server running on port ${PORT}`);
    });
});
