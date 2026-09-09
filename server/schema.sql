-- ==========================================================================
-- ALERTO-POZ DATABASE SCHEMA
-- Pozorrubio, Pangasinan Emergency Notification & Response System
-- ALERTO: An Integrated Emergency Notification and Response Application
-- ==========================================================================

CREATE DATABASE IF NOT EXISTS alerto_poz;
USE alerto_poz;

-- 1. Users Table (Authentication & Citizen Profiles)
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(100) UNIQUE NULL,
    phone VARCHAR(15) UNIQUE NULL,
    password VARCHAR(255) NOT NULL,
    name VARCHAR(100) NOT NULL,
    type VARCHAR(20) NOT NULL DEFAULT 'citizen',
    active TINYINT NOT NULL DEFAULT 0,
    otp_code VARCHAR(255) NULL,
    otp_expires BIGINT NULL,
    otp_type VARCHAR(15) NULL,
    passcode VARCHAR(255) NULL,
    barangay VARCHAR(100) NULL,
    unit_id VARCHAR(50) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Note: The unit_id column links a responder user to their specific responder unit in the responders table.

-- 2. Incidents Table (Emergency Reports)
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
    status VARCHAR(30) NOT NULL DEFAULT 'Draft',
    assignedUnit VARCHAR(50) DEFAULT NULL,
    assignedVehicle VARCHAR(100) DEFAULT NULL,
    assignedResponders VARCHAR(255) DEFAULT NULL,
    resolutionDate BIGINT NULL,
    notes TEXT NULL
);

-- 3. Responders Table (Emergency Response Units)
CREATE TABLE IF NOT EXISTS responders (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    type VARCHAR(20) NOT NULL,    -- 'medical', 'fire', 'police'
    lat DOUBLE NOT NULL,
    lng DOUBLE NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'available',    -- 'available', 'busy'
    icon VARCHAR(50) NOT NULL
);

-- 4. Broadcasts Archive Table (Public Alerts & Advisories)
CREATE TABLE IF NOT EXISTS broadcasts (
    id VARCHAR(20) PRIMARY KEY,
    title VARCHAR(150) NOT NULL,
    category VARCHAR(20) NOT NULL,    -- 'info', 'warning', 'evacuate'
    message TEXT NOT NULL,
    timestamp BIGINT NOT NULL
);

-- 5. Rescue Vehicles Table
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

-- 6. Water Devices Table
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

-- ==========================================================================
-- PRE-SEEDED DATA
-- Only the admin panel account is pre-created.
-- Citizens must register through the mobile application.
-- ==========================================================================

-- Seed First Responders (Local Pozorrubio Units)
INSERT INTO responders (id, name, type, lat, lng, status, icon) VALUES
('poz-ems-1', 'Pozorrubio Ambulance 1', 'medical', 16.1086, 120.5424, 'available', 'fa-truck-medical'),
('poz-ems-2', 'Pangasinan Red Cross (Manaoag Sub)', 'medical', 16.0435, 120.4850, 'available', 'fa-truck-medical'),
('poz-fire-1', 'Pozorrubio BFP Fire Truck 1', 'fire', 16.1118, 120.5487, 'available', 'fa-fire-extinguisher'),
('poz-police-1', 'Pozorrubio PNP Mobile Patrol 1', 'police', 16.1115, 120.5484, 'available', 'fa-shield-halved'),
('poz-police-2', 'Pozorrubio PNP Mobile Patrol 2', 'police', 16.0820, 120.5180, 'available', 'fa-shield-halved')
ON DUPLICATE KEY UPDATE name=VALUES(name), lat=VALUES(lat), lng=VALUES(lng), status=VALUES(status);

-- Seed Admin Panel Account (password: 1234)
INSERT INTO users (name, email, phone, password, type, active) VALUES
('Pozorrubio MDRRMO Admin', 'admin', '09998887777', '$2a$10$aMdHgKF23fA5REXdvzCzKe/FGE.LcxsApAdgui3hCdL/FOdd3B59i', 'authority', 1)
ON DUPLICATE KEY UPDATE name=VALUES(name);

-- Seed Responder Accounts (password: 1234)
INSERT INTO users (name, email, phone, password, type, active, unit_id) VALUES
('Pozorrubio EMS 1', 'ems1', '09111111111', '$2a$10$aMdHgKF23fA5REXdvzCzKe/FGE.LcxsApAdgui3hCdL/FOdd3B59i', 'responder', 1, 'poz-ems-1'),
('Pozorrubio Fire 1', 'fire1', '09222222222', '$2a$10$aMdHgKF23fA5REXdvzCzKe/FGE.LcxsApAdgui3hCdL/FOdd3B59i', 'responder', 1, 'poz-fire-1'),
('Pozorrubio Police 1', 'police1', '09333333333', '$2a$10$aMdHgKF23fA5REXdvzCzKe/FGE.LcxsApAdgui3hCdL/FOdd3B59i', 'responder', 1, 'poz-police-1')
ON DUPLICATE KEY UPDATE name=VALUES(name), unit_id=VALUES(unit_id);
