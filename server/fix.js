const mysql = require('mysql2/promise');
require('dotenv').config({path: './.env'});
(async () => {
  const pool = mysql.createPool({
    host: process.env.DB_HOST || 'localhost',
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD || '',
    database: process.env.DB_NAME || 'alerto_poz'
  });
  await pool.query("DELETE FROM users WHERE email = 'admin'");
  await pool.query("DELETE FROM users WHERE email = 'admin@pozorrubio.gov.ph'");
  
  // ensure the phone number is free
  await pool.query("DELETE FROM users WHERE phone = '09998887777'");
  
  await pool.query(`INSERT IGNORE INTO users (name, email, phone, password, type, active, barangay) VALUES ('MDRRMO Command Center', 'mdrrmo@pozorrubio.gov.ph', '09998887777', '$2a$10$uHA89lKJ9z2wwQmccanrtOO6i6SW.gi6YheTvcuRXETSyKQt9G0zm', 'mdrrmo_admin', 1, NULL)`);
  console.log('Done');
  process.exit(0);
})();
