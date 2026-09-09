const SERVER_URL = window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1' 
    ? 'http://localhost:3000' 
    : 'https://alerto-poz.onrender.com';

class ResponderApp {
    constructor() {
        this.activeUser = JSON.parse(localStorage.getItem("alerto-responder-user")) || null;
        this.socket = null;
        this.map = null;
        this.marker = null;
        this.incidentMarker = null;
        this.routingLine = null;
        
        this.gps = { lat: 16.1114, lng: 120.5482 }; // Default POZ Plaza
        this.gpsWatcher = null;
        this.activeIncidentId = null;

        this.initDOM();
        this.bindEvents();
        
        if (this.activeUser) {
            this.transitionToDashboard();
        }
    }

    initDOM() {
        // Screens
        this.loginScreen = document.getElementById("login-screen");
        this.dashboardScreen = document.getElementById("dashboard-screen");

        // Login Form
        this.loginForm = document.getElementById("login-form");
        this.loginIdInput = document.getElementById("login-id");
        this.loginPassInput = document.getElementById("login-password");
        this.loginError = document.getElementById("login-error");

        // Header
        this.unitName = document.getElementById("unit-name");
        this.statusIndicator = document.getElementById("status-indicator");
        this.statusSelect = document.getElementById("unit-status-dropdown");
        this.btnLogout = document.getElementById("btn-logout");

        // Active Assignment
        this.assignmentCard = document.getElementById("active-assignment-card");
        this.idleState = document.getElementById("idle-state");
        this.incIdBadge = document.getElementById("incident-id-badge");
        this.incCategory = document.getElementById("incident-category");
        this.incLocation = document.getElementById("incident-location");
        this.incReporter = document.getElementById("incident-reporter");
        this.incPhone = document.getElementById("incident-phone");
        this.incDetails = document.getElementById("incident-details");
        
        // Actions
        this.btnEnRoute = document.getElementById("btn-status-enroute");
        this.btnOnScene = document.getElementById("btn-status-onscene");
        this.btnResolved = document.getElementById("btn-status-resolved");
    }

    bindEvents() {
        this.loginForm.addEventListener("submit", (e) => this.handleLogin(e));
        this.btnLogout.addEventListener("click", () => this.handleLogout());
        this.statusSelect.addEventListener("change", (e) => this.handleStatusChange(e.target.value));

        this.btnEnRoute.addEventListener("click", () => this.updateIncidentProgress("en_route"));
        this.btnOnScene.addEventListener("click", () => this.updateIncidentProgress("on_scene"));
        this.btnResolved.addEventListener("click", () => this.resolveIncident());
    }

