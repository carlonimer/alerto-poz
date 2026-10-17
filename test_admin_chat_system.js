/**
 * Comprehensive Automated Test Suite for ALERTO-POZ Admin Chat System
 * Tests:
 * 1. Admin Authentication & Role-based Incident Retrieval (MDRRMO, Barangay, BFP, PNP)
 * 2. Incident filtering ensuring Barangay Admins receive incidents occurring in their barangay
 * 3. Citizen -> Admin Text and Media (Image/Video) Messaging
 * 4. Admin -> Citizen Text and Media Messaging
 * 5. Server-side Idempotency preventing duplicate messages upon rapid clicks
 * 6. Message timestamp chronological ascending ordering
 * 7. Verification that attachments, captions, and proof-of-evidence are preserved
 */

const http = require('http');
const fs = require('fs');
const path = require('path');

// Test against local server instance
const PORT = process.env.TEST_PORT || 3000;
const BASE_URL = `http://localhost:${PORT}`;

function request(options, postData = null, headers = {}) {
    return new Promise((resolve, reject) => {
        const url = new URL(options.path || '/', BASE_URL);
        const reqOptions = {
            hostname: url.hostname,
            port: url.port,
            path: url.pathname + url.search,
            method: options.method || 'GET',
            headers: {
                ...headers,
                ...(options.headers || {})
            }
        };

        const req = http.request(reqOptions, (res) => {
            let body = '';
            res.on('data', chunk => body += chunk);
            res.on('end', () => {
                let parsed = null;
                try {
                    parsed = JSON.parse(body);
                } catch(e) {
                    parsed = body;
                }
                resolve({ status: res.statusCode, headers: res.headers, data: parsed });
            });
        });

        req.on('error', reject);

        if (postData) {
            req.write(postData);
        }
        req.end();
    });
}

function sendMultipart(incidentId, fields, filePath = null, token = null) {
    return new Promise((resolve, reject) => {
        const boundary = '----WebKitFormBoundary' + Math.random().toString(36).substring(2);
        let payload = '';

        for (const [key, val] of Object.entries(fields)) {
            payload += `--${boundary}\r\n`;
            payload += `Content-Disposition: form-data; name="${key}"\r\n\r\n`;
            payload += `${val}\r\n`;
        }

        let fileBuffer = null;
        if (filePath && fs.existsSync(filePath)) {
            const filename = path.basename(filePath);
            const ext = path.extname(filePath).toLowerCase();
            const mimeType = ext === '.mp4' ? 'video/mp4' : (ext === '.png' ? 'image/png' : 'image/jpeg');

            payload += `--${boundary}\r\n`;
            payload += `Content-Disposition: form-data; name="media"; filename="${filename}"\r\n`;
            payload += `Content-Type: ${mimeType}\r\n\r\n`;

            fileBuffer = Buffer.concat([
                Buffer.from(payload, 'utf8'),
                fs.readFileSync(filePath),
                Buffer.from(`\r\n--${boundary}--\r\n`, 'utf8')
            ]);
        } else {
            payload += `--${boundary}--\r\n`;
            fileBuffer = Buffer.from(payload, 'utf8');
        }

        const headers = {
            'Content-Type': `multipart/form-data; boundary=${boundary}`,
            'Content-Length': fileBuffer.length
        };
        if (token) {
            headers['Authorization'] = `Bearer ${token}`;
        }

        const req = http.request({
            hostname: 'localhost',
            port: PORT,
            path: `/api/incidents/${incidentId}/messages`,
            method: 'POST',
            headers
        }, (res) => {
            let body = '';
            res.on('data', chunk => body += chunk);
            res.on('end', () => {
                try {
                    resolve({ status: res.statusCode, data: JSON.parse(body) });
                } catch (e) {
                    resolve({ status: res.statusCode, data: body });
                }
            });
        });

        req.on('error', reject);
        req.write(fileBuffer);
        req.end();
    });
}

