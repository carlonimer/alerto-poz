const { verifyAdmin } = require('./middleware/auth.js');

module.exports = function(app, getDBState, pool, useMySQL) {

    const filterIncidents = (incidents, assigned_agency, barangay = null) => {
        return incidents.filter(i => {
            let agency = i.assigned_agency;
            if (!agency) {
                const cat = (i.category || '').toLowerCase();
                if (cat === 'fire') agency = 'BFP';
                else if (cat === 'medical' || cat === 'crime' || cat === 'police' || cat === 'road_crash' || cat === 'roadcrash') agency = 'PNP';
                else if (cat === 'barangay') agency = 'Barangay';
                else if (cat === 'report') agency = 'MDRRMO';
                else agency = 'MDRRMO';
            }
            if (agency !== assigned_agency) return false;
            if (barangay && i.barangay !== barangay) return false;
            return true;
        });
    };

    app.get('/api/auth/me', verifyAdmin(), (req, res) => {
        res.json({ user: req.admin });
    });

    app.get('/api/bfp/incidents', verifyAdmin(['bfp_admin']), async (req, res) => {
        const state = await getDBState();
        res.json({ incidents: filterIncidents(state.incidents, 'BFP') });
    });

    app.get('/api/pnp/incidents', verifyAdmin(['pnp_admin']), async (req, res) => {
        const state = await getDBState();
        res.json({ incidents: filterIncidents(state.incidents, 'PNP') });
    });

    app.get('/api/mdrrmo/incidents', verifyAdmin(['mdrrmo_admin']), async (req, res) => {
        const state = await getDBState();
        res.json({ incidents: filterIncidents(state.incidents, 'MDRRMO') });
    });

    app.get('/api/barangays/:id/incidents', verifyAdmin(['barangay_admin']), async (req, res) => {
        // Enforce the user can only fetch their own barangay
        if (req.admin.barangay !== req.params.id) {
            return res.status(403).json({ error: "Access denied to other barangay's incidents." });
        }
        const state = await getDBState();
        res.json({ incidents: filterIncidents(state.incidents, 'Barangay', req.params.id) });
    });

    // MDRRMO Assistance Requests
    app.get('/api/mdrrmo/assistance-requests', verifyAdmin(['mdrrmo_admin']), async (req, res) => {
        if (useMySQL) {
            const [rows] = await pool.query("SELECT * FROM barangay_assistance_requests ORDER BY created_at DESC LIMIT 50");
            res.json({ requests: rows });
        } else {
            res.json({ requests: [] });
        }
    });

    // MDRRMO Alerts
    app.post('/api/mdrrmo/alerts', verifyAdmin(['mdrrmo_admin']), async (req, res) => {
        // Town-wide alert creation logic here
        const { title, message, category, alert_level } = req.body;
        const ts = Date.now();
        const id = `ALERT-${ts}`;
        
        if (useMySQL) {
            await pool.query(
                "INSERT INTO broadcasts (id, title, category, message, alert_level, scope, timestamp) VALUES (?, ?, ?, ?, ?, 'town', ?)",
                [id, title || '', category || 'warning', message, alert_level || 'WHITE', ts]
            );
        }
        
        const alertData = { id, title, category, message, alert_level, scope: 'town', timestamp: ts };
        app.get('io').emit('new-broadcast', alertData);

        res.json({ success: true, alert: alertData });
    });

    // Barangay Assistance Requests
    app.post('/api/barangay/assistance-request', verifyAdmin(['barangay_admin']), async (req, res) => {
        const { lat, lng, description, incident_id } = req.body;
        const barangay_id = req.admin.barangay; // Force from token
        const reqId = `BRGY-REQ-${Date.now()}`;
        const ts = Date.now();
        
        if (useMySQL) {
            await pool.query(
                "INSERT INTO barangay_assistance_requests (id, barangay, requested_by, incident_id, lat, lng, description, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                [reqId, barangay_id, req.admin.name, incident_id || null, lat, lng, description || '', ts]
            );
        }
        
        // Notify MDRRMO via Socket
        const reqData = { id: reqId, barangay: barangay_id, requested_by: req.admin.name, incident_id, lat, lng, description, status: 'Pending', created_at: ts };
        
        // Emit specifically to MDRRMO admins if they joined a room, or emit globally and let frontend filter
        // We can use a socket room if we implement socket auth, else emit globally for now and MDRRMO filters it
        app.get('io').emit('barangay-assistance-request', reqData);

        res.json({ success: true, request: reqData });
    });
};
