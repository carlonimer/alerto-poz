async function initDatabase(pool) {
    // 1. Users Table
    await pool.query(`
        CREATE TABLE IF NOT EXISTS users (
            id INT AUTO_INCREMENT PRIMARY KEY,
            email VARCHAR(100) UNIQUE NULL,
            phone VARCHAR(15) UNIQUE NULL,
            password VARCHAR(255) NOT NULL,
            name VARCHAR(100) NOT NULL,
            type VARCHAR(20) NOT NULL DEFAULT 'citizen',
            active TINYINT NOT NULL DEFAULT 0,
            otp_code VARCHAR(6) NULL,
            otp_expires BIGINT NULL,
            otp_type VARCHAR(15) NULL,
            profile_image LONGTEXT NULL,
            passcode VARCHAR(255) NULL,
            updated_at BIGINT NULL,
            created_at BIGINT NULL,
            barangay VARCHAR(100) NULL,
            first_name VARCHAR(100) NULL,
            middle_name VARCHAR(100) NULL,
            last_name VARCHAR(100) NULL,
            suffix VARCHAR(20) NULL,
            birthdate VARCHAR(20) NULL,
            gender VARCHAR(20) NULL,
            address TEXT NULL,
            unit_id VARCHAR(50) NULL
        );
    `);
    
    // Add columns if they don't exist (for backward compatibility on existing databases)
    const userColumns = [
        "unit_id VARCHAR(50) NULL",
        "profile_image LONGTEXT NULL",
        "passcode VARCHAR(255) NULL",
        "updated_at BIGINT NULL",
        "created_at BIGINT NULL",
        "barangay VARCHAR(100) NULL",
        "first_name VARCHAR(100) NULL",
        "middle_name VARCHAR(100) NULL",
        "last_name VARCHAR(100) NULL",
        "suffix VARCHAR(20) NULL",
        "birthdate VARCHAR(20) NULL",
        "gender VARCHAR(20) NULL",
        "address TEXT NULL"
    ];
    for (const col of userColumns) {
        try { await pool.query(`ALTER TABLE users ADD COLUMN ${col}`); } catch(e) {}
    }

    // 2. Feedbacks Table
    await pool.query(`
        CREATE TABLE IF NOT EXISTS feedbacks (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            subject VARCHAR(255) NOT NULL,
            category VARCHAR(50) NOT NULL,
            message TEXT NOT NULL,
            status VARCHAR(20) NOT NULL DEFAULT 'pending',
            media_path LONGTEXT NULL,
            created_at BIGINT NOT NULL,
            updated_at BIGINT NOT NULL
        );
    `);
    try { await pool.query("ALTER TABLE feedbacks ADD COLUMN media_path LONGTEXT NULL"); } catch(e) {}

    // 3. Activity Logs Table
    await pool.query(`
        CREATE TABLE IF NOT EXISTS activity_logs (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            action VARCHAR(255) NOT NULL,
            date VARCHAR(20) NOT NULL,
            time VARCHAR(20) NOT NULL,
            ip_address VARCHAR(50) NULL,
            device VARCHAR(255) NULL,
            created_at BIGINT NOT NULL
        );
    `);

    // 4. Map Settings Table
    await pool.query(`
        CREATE TABLE IF NOT EXISTS map_settings (
            user_id INT PRIMARY KEY,
            map_type VARCHAR(20) NOT NULL DEFAULT 'standard',
            live_location TINYINT NOT NULL DEFAULT 0,
            gps_enabled TINYINT NOT NULL DEFAULT 1,
            real_time_tracking TINYINT NOT NULL DEFAULT 0,
            show_traffic TINYINT NOT NULL DEFAULT 0,
            show_disaster_zones TINYINT NOT NULL DEFAULT 1,
            show_evacuation_centers TINYINT NOT NULL DEFAULT 1,
            show_barangay_boundaries TINYINT NOT NULL DEFAULT 1,
            last_location VARCHAR(100) NULL,
            navigation_preference VARCHAR(50) NOT NULL DEFAULT 'Fastest Route',
            notification_radius INT NOT NULL DEFAULT 500,
            emergency_alert_radius INT NOT NULL DEFAULT 1000,
            auto_refresh TINYINT NOT NULL DEFAULT 1,
            dark_mode TINYINT NOT NULL DEFAULT 0,
            created_at BIGINT NOT NULL,
            updated_at BIGINT NOT NULL
        );
    `);
    
    const mapColumns = [
        "navigation_preference VARCHAR(50) NOT NULL DEFAULT 'Fastest Route'",
        "notification_radius INT NOT NULL DEFAULT 500",
        "emergency_alert_radius INT NOT NULL DEFAULT 1000",
        "auto_refresh TINYINT NOT NULL DEFAULT 1",
        "dark_mode TINYINT NOT NULL DEFAULT 0"
    ];
    for (const col of mapColumns) {
        try { await pool.query(`ALTER TABLE map_settings ADD COLUMN ${col}`); } catch(e) {}
    }

    // 5. Incidents Table
    await pool.query(`
        CREATE TABLE IF NOT EXISTS incidents (
            id VARCHAR(20) PRIMARY KEY,
            category VARCHAR(20) NOT NULL,
            details TEXT,
            lat DOUBLE NOT NULL,
            lng DOUBLE NOT NULL,
            reporter VARCHAR(100) NOT NULL,
            reporterPhone VARCHAR(15) NOT NULL,
            createdAt BIGINT NOT NULL,
            networkReceivedAt BIGINT,
            barangay VARCHAR(100) NULL,
            status VARCHAR(30) NOT NULL DEFAULT 'Draft',
            assignedUnit VARCHAR(50) DEFAULT NULL,
            sos_sent TINYINT NOT NULL DEFAULT 0,
            closed_at BIGINT NULL,
            closed_by VARCHAR(100) NULL,
            assignedVehicle VARCHAR(100) DEFAULT NULL,
            assignedResponders VARCHAR(255) DEFAULT NULL,
            resolutionDate BIGINT NULL,
            notes TEXT NULL
        );
    `);

    const incidentColumns = [
        "sos_sent TINYINT NOT NULL DEFAULT 0",
        "closed_at BIGINT NULL",
        "closed_by VARCHAR(100) NULL",
        "assignedVehicle VARCHAR(100) DEFAULT NULL",
        "assignedResponders VARCHAR(255) DEFAULT NULL",
        "resolutionDate BIGINT NULL",
        "notes TEXT NULL",
        "barangay VARCHAR(100) NULL",
        "responseProgress VARCHAR(30) DEFAULT NULL",
        "reporterId INT NULL",
        "media LONGTEXT",
        "has_sent_messages TINYINT NOT NULL DEFAULT 0",
        "assigned_agency VARCHAR(50) NULL"
    ];
    for (const col of incidentColumns) {
        try { await pool.query(`ALTER TABLE incidents ADD COLUMN ${col}`); } catch(e) {}
    }

    // 6. Incident Events (History) Table
    await pool.query(`
        CREATE TABLE IF NOT EXISTS incident_events (
            id INT AUTO_INCREMENT PRIMARY KEY,
            incident_id VARCHAR(20) NOT NULL,
            ticket_number VARCHAR(50) NULL,
            event_status VARCHAR(100) NOT NULL,
            previous_status VARCHAR(50) NULL,
            new_status VARCHAR(50) NULL,
            actor_source VARCHAR(100) NOT NULL,
            date_str VARCHAR(20) NOT NULL,
            time_str VARCHAR(20) NOT NULL,
            timestamp BIGINT NOT NULL,
            INDEX(incident_id)
        );
    `);

    // 6.5. Messages Table
    await pool.query(`
        CREATE TABLE IF NOT EXISTS messages (
            id INT AUTO_INCREMENT PRIMARY KEY,
            incident_id VARCHAR(50) NOT NULL,
            sender_id VARCHAR(50) NOT NULL,
            sender_role VARCHAR(50) NOT NULL,
            message_type VARCHAR(20) NOT NULL DEFAULT 'text',
            message_content TEXT NULL,
            media_url VARCHAR(255) NULL,
            timestamp BIGINT NOT NULL,
            INDEX(incident_id)
        );
    `);

    // 7. Responders Table
    await pool.query(`
        CREATE TABLE IF NOT EXISTS responders (
            id VARCHAR(50) PRIMARY KEY,
            name VARCHAR(100) NOT NULL,
            type VARCHAR(20) NOT NULL,
            lat DOUBLE NOT NULL,
            lng DOUBLE NOT NULL,
            base_lat DOUBLE NULL,
            base_lng DOUBLE NULL,
            status VARCHAR(20) NOT NULL DEFAULT 'available',
            icon VARCHAR(50) NOT NULL
        );
    `);
    try { await pool.query("ALTER TABLE responders ADD COLUMN base_lat DOUBLE NULL"); } catch(e) {}
    try { await pool.query("ALTER TABLE responders ADD COLUMN base_lng DOUBLE NULL"); } catch(e) {}

    // 7. Broadcasts / Town-Wide Alerts Table
    await pool.query(`
        CREATE TABLE IF NOT EXISTS broadcasts (
            id VARCHAR(50) PRIMARY KEY,
            title VARCHAR(150) NOT NULL,
            category VARCHAR(20) NOT NULL,
            message TEXT NOT NULL,
            alert_level VARCHAR(20) NULL,
            scope VARCHAR(20) DEFAULT 'town',
            barangay_id VARCHAR(100) NULL,
            is_active TINYINT DEFAULT 1,
            expires_at BIGINT NULL,
            timestamp BIGINT NOT NULL
        );
    `);
    
    const broadcastCols = [
        "alert_level VARCHAR(20) NULL",
        "scope VARCHAR(20) DEFAULT 'town'",
        "barangay_id VARCHAR(100) NULL",
        "is_active TINYINT DEFAULT 1",
        "expires_at BIGINT NULL"
    ];
    for (const col of broadcastCols) {
        try { await pool.query(`ALTER TABLE broadcasts ADD COLUMN ${col}`); } catch(e) {}
    }

    // 7.5 Barangay Assistance Requests Table
    await pool.query(`
        CREATE TABLE IF NOT EXISTS barangay_assistance_requests (
            id VARCHAR(50) PRIMARY KEY,
            barangay VARCHAR(100) NOT NULL,
            requested_by VARCHAR(100) NULL,
            incident_id VARCHAR(50) NULL,
            lat DOUBLE NOT NULL,
            lng DOUBLE NOT NULL,
            description TEXT NULL,
            status VARCHAR(30) NOT NULL DEFAULT 'Pending',
            created_at BIGINT NOT NULL,
            responded_at BIGINT NULL,
            resolved_at BIGINT NULL
        );
    `);

    // 8. Rescue Vehicles Table
    await pool.query(`
        CREATE TABLE IF NOT EXISTS rescue_vehicles (
            id INT AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(100) NOT NULL,
            number VARCHAR(50) NOT NULL,
            type VARCHAR(50) NOT NULL,
            agency VARCHAR(100) NOT NULL,
            driver VARCHAR(100) NULL,
            status VARCHAR(50) NOT NULL DEFAULT 'Available',
            fuel_status VARCHAR(50) NULL,
            lat DOUBLE NULL,
            lng DOUBLE NULL
        );
    `);

    // 9. Water Devices Table
    await pool.query(`
        CREATE TABLE IF NOT EXISTS water_devices (
            id INT AUTO_INCREMENT PRIMARY KEY,
            device_id VARCHAR(50) UNIQUE NOT NULL,
            name VARCHAR(100) NOT NULL,
            type VARCHAR(50) NOT NULL,
            barangay VARCHAR(100) NOT NULL,
            location VARCHAR(255) NOT NULL,
            lat DOUBLE NOT NULL,
            lng DOUBLE NOT NULL,
            status VARCHAR(50) NOT NULL DEFAULT 'Operational',
            capacity VARCHAR(50) NULL,
            last_inspection BIGINT NULL,
            personnel VARCHAR(100) NULL,
            notes TEXT NULL
        );
    `);

    // Preseed responders table if empty
    const [responderCount] = await pool.query("SELECT COUNT(*) as count FROM responders");
    if (responderCount[0].count === 0) {
        await pool.query(`
            INSERT INTO responders (id, name, type, lat, lng, status, icon) VALUES
            ('poz-ems-1', 'Pozorrubio Ambulance 1', 'medical', 16.1086, 120.5424, 'available', 'fa-truck-medical'),
            ('poz-ems-2', 'Pangasinan Red Cross (Manaoag Sub)', 'medical', 16.0435, 120.4850, 'available', 'fa-truck-medical'),
            ('poz-fire-1', 'Pozorrubio BFP Fire Truck 1', 'fire', 16.1145, 120.5466, 'available', 'fa-fire-extinguisher'),
            ('poz-police-1', 'Pozorrubio PNP Mobile Patrol 1', 'police', 16.1115, 120.5484, 'available', 'fa-shield-halved'),
            ('poz-police-2', 'Pozorrubio PNP Mobile Patrol 2', 'police', 16.0820, 120.5180, 'available', 'fa-shield-halved');
        `);
    }

    // Check if the specific admin accounts exist
    const [adminCount] = await pool.query("SELECT COUNT(*) as count FROM users WHERE email IN ('mdrrmo@pozorrubio.gov.ph', 'bfp@pozorrubio.gov.ph', 'pnp@pozorrubio.gov.ph', 'buneg@pozorrubio.gov.ph')");
    
    if (adminCount[0].count < 4) {
        // Use INSERT IGNORE in case some exist but not others
        await pool.query(`
            INSERT IGNORE INTO users (name, email, phone, password, type, active, barangay) VALUES
            ('MDRRMO Admin', 'mdrrmo@pozorrubio.gov.ph', '09998887777', '$2a$10$uHA89lKJ9z2wwQmccanrtOO6i6SW.gi6YheTvcuRXETSyKQt9G0zm', 'mdrrmo_admin', 1, NULL),
            ('BFP Admin', 'bfp@pozorrubio.gov.ph', '09998887771', '$2a$10$uHA89lKJ9z2wwQmccanrtOO6i6SW.gi6YheTvcuRXETSyKQt9G0zm', 'bfp_admin', 1, NULL),
            ('PNP Admin', 'pnp@pozorrubio.gov.ph', '09998887772', '$2a$10$uHA89lKJ9z2wwQmccanrtOO6i6SW.gi6YheTvcuRXETSyKQt9G0zm', 'pnp_admin', 1, NULL),
            ('Brgy Buneg Admin', 'buneg@pozorrubio.gov.ph', '09998887773', '$2a$10$uHA89lKJ9z2wwQmccanrtOO6i6SW.gi6YheTvcuRXETSyKQt9G0zm', 'barangay_admin', 1, 'Buneg');
        `);
        console.log("Admin panel accounts seeded/updated.");
    }

    // Backward compatibility: upgrade old 'authority' type to 'mdrrmo_admin'
    await pool.query("UPDATE users SET type = 'mdrrmo_admin' WHERE type = 'authority'");
    
    // Force reset all admin passwords to 'admin123' to fix login issues
    await pool.query("UPDATE users SET password = '$2a$10$uHA89lKJ9z2wwQmccanrtOO6i6SW.gi6YheTvcuRXETSyKQt9G0zm' WHERE email LIKE '%@pozorrubio.gov.ph'");
    console.log("Admin passwords forced to admin123.");
}

module.exports = { initDatabase };