async function runTests() {
    console.log("=== ALERTO-POZ ADMIN CHAT SYSTEM VALIDATION ===");

    // Create a temporary dummy image and video for testing attachments
    const tempDir = path.join(__dirname, 'test_media_temp');
    if (!fs.existsSync(tempDir)) fs.mkdirSync(tempDir, { recursive: true });
    
    const sampleImgPath = path.join(tempDir, 'test_evidence.jpg');
    fs.writeFileSync(sampleImgPath, Buffer.from([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x01, 0x00, 0x60, 0x00, 0x60, 0x00, 0x00, 0xFF, 0xD9]));

    const sampleVideoPath = path.join(tempDir, 'test_video.mp4');
    fs.writeFileSync(sampleVideoPath, Buffer.from("dummy mp4 video stream content for testing upload pipeline"));

    let passed = 0;
    let failed = 0;

    function assert(condition, testName) {
        if (condition) {
            console.log(`  [PASS] ${testName}`);
            passed++;
        } else {
            console.error(`  [FAIL] ${testName}`);
            failed++;
        }
    }

    try {
        // 1. Admin Login Tests
        console.log("\n1. Testing Admin Authentication...");
        const mdrrmoLogin = await request({ method: 'POST', path: '/api/auth/admin-login' }, 
            JSON.stringify({ username: 'mdrrmo@pozorrubio.gov.ph', password: 'admin123' }), 
            { 'Content-Type': 'application/json' }
        );
        assert(mdrrmoLogin.status === 200 && mdrrmoLogin.data.success, "MDRRMO admin login succeeds");
        const mdrrmoToken = mdrrmoLogin.data.token;

        const barangayLogin = await request({ method: 'POST', path: '/api/auth/admin-login' }, 
            JSON.stringify({ username: 'buneg@pozorrubio.gov.ph', password: 'admin123' }), 
            { 'Content-Type': 'application/json' }
        );
        assert(barangayLogin.status === 200 && barangayLogin.data.success, "Barangay Buneg admin login succeeds");
        const barangayToken = barangayLogin.data.token;

        // 2. Incident Creation in Barangay Buneg
        console.log("\n2. Testing Incident Creation & RBAC Visibility...");
        const testIncidentId = 'TEST-INC-' + Date.now();
        const createInc = await request({ method: 'POST', path: '/api/incidents' },
            JSON.stringify({
                id: testIncidentId,
                category: 'Medical',
                barangay: 'Buneg',
                lat: 16.118685,
                lng: 120.566796,
                reporter: 'Juan Dela Cruz',
                reporterPhone: '09123456789',
                details: 'Severe allergic reaction reported | Dispatcher awaiting contact',
                status: 'pending'
            }),
            { 'Content-Type': 'application/json' }
        );
        assert(createInc.status === 200 || createInc.status === 201, `Incident created: ${testIncidentId}`);

        // MDRRMO should see it
        const mdrrmoInc = await request({ method: 'GET', path: '/api/mdrrmo/incidents' }, null, { 'Authorization': `Bearer ${mdrrmoToken}` });
        const mdrrmoFound = mdrrmoInc.data.incidents && mdrrmoInc.data.incidents.some(i => i.id === testIncidentId);
        assert(mdrrmoFound, "MDRRMO admin receives the new emergency incident");

        // Barangay Buneg admin should also see it because it occurred in Buneg
        const bgyInc = await request({ method: 'GET', path: `/api/barangays/Buneg/incidents` }, null, { 'Authorization': `Bearer ${barangayToken}` });
        const bgyFound = bgyInc.data.incidents && bgyInc.data.incidents.some(i => i.id === testIncidentId);
        assert(bgyFound, "Barangay Buneg admin receives the incident occurring in Buneg");

        // 3. Citizen -> Admin Messages
        console.log("\n3. Testing Citizen Messaging & Media Uploads...");
        const citizenClientMsg1 = 'cit-txt-' + Date.now();
        const citTextRes = await sendMultipart(testIncidentId, {
            senderId: '101',
            senderRole: 'Citizen App',
            messageType: 'text',
            messageContent: 'Help, the patient needs immediate assistance!',
            clientMessageId: citizenClientMsg1
        });
        assert(citTextRes.status === 200 && citTextRes.data.success, "Citizen text message submitted successfully");

        // Citizen sends Image Attachment with Camera Proof of Evidence
        const citizenClientMsg2 = 'cit-img-' + Date.now();
        const citImgRes = await sendMultipart(testIncidentId, {
            senderId: '101',
            senderRole: 'Citizen App',
            messageType: 'image',
            messageContent: 'Patient photo attached with proof',
            clientMessageId: citizenClientMsg2
        }, sampleImgPath);
        assert(citImgRes.status === 200 && citImgRes.data.success && citImgRes.data.message.media_url, "Citizen image attachment uploaded successfully with media_url");
        const uploadedImgUrl = citImgRes.data.message.media_url;

        // Citizen sends Video Attachment
        const citizenClientMsg3 = 'cit-vid-' + Date.now();
        const citVidRes = await sendMultipart(testIncidentId, {
            senderId: '101',
            senderRole: 'Citizen App',
            messageType: 'video',
            messageContent: 'Video of patient breathing difficulty',
            clientMessageId: citizenClientMsg3
        }, sampleVideoPath);
        assert(citVidRes.status === 200 && citVidRes.data.success && citVidRes.data.message.media_url, "Citizen video attachment uploaded successfully with media_url");

        // 4. Server-Side Idempotency Test (Rapid Taps Prevention)
        console.log("\n4. Testing Idempotency & Duplicate Prevention...");
        const duplicateRes = await sendMultipart(testIncidentId, {
            senderId: '101',
            senderRole: 'Citizen App',
            messageType: 'image',
            messageContent: 'Patient photo attached with proof',
            clientMessageId: citizenClientMsg2 // Re-using identical clientMessageId
        }, sampleImgPath);
        assert(duplicateRes.status === 200 && duplicateRes.data.duplicate === true, "Duplicate submission with same clientMessageId detected and deduplicated");

        // 5. Admin -> Citizen Messaging
        console.log("\n5. Testing Admin & Barangay Admin Messaging...");
        const adminClientMsg1 = 'admin-txt-' + Date.now();
        const adminTextRes = await sendMultipart(testIncidentId, {
            senderId: 'admin',
            senderRole: 'Command Center',
            messageType: 'text',
            messageContent: 'MDRRMO Rescue Unit 1 is en route to your location. Keep calm.',
            clientMessageId: adminClientMsg1
        }, null, mdrrmoToken);
        assert(adminTextRes.status === 200 && adminTextRes.data.success, "MDRRMO Admin sends text message successfully");

        // Barangay admin sending message
        const bgyClientMsg1 = 'bgy-txt-' + Date.now();
        const bgyTextRes = await sendMultipart(testIncidentId, {
            senderId: 'barangay_buneg',
            senderRole: 'Barangay Buneg Official',
            messageType: 'text',
            messageContent: 'Barangay tanods have been dispatched to assist on site.',
            clientMessageId: bgyClientMsg1
        }, null, barangayToken);
        assert(bgyTextRes.status === 200 && bgyTextRes.data.success, "Barangay Admin sends text message successfully");

        // Admin sending attachment
        const adminClientMsg2 = 'admin-img-' + Date.now();
        const adminImgRes = await sendMultipart(testIncidentId, {
            senderId: 'admin',
            senderRole: 'Command Center',
            messageType: 'image',
            messageContent: 'Ambulance location dispatch map',
            clientMessageId: adminClientMsg2
        }, sampleImgPath, mdrrmoToken);
        assert(adminImgRes.status === 200 && adminImgRes.data.success && adminImgRes.data.message.media_url, "Admin sends image attachment successfully");

        // 6. Message Retrieval, Ordering, and Attachment Verification
        console.log("\n6. Testing Message Retrieval, Deduplication & Ordering...");
        const getMsgsRes = await request({ method: 'GET', path: `/api/incidents/${testIncidentId}/messages` });
        assert(getMsgsRes.status === 200 && getMsgsRes.data.success, "Fetch messages endpoint returns 200 OK");
        
        const messages = getMsgsRes.data.messages || [];
        console.log(`  Fetched ${messages.length} messages for incident ${testIncidentId}`);

        // Ascending timestamp check
        let isAscending = true;
        for (let i = 1; i < messages.length; i++) {
            if (Number(messages[i].timestamp) < Number(messages[i - 1].timestamp)) {
                isAscending = false;
                break;
            }
        }
        assert(isAscending, "All messages are strictly ordered in ascending chronological order");

        // Verify initial category message
        const hasCategoryMsg = messages.some(m => (m.message_content || '').toUpperCase().includes('SELECTED EMERGENCY: MEDICAL'));
        assert(hasCategoryMsg, "Initial Selected Emergency: MEDICAL category message is present");

        // Verify image attachment accessibility
        const imgAccessRes = await request({ method: 'GET', path: uploadedImgUrl });
        assert(imgAccessRes.status === 200, `Uploaded image is accessible via HTTP at ${uploadedImgUrl}`);

        // Verify no duplicate IDs
        const ids = messages.map(m => m.id);
        const uniqueIds = new Set(ids);
        assert(ids.length === uniqueIds.size, `No duplicate message IDs found (${ids.length} messages)`);

        console.log(`\n==============================================`);
        console.log(`TEST SUMMARY: ${passed} Passed, ${failed} Failed`);
        console.log(`==============================================`);

    } catch (e) {
        console.error("Test execution error:", e);
        failed++;
    } finally {
        // Clean up temp test files
        try {
            if (fs.existsSync(sampleImgPath)) fs.unlinkSync(sampleImgPath);
            if (fs.existsSync(sampleVideoPath)) fs.unlinkSync(sampleVideoPath);
            if (fs.existsSync(tempDir)) fs.rmdirSync(tempDir);
        } catch(e) {}

        process.exit(failed === 0 ? 0 : 1);
    }
}

runTests();