    async handleLogin(e) {
        e.preventDefault();
        const loginId = this.loginIdInput.value.trim();
        const password = this.loginPassInput.value.trim();

        if (!loginId || !password) return;

        try {
            const res = await fetch(`${SERVER_URL}/api/auth/responder-login`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ loginId, password })
            });
            const data = await res.json();
            
            if (data.success) {
                this.activeUser = data.user;
                localStorage.setItem("alerto-responder-user", JSON.stringify(this.activeUser));
                this.transitionToDashboard();
            } else {
                this.loginError.textContent = data.error || "Login failed.";
                this.loginError.classList.remove("hidden");
            }
        } catch (error) {
            this.loginError.textContent = "Network error connecting to server.";
            this.loginError.classList.remove("hidden");
        }
    }

    handleLogout() {
        localStorage.removeItem("alerto-responder-user");
        this.activeUser = null;
        if (this.socket) {
            this.socket.disconnect();
            this.socket = null;
        }
        this.stopGPS();
        this.dashboardScreen.classList.remove("active");
        this.dashboardScreen.classList.add("hidden");
        this.loginScreen.classList.add("active");
        this.loginScreen.classList.remove("hidden");
    }

    transitionToDashboard() {
        this.loginScreen.classList.remove("active");
        this.loginScreen.classList.add("hidden");
        this.dashboardScreen.classList.remove("hidden");
        this.dashboardScreen.classList.add("active");

        this.unitName.textContent = this.activeUser.unit_details ? this.activeUser.unit_details.name : this.activeUser.name;
        this.statusSelect.value = "available";
        this.statusIndicator.className = "status-dot available";

        this.initMap();
        this.startGPS();
        this.connectSocket();
    }

    connectSocket() {
        if (this.socket) return;
        
        this.socket = io(SERVER_URL);
        
        this.socket.on('connect', () => {
            console.log("Connected to Command Center.");
        });

        this.socket.on('init-state', (state) => {
            this.checkActiveAssignments(state.incidents);
        });

        this.socket.on('incident-updated', (incident) => {
            if (this.activeIncidentId === incident.id) {
                this.renderAssignment(incident);
            } else if (incident.assignedUnit === this.activeUser.unit_id && incident.status !== 'resolved' && incident.status !== 'cancelled') {
                this.checkActiveAssignments([incident]);
            }
        });
    }

    checkActiveAssignments(incidents) {
        // Find if any active incident is assigned to this unit
        const active = incidents.find(i => 
            i.assignedUnit === this.activeUser.unit_id && 
            (i.status === 'dispatching' || i.status === 'en_route' || i.status === 'on_scene')
        );

        if (active) {
            this.renderAssignment(active);
        } else {
            this.clearAssignment();
        }
    }

    renderAssignment(incident) {
        this.activeIncidentId = incident.id;
        this.idleState.classList.add("hidden");
        this.assignmentCard.classList.remove("hidden");

        this.incIdBadge.textContent = incident.id;
        this.incCategory.textContent = incident.category.toUpperCase();
        this.incLocation.textContent = `${incident.lat.toFixed(5)}, ${incident.lng.toFixed(5)}`;
        this.incReporter.textContent = incident.reporter;
        this.incPhone.textContent = incident.reporterPhone;
        this.incDetails.textContent = incident.details;

        // Reset buttons
        this.btnEnRoute.style.opacity = "1";
        this.btnOnScene.style.opacity = "1";

        if (incident.responseProgress === "en_route") {
            this.btnEnRoute.style.opacity = "0.5";
        } else if (incident.responseProgress === "on_scene") {
            this.btnEnRoute.style.opacity = "0.5";
            this.btnOnScene.style.opacity = "0.5";
        }

        // Plot incident on map
        if (this.map && incident.lat && incident.lng) {
            if (this.incidentMarker) {
                this.incidentMarker.setLatLng([incident.lat, incident.lng]);
            } else {
                this.incidentMarker = L.marker([incident.lat, incident.lng], {
                    icon: L.divIcon({
                        className: 'incident-marker',
                        html: '<div style="background-color:#ef4444; border:2px solid #fff; border-radius:50%; width:16px; height:16px; box-shadow:0 0 10px rgba(239,68,68,0.8);"></div>',
                        iconSize: [16, 16]
                    })
                }).addTo(this.map);
            }

            // Fit bounds to show both responder and incident
            const bounds = L.latLngBounds([this.gps, [incident.lat, incident.lng]]);
            this.map.fitBounds(bounds, { padding: [30, 30] });
        }
    }

    clearAssignment() {
        this.activeIncidentId = null;
        this.assignmentCard.classList.add("hidden");
        this.idleState.classList.remove("hidden");
        if (this.incidentMarker) {
            this.map.removeLayer(this.incidentMarker);
            this.incidentMarker = null;
        }
        if (this.map) {
            this.map.setView([this.gps.lat, this.gps.lng], 16);
        }
    }

    async updateIncidentProgress(progress) {
        if (!this.activeIncidentId) return;
        try {
            await fetch(`${SERVER_URL}/api/incidents/${this.activeIncidentId}`, {
                method: "PUT",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ status: progress === "on_scene" ? "on_scene" : "dispatching", responseProgress: progress })
            });
        } catch (e) {
            console.error(e);
        }
    }

    async resolveIncident() {
        if (!this.activeIncidentId) return;
        try {
            await fetch(`${SERVER_URL}/api/incidents/${this.activeIncidentId}`, {
                method: "PUT",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ status: "resolved", resolutionDate: Date.now() })
            });
            this.clearAssignment();
        } catch (e) {
            console.error(e);
        }
    }

    handleStatusChange(status) {
        if (status === "available") {
            this.statusIndicator.className = "status-dot available";
        } else {
            this.statusIndicator.className = "status-dot busy";
        }
        // In a full implementation, you would emit this status change to the server
    }

    initMap() {
        if (this.map) return;
        this.map = L.map('responder-map', { zoomControl: false }).setView([this.gps.lat, this.gps.lng], 16);
        L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png').addTo(this.map);

        this.marker = L.marker([this.gps.lat, this.gps.lng], {
            icon: L.divIcon({
                className: 'responder-marker',
                html: '<div style="background-color:#3b82f6; border:3px solid #fff; border-radius:50%; width:18px; height:18px; box-shadow:0 0 10px rgba(59,130,246,0.8);"></div>',
                iconSize: [18, 18]
            })
        }).addTo(this.map);
    }

    startGPS() {
        if (!navigator.geolocation) {
            alert("Geolocation is not supported by your browser.");
            return;
        }

        this.gpsWatcher = navigator.geolocation.watchPosition(
            (pos) => {
                this.gps.lat = pos.coords.latitude;
                this.gps.lng = pos.coords.longitude;

                if (this.marker) {
                    this.marker.setLatLng([this.gps.lat, this.gps.lng]);
                }
                if (!this.activeIncidentId && this.map) {
                    this.map.panTo([this.gps.lat, this.gps.lng]);
                }

                // Broadcast live location to server
                if (this.socket && this.socket.connected && this.activeUser.unit_id) {
                    this.socket.emit("responder-gps-update", {
                        id: this.activeUser.unit_id,
                        lat: this.gps.lat,
                        lng: this.gps.lng
                    });
                }
            },
            (err) => {
                console.warn("GPS tracking error: ", err);
            },
            { enableHighAccuracy: true, maximumAge: 10000, timeout: 5000 }
        );
    }

    stopGPS() {
        if (this.gpsWatcher) {
            navigator.geolocation.clearWatch(this.gpsWatcher);
            this.gpsWatcher = null;
        }
    }
}

// Initialize on DOM Load
document.addEventListener("DOMContentLoaded", () => {
    window.App = new ResponderApp();
});
