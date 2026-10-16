const fs = require('fs');
const path = require('path');

// Load authoritative PSGC Pozorrubio barangays boundary data
let barangaysData = [];
try {
    const dataPath = path.join(__dirname, '..', 'data', 'pozorrubio_barangays.json');
    barangaysData = JSON.parse(fs.readFileSync(dataPath, 'utf8'));
} catch (e) {
    console.error('[BarangayService] Failed to load pozorrubio_barangays.json:', e.message);
}

// Pozorrubio Geofence Box
const POZORRUBIO_BBOX = {
    minLat: 16.0500,
    maxLat: 16.1800,
    minLng: 120.4800,
    maxLng: 120.6100
};

/**
 * Standard ray-casting point-in-polygon algorithm.
 * @param {Array<number>} pt [lng, lat]
 * @param {Array<Array<number>>} vs Array of [lng, lat] polygon vertices
 * @returns {boolean} true if pt is strictly inside or on edge of polygon
 */
function pointInPolygon(pt, vs) {
    const x = pt[0], y = pt[1];
    let inside = false;
    for (let i = 0, j = vs.length - 1; i < vs.length; j = i++) {
        const xi = vs[i][0], yi = vs[i][1];
        const xj = vs[j][0], yj = vs[j][1];
        const intersect = ((yi > y) !== (yj > y)) &&
            (x < (xj - xi) * (y - yi) / (yj - yi) + xi);
        if (intersect) inside = !inside;
    }
    return inside;
}

/**
 * Distance in meters between two lat/lng coordinates (Haversine formula).
 */
