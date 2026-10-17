/**
 * Real-time WebSocket chat test for ALERTO-POZ
 * Tests Socket.IO real-time event broadcasting between Citizen, Admin, and Barangay Admin.
 */

const { io } = require('socket.io-client');
const http = require('http');

const PORT = process.env.TEST_PORT || 3000;
const URL = `http://localhost:${PORT}`;

async function runSocketTest() {
    console.log("=== WEBSOCKET REAL-TIME CHAT SYNCHRONIZATION TEST ===");

    const incidentId = 'WS-INC-' + Date.now();
    let passed = 0;
    let failed = 0;

    function assert(cond, name) {
        if (cond) {
            console.log(`  [PASS] ${name}`);
            passed++;
        } else {
            console.error(`  [FAIL] ${name}`);
            failed++;
        }
    }

    const citizenSocket = io(URL, { transports: ['websocket', 'polling'] });
    const adminSocket = io(URL, { transports: ['websocket', 'polling'] });
    const barangaySocket = io(URL, { transports: ['websocket', 'polling'] });

    await Promise.all([
        new Promise(r => citizenSocket.on('connect', r)),
        new Promise(r => adminSocket.on('connect', r)),
        new Promise(r => barangaySocket.on('connect', r))
    ]);

    assert(citizenSocket.connected && adminSocket.connected && barangaySocket.connected, "All three sockets connected to server");

    // Track received messages
    const receivedByCitizen = [];
    const receivedByAdmin = [];
    const receivedByBarangay = [];

    citizenSocket.on('chat-message-receive', msg => {
        if (String(msg.incident_id) === String(incidentId)) receivedByCitizen.push(msg);
    });
    adminSocket.on('chat-message-receive', msg => {
        if (String(msg.incident_id) === String(incidentId)) receivedByAdmin.push(msg);
    });
    barangaySocket.on('chat-message-receive', msg => {
        if (String(msg.incident_id) === String(incidentId)) receivedByBarangay.push(msg);
    });

    // 1. Citizen sends a message via HTTP POST
    const citMsgId = 'ws-cit-msg-1';
    await new Promise((resolve, reject) => {
        const boundary = '----Boundary' + Math.random().toString(36).substring(2);
        let payload = `--${boundary}\r\nContent-Disposition: form-data; name="senderId"\r\n\r\n101\r\n`;
        payload += `--${boundary}\r\nContent-Disposition: form-data; name="senderRole"\r\n\r\nCitizen App\r\n`;
        payload += `--${boundary}\r\nContent-Disposition: form-data; name="messageType"\r\n\r\ntext\r\n`;
        payload += `--${boundary}\r\nContent-Disposition: form-data; name="messageContent"\r\n\r\nCitizen reporting urgent situation\r\n`;
        payload += `--${boundary}\r\nContent-Disposition: form-data; name="clientMessageId"\r\n\r\n${citMsgId}\r\n`;
        payload += `--${boundary}--\r\n`;

        const req = http.request({
            hostname: 'localhost',
            port: PORT,
            path: `/api/incidents/${incidentId}/messages`,
            method: 'POST',
            headers: {
                'Content-Type': `multipart/form-data; boundary=${boundary}`,
                'Content-Length': Buffer.byteLength(payload)
            }
        }, res => {
            let data = '';
            res.on('data', c => data += c);
            res.on('end', () => resolve(JSON.parse(data)));
        });
        req.on('error', reject);
        req.write(payload);
        req.end();
    });

    // Wait 500ms for websocket propagation
    await new Promise(r => setTimeout(r, 600));

    assert(receivedByAdmin.length === 1 && receivedByAdmin[0].client_message_id === citMsgId, "Admin socket received citizen message in real-time");
    assert(receivedByBarangay.length === 1 && receivedByBarangay[0].client_message_id === citMsgId, "Barangay socket received citizen message in real-time");
    assert(receivedByCitizen.length === 1 && receivedByCitizen[0].client_message_id === citMsgId, "Citizen socket received broadcast confirmation");

    // 2. Admin sends message via dispatcher-chat-message socket event
    const adminMsgId = 'ws-admin-msg-2';
    adminSocket.emit('dispatcher-chat-message', {
        incidentId: incidentId,
        message: 'Command Center has acknowledged your report.',
        senderId: 'admin',
        senderRole: 'Command Center',
        clientMessageId: adminMsgId
    });

    await new Promise(r => setTimeout(r, 600));

    assert(receivedByCitizen.length === 2 && receivedByCitizen[1].client_message_id === adminMsgId, "Citizen socket received admin dispatcher message in real-time");
    assert(receivedByBarangay.length === 2 && receivedByBarangay[1].client_message_id === adminMsgId, "Barangay socket received admin dispatcher message in real-time");
    assert(receivedByCitizen[1].message_content === 'Command Center has acknowledged your report.', "Message content verified across sockets");

    // Close sockets
    citizenSocket.close();
    adminSocket.close();
    barangaySocket.close();

    console.log(`\n==============================================`);
    console.log(`WEBSOCKET SUMMARY: ${passed} Passed, ${failed} Failed`);
    console.log(`==============================================`);

    process.exit(failed === 0 ? 0 : 1);
}

runSocketTest().catch(err => {
    console.error("Socket test failed with error:", err);
    process.exit(1);
});
