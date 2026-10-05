const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET || 'alerto_poz_super_secret_key_123';

function generateToken(user) {
    return jwt.sign(
        { id: user.id, name: user.name, type: user.type, barangay: user.barangay },
        JWT_SECRET,
        { expiresIn: '24h' }
    );
}

function verifyAdmin(allowedRoles = []) {
    return (req, res, next) => {
        const authHeader = req.headers['authorization'];
        const token = authHeader && authHeader.split(' ')[1];
        
        if (!token) return res.status(401).json({ error: "Access denied. No token provided." });

        jwt.verify(token, JWT_SECRET, (err, decoded) => {
            if (err) return res.status(403).json({ error: "Invalid or expired token." });
            
            if (allowedRoles.length > 0 && !allowedRoles.includes(decoded.type)) {
                return res.status(403).json({ error: "Access denied. Insufficient permissions." });
            }
            
            // Add user info to request
            req.admin = decoded;
            next();
        });
    };
}

module.exports = { generateToken, verifyAdmin, JWT_SECRET };