function haversineDistance(lat1, lon1, lat2, lon2) {
    const R = 6371e3; // meters
    const phi1 = lat1 * Math.PI / 180;
    const phi2 = lat2 * Math.PI / 180;
    const deltaPhi = (lat2 - lat1) * Math.PI / 180;
    const deltaLambda = (lon2 - lon1) * Math.PI / 180;

    const a = Math.sin(deltaPhi / 2) * Math.sin(deltaPhi / 2) +
              Math.cos(phi1) * Math.cos(phi2) *
              Math.sin(deltaLambda / 2) * Math.sin(deltaLambda / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
}

/**
 * Authoritatively detect the Barangay in Pozorrubio from GPS coordinates.
 * @param {number} lat Latitude
 * @param {number} lng Longitude
 * @returns {Object|null} { name, center, distanceMeters }
 */
function findPozorrubioBarangay(lat, lng) {
    if (typeof lat !== 'number' || typeof lng !== 'number' || isNaN(lat) || isNaN(lng)) {
        return null;
    }

    const pt = [lng, lat];

    // 1. Exact Polygon Point-in-Polygon Check
    for (const b of barangaysData) {
        // Fast bounding box check
        const [minLat, minLng, maxLat, maxLng] = b.bbox;
        if (lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng) {
            if (pointInPolygon(pt, b.polygon)) {
                return {
                    name: b.name,
                    center: b.center,
                    matchType: 'exact_polygon'
                };
            }
        }
    }

    // 2. Tolerance check: If coordinates are within the broader Pozorrubio geofence,
    // find the nearest barangay centroid/boundary within 1200 meters (border buffer)
    if (lat >= POZORRUBIO_BBOX.minLat && lat <= POZORRUBIO_BBOX.maxLat &&
        lng >= POZORRUBIO_BBOX.minLng && lng <= POZORRUBIO_BBOX.maxLng) {
        let closest = null;
        let minDist = Infinity;

        for (const b of barangaysData) {
            const dist = haversineDistance(lat, lng, b.center[0], b.center[1]);
            if (dist < minDist) {
                minDist = dist;
                closest = b;
            }
        }

        if (closest && minDist <= 3000) { // Within 3km of a barangay center
            return {
                name: closest.name,
                center: closest.center,
                matchType: 'nearest_centroid_buffer',
                distanceMeters: Math.round(minDist)
            };
        }
    }

    return null;
}

/**
 * Resolve full administrative location with authoritative boundary enforcement.
 * @param {number} lat Latitude
 * @param {number} lng Longitude
 * @returns {Promise<Object>} Resolved location info
 */
async function resolveLocation(lat, lng) {
    console.log(`[BarangayService] Resolving GPS Coordinates: lat=${lat}, lng=${lng}`);

    // Check authoritative Pozorrubio boundaries first
    const pozMatch = findPozorrubioBarangay(lat, lng);

    if (pozMatch) {
        const barangay = pozMatch.name;
        const municipality = "Pozorrubio";
        const province = "Pangasinan";
        let street = null;

        // Optionally query Nominatim for road/amenity name only, but NEVER allow it to override the barangay
        try {
            const res = await fetch(`https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${lat}&lon=${lng}&zoom=18&addressdetails=1`, {
                headers: { 'User-Agent': 'AlertoPoz/1.0', 'Accept-Language': 'en' },
                signal: AbortSignal.timeout(3000)
            });
            if (res.ok) {
                const data = await res.json();
                street = data.address?.road || data.address?.pedestrian || data.address?.subdivision || null;
            }
        } catch (_) {
            // Non-critical, fallback to administrative string
        }

        const parts = [];
        if (street) parts.push(street);
        parts.push(barangay);
        parts.push(municipality);
        parts.push(province);

        const result = {
            success: true,
            lat,
            lng,
            barangay,
            municipality,
            province,
            street: street || null,
            formattedAddress: parts.join(', '),
            isWithinPozorrubio: true,
            matchType: pozMatch.matchType,
            source: 'authoritative_psgc'
        };

        console.log(`[BarangayService] Resolved to Authoritative Barangay: "${barangay}", Municipality: "${municipality}", Province: "${province}" (matchType: ${pozMatch.matchType})`);
        return result;
    }

    // Coordinates are outside Pozorrubio: Use external geocoder with strict hierarchy mapping
    console.log(`[BarangayService] Coordinates (${lat}, ${lng}) outside Pozorrubio, falling back to external geocoder`);
    try {
        const res = await fetch(`https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${lat}&lon=${lng}&zoom=18&addressdetails=1`, {
            headers: { 'User-Agent': 'AlertoPoz/1.0', 'Accept-Language': 'en' },
            signal: AbortSignal.timeout(6000)
        });

        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = await res.json();
        const addr = data.address || {};

        let barangay = addr.village || addr.suburb || addr.quarter || addr.hamlet || addr.neighbourhood || addr.city_district || "";
        if (barangay.toLowerCase().startsWith('barangay ')) {
            barangay = barangay.substring(9).trim();
        }

        const municipality = addr.town || addr.municipality || addr.city || addr.county || "";
        const province = addr.province || addr.state || addr.region || "";
        const street = addr.road || addr.pedestrian || null;

        const parts = [];
        if (barangay) parts.push(barangay);
        if (municipality) parts.push(municipality);
        if (province) parts.push(province);

        const result = {
            success: true,
            lat,
            lng,
            barangay: barangay || null,
            municipality: municipality || null,
            province: province || null,
            street: street || null,
            formattedAddress: parts.length > 0 ? parts.join(', ') : (data.display_name || "Unknown Location"),
            isWithinPozorrubio: false,
            source: 'external_nominatim'
        };

        console.log(`[BarangayService] Resolved via External Geocoder: Barangay: "${barangay}", Municipality: "${municipality}", Province: "${province}"`);
        return result;
    } catch (e) {
        console.error('[BarangayService] External reverse geocoding failed:', e.message);
        return {
            success: false,
            lat,
            lng,
            barangay: null,
            municipality: null,
            province: null,
            formattedAddress: "Unknown Location",
            isWithinPozorrubio: false,
            error: e.message
        };
    }
}

module.exports = {
    findPozorrubioBarangay,
    resolveLocation,
    POZORRUBIO_BBOX,
    barangaysData
};
