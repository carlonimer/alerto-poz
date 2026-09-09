const mysql = require('mysql2/promise');
async function run() {
    const pool = mysql.createPool({host:'127.0.0.1', user:'root', password:'', database:'alerto_poz'});
    try {
        await pool.query("UPDATE responders SET status='available'");
        console.log("Responders reset to available successfully.");
    } catch (e) {
        console.error(e.message);
    }
    process.exit();
}
run();
