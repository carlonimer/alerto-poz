/* ==========================================================================
   ALERTO-POZ DESKTOP DASHBOARD CLIENT ENGINE
   ========================================================================== */

const POZORRUBIO_PLAZA = { lat: 16.1114, lng: 120.5482 };

// Stationary landmarks in Pozorrubio
const LANDMARKS = [
    { name: "Pozorrubio Community Hospital", type: "medical", lat: 16.1086, lng: 120.5424 },
    { name: "Rural Health Unit I (RHU I)", type: "medical", lat: 16.1110, lng: 120.5490 },
    { name: "Pozorrubio Police Station (PNP)", type: "police", lat: 16.1115, lng: 120.5484 },
    { name: "Pozorrubio Fire Station (BFP)", type: "fire", lat: 16.1118, lng: 120.5487 }
];

class CommandDashboard {
    constructor(user) {
        this.user = user;
        this.socket = null;
        
        // Hydrated states from server
        this.incidents = [];
        this.responders = [];
        this.broadcasts = [];
        this.rescue_vehicles = [];
        this.water_devices = [];
        
        this.selectedIncident = null;
        
        // Maps references
        this.map = null;
        this.incidentMarkers = {};
        this.responderMarkers = {};
        
        this.initDOM();
        
        this.initSocket();
    }

    initDOM() {
        // Tab buttons toggles
        this.tabBtns = document.querySelectorAll(".sidebar-nav .nav-btn");
        this.panes = document.querySelectorAll(".dashboard-viewport .tab-pane");
        
        this.tabBtns.forEach(btn => {
            btn.addEventListener("click", (e) => {
                const tabId = btn.getAttribute("data-tab");
                this.tabBtns.forEach(b => b.classList.remove("active"));
                btn.classList.add("active");
                
                this.panes.forEach(pane => {
                    pane.classList.remove("active");
                    if (pane.id === `pane-${tabId}`) {
                        pane.classList.add("active");
                    }
                });
                
                if (tabId === 'map' && this.map) {
                    setTimeout(() => this.map.invalidateSize(), 100);
                    // If user manually clicked the Command Map tab, show all markers and clear selection
                    if (e && e.isTrusted) {
                        this.selectedIncident = null;
                        const detailsBox = document.getElementById("incident-details-box");
                        if (detailsBox) {
                            detailsBox.innerHTML = `
                                <div class="text-center text-muted" style="margin-top: 40px; font-style: italic;">
                                    Select an incident from Active Logs to manage.
                                </div>
                            `;
                        }
                        
                        // Restore only 'new' (Pending) markers and set their icons to default
                        Object.entries(this.incidentMarkers).forEach(([id, m]) => {
                            const incident = this.incidents.find(i => i.id === id);
                            if (incident && (incident.status === 'pending' || incident.status === 'new')) {
                                if (!this.map.hasLayer(m)) {
                                    m.addTo(this.map);
                                }
                                const defaultIcon = L.divIcon({
                                    className: 'incident-pin',
                                    html: '<div style="color: #ef4444; font-size: 32px; text-shadow: 0 3px 5px rgba(0,0,0,0.5); text-align: center;"><i class="fa-solid fa-location-dot"></i></div>',
                                    iconAnchor: [11, 32],
                                    popupAnchor: [0, -32]
                                });
                                m.setIcon(defaultIcon);
                            } else {
                                if (this.map.hasLayer(m)) {
                                    this.map.removeLayer(m);
                                }
                            }
                        });
                    }
                }
                
                if (tabId === 'logs') {
                    const badge = document.getElementById("unread-count");
                    badge.classList.add("hidden");
                    badge.textContent = "0";
                }
                
                if (tabId === 'feedbacks') {
                    this.loadFeedbacks();
                }

                if (tabId === 'id_verifications') {
                    this.loadIdVerifications();
                }

                if (tabId === 'weather_control') {
                    this.loadWeatherStatus();
                    this.loadWeatherHistory();
                }
            });
        });

        // Weather Status Control bindings
        const btnRefreshWeather = document.getElementById("btn-refresh-weather");
        if (btnRefreshWeather) {
            btnRefreshWeather.addEventListener("click", () => {
                this.loadWeatherStatus();
                this.loadWeatherHistory();
            });
        }
        const btnRefreshWeatherHist = document.getElementById("btn-refresh-weather-history");
        if (btnRefreshWeatherHist) {
            btnRefreshWeatherHist.addEventListener("click", () => this.loadWeatherHistory());
        }
        const headerWeatherBadge = document.getElementById("header-weather-badge");
        if (headerWeatherBadge) {
            headerWeatherBadge.addEventListener("click", () => {
                const btnNav = document.getElementById("nav-btn-weather-control");
                if (btnNav) btnNav.click();
            });
        }
        window.dashPromptWeatherChange = (status) => this.promptWeatherChange(status);

        // ID Verification filters & bindings
        const idFilter = document.getElementById("id-verif-status-filter");
        if (idFilter) {
            idFilter.addEventListener("change", () => this.loadIdVerifications());
        }
        const btnRefreshId = document.getElementById("btn-refresh-id-verifs");
        if (btnRefreshId) {
            btnRefreshId.addEventListener("click", () => this.loadIdVerifications());
        }
        window.dashOpenIdReview = (userId) => this.openIdReviewModal(userId);
        window.dashQuickApproveId = (userId) => this.submitIdReview(userId, 'approve');
        window.dashQuickRejectId = (userId) => this.promptRejectId(userId);

        // Dispatch console
        this.statusSelector = document.getElementById("incident-status-selector");
        this.unitSelector = document.getElementById("responder-unit-selector");
        this.vehicleSelector = document.getElementById("vehicle-selector");
        this.dispatchBtn = document.getElementById("dispatch-submit");
        this.dispatchBtn.addEventListener("click", () => this.handleDispatch());

        // Broadcast forms
        this.broadcastForm = document.getElementById("compose-broadcast-form");
        this.broadcastForm.addEventListener("submit", (e) => {
            e.preventDefault();
            this.handleSendBroadcast();
        });

        // Barangay Assistance form
        const brgyAssistForm = document.getElementById("brgy-assist-form");
        if (brgyAssistForm) {
            brgyAssistForm.addEventListener("submit", async (e) => {
                e.preventDefault();
                await this.handleBarangayAssist();
            });
        }

        // Call overlays Accept/Decline button bindings
        document.getElementById("btn-accept-dash-call").addEventListener("click", () => this.acceptCall());
        document.getElementById("btn-decline-dash-call").addEventListener("click", () => this.declineCall());
        
        // Dispatcher Comms Bindings
        this.adminChatInput = document.getElementById("admin-chat-input");
        document.getElementById("btn-admin-send").addEventListener("click", () => this.sendDispatcherChat());
        this.adminChatInput.addEventListener("keypress", (e) => {
            if (e.key === "Enter") this.sendDispatcherChat();
        });
        document.getElementById("btn-admin-call").addEventListener("click", () => this.initiateCall('audio'));
        document.getElementById("btn-admin-video").addEventListener("click", () => this.initiateCall('video'));
        const btnAdminAttach = document.getElementById("btn-admin-attach");
        const adminChatFile = document.getElementById("admin-chat-file");
        btnAdminAttach.addEventListener("click", () => {
            adminChatFile.removeAttribute("capture");
            adminChatFile.click();
        });

        const btnAdminCamera = document.getElementById("btn-admin-camera");
        if (btnAdminCamera) {
            btnAdminCamera.addEventListener("click", () => {
                if (typeof openWebcamUI !== 'undefined') {
                    const opened = openWebcamUI((file) => {
                        const dataTransfer = new DataTransfer();
                        dataTransfer.items.add(file);
                        adminChatFile.files = dataTransfer.files;
                        adminChatFile.dispatchEvent(new Event('change'));
                    });
                    if (!opened) {
                        adminChatFile.setAttribute("capture", "environment");
                        adminChatFile.click();
                    }
                } else {
                    adminChatFile.setAttribute("capture", "environment");
                    adminChatFile.click();
                }
            });
        }
        
        const btnBrgyAssist = document.getElementById("btn-brgy-assist");
        if (btnBrgyAssist) {
            btnBrgyAssist.addEventListener("click", async () => {
                const confirmed = confirm("Are you sure you want to request emergency assistance from MDRRMO?");
                if (!confirmed) return;
                
                try {
                    const res = await fetch("/api/iot/barangay-assist", {
                        method: "POST",
                        headers: { "Content-Type": "application/json" },
                        body: JSON.stringify({
                            barangay: this.user.barangay,
                            lat: 16.1114,
                            lng: 120.5482
                        })
                    });
                    const data = await res.json();
                    if (data.success) {
                        alert("MDRRMO has been alerted and assistance has been requested.");
                    } else {
                        alert("Failed to request assistance: " + data.error);
                    }
                } catch(e) {
                    alert("Network error.");
                }
            });
        }
        
        const btnMaximizeChat = document.getElementById("btn-maximize-chat");
        if (btnMaximizeChat) {
            btnMaximizeChat.addEventListener("click", (e) => {
                e.preventDefault();
                const container = document.getElementById("dispatcher-chat-container");
                const icon = btnMaximizeChat.querySelector("i");
                const mapGrid = document.querySelector(".map-layout-grid");
                const chatCard = document.querySelector(".sidebar-card.chat-card");
                
                if (mapGrid.classList.contains("chat-workspace-mode")) {
                    // Minimize
                    mapGrid.classList.remove("chat-workspace-mode");
                    chatCard.appendChild(container);
                    icon.classList.remove("fa-compress");
                    icon.classList.add("fa-expand");
                    
                    if (this.map) {
                        setTimeout(() => this.map.invalidateSize(), 300);
                    }
                } else {
                    // Maximize
                    mapGrid.classList.add("chat-workspace-mode");
                    const mapPanel = document.querySelector(".map-panel");
                    mapGrid.insertBefore(container, mapPanel);
                    icon.classList.remove("fa-expand");
                    icon.classList.add("fa-compress");
                }
                
                // Scroll to bottom of chat
                const feed = document.getElementById('dispatcher-chat-feed');
                if(feed) feed.scrollTop = feed.scrollHeight;
            });
        }
        
        const handleAdminFileUpload = async (e) => {
            const file = e.target.files[0];
            if (!file || !this.selectedIncident) return;
            
            const attachBtn = document.getElementById("btn-admin-attach");
            const cameraBtn = document.getElementById("btn-admin-camera");
            if (attachBtn) attachBtn.disabled = true;
            if (cameraBtn) cameraBtn.disabled = true;

            const isVideo = file.type.startsWith("video/") || file.name.match(/\.(mp4|webm|mov|3gp|mkv|avi)$/i);
            const type = isVideo ? "video" : "image";
            const clientMessageId = 'admin-media-' + Date.now() + '-' + Math.random().toString(36).substring(2, 9);
            const fd = new FormData();
            const senderId = this.user ? (this.user.username || this.user.id || 'ADMIN') : 'ADMIN';
            const senderRole = this.user && this.user.type === 'barangay_admin' ? `Barangay ${this.user.barangay || 'Official'}` : 'Command Center';
            fd.append('senderId', senderId);
            fd.append('senderRole', senderRole);
            fd.append('messageType', type);
            fd.append('clientMessageId', clientMessageId);
            fd.append('media', file);
            
            try {
                const token = localStorage.getItem("alerto_admin_token");
                const headers = {};
                if (token) headers['Authorization'] = `Bearer ${token}`;
                const res = await fetch(`/api/incidents/${this.selectedIncident.id}/messages`, {
                    method: "POST",
                    headers,
                    body: fd
                });
                if (!res.ok) {
                    const errData = await res.json().catch(() => ({}));
                    throw new Error(errData.error || `Upload failed with status ${res.status}`);
                }
            } catch (err) {
                console.error("Media upload error:", err);
                alert("Failed to upload attachment: " + (err.message || "Network error. Please try again."));
            } finally {
                if (attachBtn) attachBtn.disabled = false;
                if (cameraBtn) cameraBtn.disabled = false;
                e.target.value = "";
            }
        };

        document.getElementById("admin-chat-file").addEventListener("change", handleAdminFileUpload);

        // Responder Management Bindings
        window.dashCloseResponderModal = () => {
            document.getElementById("responder-modal").classList.add("hidden");
            document.body.style.overflow = "";
        };

        document.getElementById("btn-add-responder").addEventListener("click", () => {
            document.getElementById("responder-form").reset();
            document.getElementById("resp-id").value = "";
            document.getElementById("resp-modal-title").textContent = "Add Responder";
            document.getElementById("responder-modal").classList.remove("hidden");
            document.body.style.overflow = "hidden";
        });
        
        document.getElementById("responder-form").addEventListener("submit", (e) => {
            e.preventDefault();
            this.handleSaveResponder();
        });

        // Responder Filters
        document.getElementById("resp-search").addEventListener("input", () => this.renderRespondersGrid());
        document.getElementById("resp-filter-type").addEventListener("change", () => this.renderRespondersGrid());
        document.getElementById("resp-filter-status").addEventListener("change", () => this.renderRespondersGrid());

        window.dashEditResponder = (id) => this.editResponder(id);
        window.dashDeleteResponder = (id) => this.deleteResponder(id);

        // History View Bindings
        this.histSearch = document.getElementById("hist-search");
        this.histStatusFilter = document.getElementById("hist-status-filter");
        this.histTypeFilter = document.getElementById("hist-type-filter");
        this.histDateFilter = document.getElementById("hist-date-filter");
        this.btnHistClear = document.getElementById("btn-hist-clear");
        this.historyTableBody = document.getElementById("history-table-body");
        
        this.histTotal = document.getElementById("hist-total");
        this.histPending = document.getElementById("hist-pending");
        this.histResolved = document.getElementById("hist-resolved");
        this.histCancelled = document.getElementById("hist-cancelled");

        if (this.histSearch) {
            this.histSearch.addEventListener("input", () => this.renderHistoryRecords());
            this.histStatusFilter.addEventListener("change", () => this.renderHistoryRecords());
            this.histTypeFilter.addEventListener("change", () => this.renderHistoryRecords());
            this.histDateFilter.addEventListener("change", () => this.renderHistoryRecords());
            this.btnHistClear.addEventListener("click", () => {
                this.histSearch.value = "";
                this.histStatusFilter.value = "all";
                this.histTypeFilter.value = "all";
                this.histDateFilter.value = "";
                this.renderHistoryRecords();
            });
        }
        
        window.dashViewHistoryDetails = (id) => this.viewHistoryDetails(id);
        window.dashViewMapLocation = (lat, lng, id) => this.viewMapLocation(lat, lng, id);
        window.dashAcknowledgeIncident = (id) => this.acknowledgeIncident(id);

        if (this.user && this.user.type === 'barangay_admin') {
            this.setupBarangayAccountUI();
        }

        // Auto-refresh analytics every 10 seconds
        setInterval(() => this.updateAnalytics(), 10000);
    }

    setupBarangayAccountUI() {
        const logsTabSpan = document.querySelector(".nav-btn[data-tab='logs'] span:not(.badge-count)");
        if (logsTabSpan) logsTabSpan.textContent = "Emergency Reports";
        const logsHeading = document.querySelector("#pane-logs h3");
        if (logsHeading && this.user && this.user.barangay) {
            logsHeading.textContent = `Barangay ${this.user.barangay} Emergency Reports`;
        }
        const statusFilter = document.getElementById("logs-filter-status");
        if (statusFilter && !statusFilter.querySelector("option[value='acknowledged']")) {
            const ackOpt = document.createElement("option");
            ackOpt.value = "acknowledged";
            ackOpt.textContent = "Acknowledged";
            const pendingOpt = statusFilter.querySelector("option[value='pending']");
            if (pendingOpt && pendingOpt.nextSibling) {
                statusFilter.insertBefore(ackOpt, pendingOpt.nextSibling);
            } else {
                statusFilter.appendChild(ackOpt);
            }
        }
    }

    filterIncidents(incidentsList) {
        if (!this.user || !this.user.type) return incidentsList;
        const role = this.user.type; // bfp_admin, pnp_admin, mdrrmo_admin, barangay_admin
        const normalizeBrgy = (val) => String(val || '').trim().replace(/^(barangay|brgy\.?)\s+/i, '').trim().toLowerCase();
        const brgy = normalizeBrgy(this.user.barangay);

        return incidentsList.filter(inc => {
            // Map legacy null assigned_agency based on category
            let agency = inc.assigned_agency;
            const cat = (inc.category || '').toLowerCase();
            if (!agency) {
                if (cat === 'fire') agency = 'BFP';
                else if (cat === 'crime' || cat === 'police') agency = 'PNP';
                else if (cat === 'barangay') agency = 'Barangay';
                else agency = 'MDRRMO';
            }

            if (role === 'bfp_admin') return agency === 'BFP';
            if (role === 'pnp_admin') return agency === 'PNP';
            if (role === 'barangay_admin') {
                const incBrgy = normalizeBrgy(inc.barangay);
                return (agency === 'Barangay' || cat === 'barangay') && Boolean(incBrgy) && incBrgy === brgy;
            }
            if (role === 'mdrrmo_admin') return agency === 'MDRRMO' || agency === 'Barangay';
            
            return true;
        });
    }

    initSocket() {
        // Handle VS Code Live Server testing ports
        const socketUrl = (window.location.port === '5500' || window.location.port === '5501') 
            ? 'https://alerto-poz.onrender.com' 
            : '';
        this.socket = io(socketUrl);
        
        this.socket.on('connect', () => {
            this.updateNetworkUI(true);
        });
        
        this.socket.on('disconnect', () => {
            this.updateNetworkUI(false);
        });

        // Load initial state database from backend server
        this.socket.on('init-state', async (db) => {
            // Fetch strictly authorized incidents via API instead of public broadcast
            await this.fetchAdminIncidents();

            this.responders = db.responders;
            this.broadcasts = db.broadcasts;
            this.rescue_vehicles = db.rescue_vehicles || [];
            this.water_devices = db.water_devices || [];
            
            this.renderAll();
        });

        // Live report event
        this.socket.on('new-incident-alert', (report) => {
            // Check if user is allowed to see this
            const filtered = this.filterIncidents([report]);
            if (filtered.length === 0) return;

            // Prevent duplicates
            const existingIdx = this.incidents.findIndex(i => i.id === report.id);
            if (existingIdx !== -1) {
                this.incidents[existingIdx] = report;
            } else {
                this.incidents.unshift(report);
            }
            
            // Notification sound
            
            // Notification sound
            this.playAlertSound();
            
            // Log unread badge increment
            const logTab = document.querySelector("[data-tab='logs']");
            if (!logTab.classList.contains("active")) {
                const badge = document.getElementById("unread-count");
                let count = parseInt(badge.textContent) + 1;
                badge.textContent = count;
                badge.classList.remove("hidden");
            }
            
            // Map markers adding
            this.plotIncidentMarker(report);
            
            this.renderLogsTable();
            this.renderHistoryRecords();
            this.updateAnalytics();
        });

        this.socket.on('chat-message-receive', (msg) => {
            if (this.selectedIncident && String(this.selectedIncident.id) === String(msg.incident_id)) {
                if (!this.seenMessageIds) this.seenMessageIds = new Set();
                const idKey = msg.id ? String(msg.id) : null;
                const clientKey = msg.client_message_id ? String(msg.client_message_id) : null;
                if (idKey && this.seenMessageIds.has(idKey)) return;
                if (clientKey && this.seenMessageIds.has(clientKey)) return;
                if (idKey) this.seenMessageIds.add(idKey);
                if (clientKey) this.seenMessageIds.add(clientKey);

                const feed = document.getElementById("dispatcher-chat-feed");
                if (feed) {
                    feed.insertAdjacentHTML('beforeend', this.buildMessageHtml(msg));
                    feed.scrollTo({ top: feed.scrollHeight, behavior: 'smooth' });
                }
            }
        });

        // State changes forwarded from other clients
        this.socket.on('incident-deleted', (data) => {
            const index = this.incidents.findIndex(i => i.id === data.id);
            if (index > -1) {
                this.incidents.splice(index, 1);
                this.renderLogsTable();
                this.renderHistoryRecords();
                this.updateAnalytics();
            }
        });

        this.socket.on('incident-updated', (incident) => {
            const filtered = this.filterIncidents([incident]);
            const idx = this.incidents.findIndex(i => i.id === incident.id);

            if (filtered.length === 0) {
                // If it was assigned to us before but now isn't, remove it.
                if (idx !== -1) {
                    this.incidents.splice(idx, 1);
                    this.renderLogsTable();
                    this.renderHistoryRecords();
                    this.updateAnalytics();
                    // Also clear markers if any
                    if (this.gpsStreams && this.gpsStreams[incident.id]) {
                        clearInterval(this.gpsStreams[incident.id]);
                        delete this.gpsStreams[incident.id];
                    }
                    if (this.incidentMarkers && this.incidentMarkers[incident.id]) {
                        this.map.removeLayer(this.incidentMarkers[incident.id]);
                        delete this.incidentMarkers[incident.id];
                    }
                }
                return;
            }

            if (idx !== -1) {
                this.incidents[idx] = incident;
            } else {
                // It's newly assigned to this agency (e.g., draft activated with a new category)
                this.incidents.unshift(incident);
                // Also plot the marker since it wasn't there before
                this.plotIncidentMarker(incident);
                if (this.user && this.user.type === 'barangay_admin') {
                    this.playAlertSound();
                    const logTab = document.querySelector("[data-tab='logs']");
                    if (logTab && !logTab.classList.contains("active")) {
                        const badge = document.getElementById("unread-count");
                        if (badge) {
                            let count = (parseInt(badge.textContent) || 0) + 1;
                            badge.textContent = count;
                            badge.classList.remove("hidden");
                        }
                    }
                }
            }

            this.renderLogsTable();
            this.renderHistoryRecords();
            this.updateAnalytics();
                
                // Update marker color if enroute/resolved
                if (incident.status === 'resolved' || incident.status === 'cancelled' || incident.status === 'closed') {
                    if (this.gpsStreams && this.gpsStreams[incident.id]) {
                        clearInterval(this.gpsStreams[incident.id]);
                        delete this.gpsStreams[incident.id];
                    }
                    if (this.incidentMarkers[incident.id]) {
                        this.map.removeLayer(this.incidentMarkers[incident.id]);
                        delete this.incidentMarkers[incident.id];
                    }
                    if (this.selectedIncident && this.selectedIncident.id === incident.id) {
                        this.selectedIncident = null;
                        if (incident.status === 'cancelled') {
                            document.getElementById("incident-details-box").innerHTML = `
                                <p style="color:var(--danger); text-align:center;"><i class="fa-solid fa-ban"></i> Incident ${incident.id} Cancelled</p>
                            `;
                        } else {
                            document.getElementById("incident-details-box").innerHTML = `
                                <p style="color:var(--success); text-align:center;"><i class="fa-solid fa-circle-check"></i> Incident ${incident.id} Resolved</p>
                            `;
                        }
                    }
                } else {
                    const marker = this.incidentMarkers[incident.id];
                    if (marker) {
                        if (this.selectedIncident) {
                            if (this.selectedIncident.id !== incident.id) {
                                if (this.map.hasLayer(marker)) this.map.removeLayer(marker);
                            } else {
                                if (!this.map.hasLayer(marker)) marker.addTo(this.map);
                            }
                        } else {
                            const isBrgyActive = this.user && this.user.type === 'barangay_admin' && ['pending', 'new', 'acknowledged', 'dispatching'].includes((incident.status || '').toLowerCase());
                            if (incident.status === 'pending' || incident.status === 'new' || isBrgyActive) {
                                if (!this.map.hasLayer(marker)) marker.addTo(this.map);
                            } else {
                                if (this.map.hasLayer(marker)) this.map.removeLayer(marker);
                            }
                        }

                        if (incident.status === 'enroute') {
                            const enrouteIcon = L.divIcon({
                                className: 'incident-gps-marker pulse-marker-warning',
                                html: '<div style="background-color:#f59e0b; border:2px solid #fff; border-radius:50%; width:20px; height:20px; box-shadow:0 0 10px rgba(245,158,11,0.8);"></div>'
                            });
                            marker.setIcon(enrouteIcon);
                        } else if (incident.status === 'pending' || incident.status === 'new') {
                            const defaultIcon = L.divIcon({
                                className: 'incident-pin',
                                html: '<div style="color: #ef4444; font-size: 32px; text-shadow: 0 3px 5px rgba(0,0,0,0.5); text-align: center;"><i class="fa-solid fa-location-dot"></i></div>',
                                iconAnchor: [11, 32],
                                popupAnchor: [0, -32]
                            });
                            marker.setIcon(defaultIcon);
                        }
                    }
                }
                
                // Chat & details auto-update
                if (this.selectedIncident && this.selectedIncident.id === incident.id && incident.status !== 'resolved' && incident.status !== 'closed') {
                    this.selectedIncident = incident;
                    if (this.user && this.user.type === 'barangay_admin') {
                        this.selectIncidentForDispatch(incident.id);
                    } else {
                        this.renderDispatcherChat(incident);
                    }
                }
        });

        this.socket.on('barangay-assistance-request', (req) => {
            if (this.user.type === 'mdrrmo_admin') {
                if (!this.assistanceRequests) this.assistanceRequests = [];
                this.assistanceRequests.unshift(req);
                this.renderAssistanceRequests();
                
                // Show a quick browser notification/alert
                const navBtn = document.getElementById("nav-btn-assistance-reqs");
                if (navBtn) {
                    navBtn.style.animation = "pulse 1s infinite alternate";
                    setTimeout(() => { navBtn.style.animation = ""; }, 5000);
                }
            }
        });

        this.socket.on('responder-updated', (responder) => {
            const idx = this.responders.findIndex(r => r.id === responder.id);
            if (idx !== -1) {
                this.responders[idx] = responder;
                this.renderRespondersGrid();
                this.updateUnitDropdown();
                if (this.map) {
                    this.updateRespondersOnMap();
                }
            }
        });

        // Listen for live responder GPS tracks animation updates
        this.socket.on('responder-gps-changed', (data) => {
            const { id, lat, lng } = data;
            const r = this.responders.find(res => res.id === id);
            if (r) {
                r.lat = lat;
                r.lng = lng;
            }
            if (this.responderMarkers[id]) {
                this.responderMarkers[id].setLatLng([lat, lng]);
            }
        });

        // Listen for incoming voice/video calls
        this.socket.on('call-status-updated', (data) => {
            this.handleCallStatusUpdate(data);
        });

        // Listen for check-in coordinates mapping
        this.socket.on('new-checkin-received', (data) => {
            this.handleNewCheckin(data);
        });

        // Listen for citizen ID verification submissions & status updates
        this.socket.on('id-verification-updated', () => {
            this.updatePendingIdCount();
            const activeTab = document.querySelector(".sidebar-nav .nav-btn.active");
            if (activeTab && activeTab.getAttribute("data-tab") === "id_verifications") {
                this.loadIdVerifications();
            }
        });

        // Listen for global weather status updates
        this.socket.on('weather-status-updated', (data) => {
            this.handleWeatherUpdate(data);
        });

        // Initial fetch of pending ID verifications count
        this.updatePendingIdCount();

        // Initial fetch of current weather status
        this.loadWeatherStatus();
    }

    updateNetworkUI(connected) {
        const badge = document.getElementById("server-connection-badge");
        if (connected) {
            badge.className = "status-pill active";
            badge.innerHTML = `<span class="ping-wave"></span><span class="ping-core"></span> WebSocket Active`;
        } else {
            badge.className = "status-pill";
            badge.style.color = "var(--danger)";
            badge.style.backgroundColor = "rgba(239, 68, 68, 0.1)";
            badge.style.borderColor = "rgba(239, 68, 68, 0.15)";
            badge.innerHTML = `<i class="fa-solid fa-cloud-bolt text-danger"></i> Server Offline`;
        }
    }

    async fetchAdminIncidents() {
        const token = localStorage.getItem("alerto_admin_token");
        if (!token) return;

        let endpoint = '';
        if (this.user.type === 'bfp_admin') endpoint = '/api/bfp/incidents';
        else if (this.user.type === 'pnp_admin') endpoint = '/api/pnp/incidents';
        else if (this.user.type === 'mdrrmo_admin') endpoint = '/api/mdrrmo/incidents';
        else if (this.user.type === 'barangay_admin') endpoint = `/api/barangays/${encodeURIComponent(this.user.barangay)}/incidents`;
        else endpoint = '/api/admin/incidents';

        if (endpoint) {
            try {
                const res = await fetch(endpoint, {
                    headers: { 'Authorization': `Bearer ${token}` }
                });
                const data = await res.json();
                if (data.incidents) {
                    this.incidents = data.incidents;
                    this.renderAll();
                }
            } catch(e) {
                console.error("Failed to fetch admin incidents", e);
            }
        }
        
        // MDRRMO only: Fetch assistance requests
        if (this.user.type === 'mdrrmo_admin') {
            try {
                const res = await fetch("/api/mdrrmo/assistance-requests", {
                    headers: { 'Authorization': `Bearer ${token}` }
                });
                const data = await res.json();
                if (data.requests) {
                    this.assistanceRequests = data.requests;
                    this.renderAssistanceRequests();
                }
            } catch (e) {
                console.error("Failed to fetch assistance requests", e);
            }
        }
    }

    renderAssistanceRequests() {
        const tbody = document.getElementById("assistance-tbody");
        if (!tbody || !this.assistanceRequests) return;
        
        if (this.assistanceRequests.length === 0) {
            tbody.innerHTML = `<tr><td colspan="6" class="text-center" style="padding: 24px">No assistance requests pending.</td></tr>`;
            return;
        }

        tbody.innerHTML = this.assistanceRequests.map(req => {
            const date = new Date(req.created_at || Date.now()).toLocaleString();
            return `
                <tr>
                  <td>${date}</td>
                  <td><strong>Brgy. ${req.barangay}</strong></td>
                  <td>${req.requested_by}</td>
                  <td>${req.description}</td>
                  <td><span class="status-pill status-${(req.status || 'pending').toLowerCase()}">${req.status || 'Pending'}</span></td>
                  <td>
                    <button class="action-btn accept-btn" onclick="alert('Dispatching backup to ${req.barangay}...')">Dispatch Backup</button>
                  </td>
                </tr>
            `;
        }).join('');
    }

    renderAll() {
        this.initMap();
        if (this.map) {
            this.updateRespondersOnMap();
        }
        this.renderLogsTable();
        this.renderHistoryRecords();
        this.renderRespondersGrid();
        this.renderBroadcastArchive();
        
        
        this.updateAnalytics();
    }

    

    

    initMap() {
        if (this.map) return;

        setTimeout(() => {
            this.map = L.map('command-map').setView([POZORRUBIO_PLAZA.lat, POZORRUBIO_PLAZA.lng], 14);

            this.mapTileLayer = L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png');
            this.mapTileLayer.addTo(this.map);

            // Restore saved map type or default to standard
            const savedType = localStorage.getItem("alerto_admin_map_type") || "standard";
            this.setMapType(savedType);

            // Setup Map Settings Control
            this.setupMapControls(savedType);

            // Stationary landmarks (RHU, fire station, police station, hospital)
            LANDMARKS.forEach(lm => {
                let color = "#3b82f6";
                if (lm.type === "fire") color = "#f59e0b";
                if (lm.type === "medical") color = "#ef4444";
                
                const dot = L.divIcon({
                    className: 'landmark-dot-marker',
                    html: `<div style="background-color:${color}; border:2.5px solid #fff; border-radius:50%; width:16px; height:16px; box-shadow:0 2px 4px rgba(0,0,0,0.5);" title="${lm.name}"></div>`,
                    iconSize: [16, 16]
                });
                
                L.marker([lm.lat, lm.lng], { icon: dot })
                    .bindPopup(`<b>${lm.name}</b><br>Type: ${lm.type.toUpperCase()}`)
                    .addTo(this.map);
            });

            // Active incidents
            this.incidents.forEach(inc => {
                if (inc.status !== 'resolved') {
                    this.plotIncidentMarker(inc);
                }
            });

            // Responders
            this.updateRespondersOnMap();
            
            // Water Devices
            this.water_devices.forEach(wd => {

                const wdIcon = L.divIcon({
                    className: 'water-device-marker',
                    html: `<div style="background-color:blue; border:2.5px solid #fff; border-radius:50%; width:16px; height:16px; box-shadow:0 2px 4px rgba(0,0,0,0.5);" title="${wd.name}"></div>`,
                    iconSize: [16, 16]
                });
                
                L.marker([wd.lat, wd.lng], { icon: wdIcon })
                    .bindPopup(`<b>${wd.name}</b><br>Type: ${wd.type.toUpperCase()}<br>Status: ${wd.status}`)
                    .addTo(this.map);
            });
        }, 100);
    }

    plotIncidentMarker(inc) {
        if (this.incidentMarkers[inc.id]) return;
        if (inc.category === 'Hardware Emergency') return; // Do not plot hardware emergencies on the map
        
        let color = inc.status === 'new' ? '#ef4444' : '#f59e0b';
        
        const pinIcon = L.divIcon({
            className: `incident-pin inc-${inc.id}`,
            html: `<div style="color: ${color}; font-size: 32px; text-shadow: 0 3px 5px rgba(0,0,0,0.5); text-align: center;"><i class="fa-solid fa-location-dot"></i></div>`,
            iconAnchor: [11, 32],
            popupAnchor: [0, -32]
        });

        let manageBtnHTML = '';
        if (inc.status !== 'resolved' && inc.status !== 'cancelled') {
            manageBtnHTML = `<br><button class="btn btn-danger btn-block" style="margin-top:6px; font-size:10px; padding:3px;" onclick="window.dashSelectIncident('${inc.id}')">Manage Alert</button>`;
        }
        
        const marker = L.marker([inc.lat, inc.lng], { icon: pinIcon })
            .bindPopup(`<b>${(inc.category || 'Draft').toUpperCase()} INCIDENT</b><br>${inc.details}${manageBtnHTML}`);
            
        if (this.selectedIncident) {
            if (this.selectedIncident.id === inc.id) {
                marker.addTo(this.map);
            }
        } else {
            const isBrgyActive = this.user && this.user.type === 'barangay_admin' && ['pending', 'new', 'acknowledged', 'dispatching'].includes((inc.status || '').toLowerCase());
            if (inc.status === 'pending' || inc.status === 'new' || isBrgyActive) {
                marker.addTo(this.map);
            }
        }

        this.incidentMarkers[inc.id] = marker;
        
        window.dashSelectIncident = (id) => this.selectIncidentForDispatch(id);
    }

    updateRespondersOnMap() {
        this.responders.forEach(r => {
            if (this.responderMarkers[r.id]) {
                this.map.removeLayer(this.responderMarkers[r.id]);
            }

            let color = "#3b82f6"; // PNP
            if (r.type === "medical") color = "#ef4444";
            if (r.type === "fire") color = "#f59e0b";

            let repIconHTML = `<div style="background-color:${color}; width:20px; height:20px; border-radius:50%; border:2px solid #fff; box-shadow:0 2px 5px rgba(0,0,0,0.3); display:flex; align-items:center; justify-content:center;" title="${r.name} (${r.status})">
                <i class="fa-solid ${r.icon || 'fa-car-side'}" style="color:white; font-size:10px;"></i>
            </div>`;

            const repIcon = L.divIcon({
                className: `responder-vehicle rep-${r.id}`,
                html: repIconHTML,
                iconAnchor: [14, 14]
            });

            const marker = L.marker([r.lat, r.lng], { icon: repIcon })
                .bindPopup(`<b>${r.name}</b><br>Status: ${r.status.toUpperCase()}`)
                .addTo(this.map);

            this.responderMarkers[r.id] = marker;
        });
    }

    selectIncidentForDispatch(id) {
        const inc = this.incidents.find(i => i.id === id);
        if (!inc) return;

        this.selectedIncident = inc;
        
        const detailsContainer = document.getElementById("incident-details-box");
        const time = new Date(inc.createdAt).toLocaleTimeString();
        
        if (this.user && this.user.type === 'barangay_admin') {
            const incDate = new Date(inc.createdAt);
            const dateFormatted = isNaN(incDate) ? 'Unknown Date' : `${incDate.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' })} • ${incDate.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' })}`;
            const coordsFormatted = (inc.lat && inc.lng) ? `${Number(inc.lat).toFixed(6)}, ${Number(inc.lng).toFixed(6)}` : 'No GPS';
            const locationDisplay = [inc.barangay ? `Barangay ${inc.barangay}` : '', inc.address].filter(Boolean).join(', ') || 'Pozorrubio, Pangasinan';
            const descriptionText = inc.details || inc.description || 'No emergency description provided.';

            let mediaItems = [];
            if (Array.isArray(inc.media)) {
                mediaItems = inc.media;
            } else if (typeof inc.media === 'string') {
                try {
                    const parsed = JSON.parse(inc.media);
                    if (Array.isArray(parsed)) mediaItems = parsed;
                    else if (parsed) mediaItems = [parsed];
                } catch(e) {
                    if (inc.media.trim()) mediaItems = [inc.media.trim()];
                }
            }

            let attachmentsHtml = '';
            if (mediaItems.length > 0) {
                attachmentsHtml = '<div style="display: flex; gap: 8px; flex-wrap: wrap; margin-top: 6px;">';
                mediaItems.forEach(item => {
                    const src = (typeof item === 'string') ? item : (item.url || item.data || item.path || '');
                    if (!src) return;
                    const finalSrc = src.startsWith('http') || src.startsWith('data:') ? src : `${window.SERVER_URL || ''}${src}`;
                    const isVideo = (item.type === 'video') || (typeof src === 'string' && src.match(/\.(mp4|webm|mov|3gp|mkv|avi)$/i));
                    if (isVideo) {
                        attachmentsHtml += `<video src="${finalSrc}" class="feedback-media-img" style="width: 70px; height: 70px; border-radius: 6px; object-fit: cover; border: 1px solid var(--border-color); cursor: pointer;" title="Click to view full video"></video>`;
                    } else {
                        attachmentsHtml += `<img src="${finalSrc}" class="feedback-media-img" style="width: 70px; height: 70px; border-radius: 6px; object-fit: cover; border: 1px solid var(--border-color); cursor: pointer;" alt="Attachment" title="Click to view full image" />`;
                    }
                });
                attachmentsHtml += '</div>';
            } else {
                attachmentsHtml = '<span style="color: var(--text-muted); font-size: 12px; font-style: italic;">No attachments</span>';
            }

            const statusClass = (inc.status || 'pending').toLowerCase();
            const isPending = statusClass === 'pending' || statusClass === 'new';

            detailsContainer.innerHTML = `
                <div class="incident-summary-card" style="padding: 12px; font-size: 13px;">
                    <div class="summary-row" style="margin-bottom: 6px;">
                        <span class="summary-label" style="font-weight: 600;">Incident ID:</span>
                        <span class="summary-val font-mono" style="font-weight: 700; color: var(--primary);">${inc.id}</span>
                    </div>
                    <div class="summary-row" style="margin-bottom: 6px;">
                        <span class="summary-label" style="font-weight: 600;">Category:</span>
                        <span class="badge" style="background: #059669; color: white; padding: 2px 8px; border-radius: 4px; font-weight: 700; font-size: 11px;">BARANGAY</span>
                    </div>
                    <div class="summary-row" style="margin-bottom: 6px;">
                        <span class="summary-label" style="font-weight: 600;">Status:</span>
                        <span class="pills-badge badge-${statusClass}" style="font-weight: 700; text-transform: uppercase;">${inc.status || 'pending'}</span>
                    </div>
                    <div class="summary-row" style="margin-bottom: 6px;">
                        <span class="summary-label" style="font-weight: 600;">Resident / User:</span>
                        <span class="summary-val" style="font-weight: 600;">${inc.reporter || 'Unknown'} ${inc.reporterPhone ? `<span style="color:var(--text-muted); font-weight: 400; font-size: 12px;">(${inc.reporterPhone})</span>` : ''}</span>
                    </div>
                    <div class="summary-row" style="margin-bottom: 6px;">
                        <span class="summary-label" style="font-weight: 600;">Date & Time:</span>
                        <span class="summary-val" style="color: var(--text-secondary);">${dateFormatted}</span>
                    </div>
                    <div class="summary-row" style="margin-bottom: 6px; align-items: flex-start;">
                        <span class="summary-label" style="font-weight: 600;">Location:</span>
                        <span class="summary-val" style="text-align: right; line-height: 1.3;">
                            <span style="font-weight: 600; color: var(--text-primary);">${locationDisplay}</span><br>
                            <span class="font-mono" style="font-size: 11px; color: var(--text-muted);"><i class="fa-solid fa-map-pin"></i> ${coordsFormatted}</span>
                        </span>
                    </div>
                    <div style="margin-top: 8px; padding-top: 8px; border-top: 1px solid var(--border-color);">
                        <span class="summary-label" style="font-weight: 600; display: block; margin-bottom: 4px;">Emergency Description:</span>
                        <div style="background: var(--bg-tertiary); padding: 8px 10px; border-radius: 6px; color: var(--text-primary); font-size: 12px; line-height: 1.4; max-height: 85px; overflow-y: auto;">
                            ${descriptionText}
                        </div>
                    </div>
                    <div style="margin-top: 8px; padding-top: 8px; border-top: 1px solid var(--border-color);">
                        <span class="summary-label" style="font-weight: 600; display: block; margin-bottom: 4px;">Attachments:</span>
                        ${attachmentsHtml}
                    </div>
                    ${isPending ? `
                    <div style="margin-top: 10px; padding-top: 8px; border-top: 1px solid var(--border-color);">
                        <button id="btn-brgy-ack-action" class="btn btn-warning btn-block" style="padding: 7px 12px; font-weight: 600; font-size: 12px; display: flex; align-items: center; justify-content: center; gap: 6px; width: 100%; cursor: pointer;" onclick="window.commandDashboard.acknowledgeIncident('${inc.id}')">
                            <i class="fa-solid fa-check-double"></i> Acknowledge Report
                        </button>
                    </div>
                    ` : (statusClass === 'acknowledged' ? `
                    <div style="margin-top: 8px; padding: 5px 8px; background: #ecfdf5; border: 1px solid #10b981; border-radius: 6px; color: #065f46; font-size: 11px; font-weight: 600; text-align: center;">
                        <i class="fa-solid fa-circle-check"></i> Report Acknowledged by Barangay
                    </div>
                    ` : '')}
                </div>
            `;
            detailsContainer.style.maxHeight = "380px";
        } else {
            detailsContainer.innerHTML = `
                <div class="incident-summary-card">
                    <div class="summary-row">
                        <span class="summary-label">Incident ID:</span>
                        <span class="summary-val font-mono">${inc.id}</span>
                    </div>
                    <div class="summary-row">
                        <span class="summary-label">Category:</span>
                        <span class="summary-val uppercase">${inc.category || 'Draft'}</span>
                    </div>
                    <div class="summary-row">
                        <span class="summary-label">Status:</span>
                        <span class="pills-badge badge-${inc.status}">${inc.status}</span>
                    </div>
                    ${inc.status === 'dispatching' && inc.responseProgress ? `
                    <div class="summary-row">
                        <span class="summary-label">Progress:</span>
                        <span class="summary-val text-primary uppercase font-bold">${inc.responseProgress.replace(/_/g, ' ')}</span>
                    </div>
                    ` : ''}
                    <div class="summary-row">
                        <span class="summary-label">Reporter:</span>
                        <span class="summary-val">${inc.reporter}</span>
                    </div>
                    <div class="summary-row">
                        <span class="summary-label">Time Logged:</span>
                        <span class="summary-val">${time}</span>
                    </div>
                </div>
            `;
        }

        this.renderDispatcherChat(inc);

        this.updateUnitDropdown();
        
        const mapTab = document.querySelector("[data-tab='map']");
        if (!mapTab.classList.contains("active")) {
            mapTab.click();
        }
        
        setTimeout(() => {
            if (this.map) {
                this.map.invalidateSize();
                this.map.flyTo([inc.lat, inc.lng], 18, { animate: true, duration: 1.5 });
                
                // Hide other markers to focus on selected incident
                Object.entries(this.incidentMarkers).forEach(([id, m]) => {
                    m.unbindTooltip();
                    if (id !== inc.id) {
                        if (this.map.hasLayer(m)) {
                            this.map.removeLayer(m);
                        }
                    } else {
                        if (!this.map.hasLayer(m)) {
                            m.addTo(this.map);
                        }
                    }
                });

                const marker = this.incidentMarkers[inc.id];
                if (marker) {
                    const locIcon = L.divIcon({
                        className: 'custom-location-pin',
                        html: '<div style="color: #e11d48; font-size: 42px; text-shadow: 0 4px 6px rgba(0,0,0,0.4);"><i class="fa-solid fa-location-dot"></i></div>',
                        iconAnchor: [15, 42],
                        popupAnchor: [0, -42]
                    });
                    marker.setIcon(locIcon);
                    
                    const setPopupAddress = (address) => {
                        marker.bindPopup(`
                            <div style="max-width: 250px; white-space: normal; text-align: center; font-family: 'Inter', sans-serif; padding: 5px;">
                                <div style="background: #eef2ff; color: #4f46e5; padding: 4px 8px; border-radius: 4px; font-size: 10px; font-weight: 800; display: inline-block; margin-bottom: 6px; text-transform: uppercase;">User Location Detected</div><br>
                                <span style="font-size: 12px; font-weight: 600; color: #1e293b;">${address}</span>
                            </div>
                        `, {
                            offset: [0, -32],
                            closeButton: false
                        }).openPopup();
                    };

                    if (window.BarangayService && typeof window.BarangayService.resolveLocation === 'function') {
                        window.BarangayService.resolveLocation(inc.lat, inc.lng)
                            .then(loc => {
                                const address = loc.formattedAddress || `${inc.barangay || 'Pozorrubio'}, Pozorrubio, Pangasinan`;
                                setPopupAddress(address);
                            })
                            .catch(err => {
                                console.error("BarangayService geocoding failed, falling back", err);
                                const fallbackAddr = inc.barangay ? `${inc.barangay}, Pozorrubio, Pangasinan` : "Pozorrubio, Pangasinan";
                                setPopupAddress(fallbackAddr);
                            });
                    } else if (inc.barangay) {
                        setPopupAddress(`${inc.barangay}, Pozorrubio, Pangasinan`);
                    } else {
                        fetch(`/api/geocode/reverse?lat=${inc.lat}&lng=${inc.lng}`)
                            .then(res => res.json())
                            .then(data => {
                                setPopupAddress(data.formattedAddress || "Pozorrubio, Pangasinan");
                            })
                            .catch(() => setPopupAddress("Pozorrubio, Pangasinan"));
                    }
                }
            }
        }, 150);
    }

    getAvatarHtml(profileImage, gender, size = 32) {
        if (profileImage && profileImage.trim() !== '') {
            const url = profileImage.startsWith('http') ? profileImage : `${window.SERVER_URL || ''}${profileImage}`;
            return `<img src="${url}" style="width: ${size}px; height: ${size}px; border-radius: 50%; object-fit: cover; box-shadow: 0 2px 5px rgba(0,0,0,0.1); flex-shrink: 0;" />`;
        }
        const g = (gender || '').toLowerCase();
        let color = '#ced4da';
        if (g === 'male') color = '#4dabf7';
        else if (g === 'female') color = '#f06595';
        
        return `<div style="width: ${size}px; height: ${size}px; border-radius: 50%; background: ${color}; display: flex; justify-content: center; align-items: center; box-shadow: 0 2px 5px rgba(0,0,0,0.1); flex-shrink: 0;">
            <svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg" style="width: 100%; height: 100%; border-radius: 50%;"><circle cx="50" cy="50" r="50" fill="${color}"/><circle cx="50" cy="40" r="18" fill="#fff"/><path d="M22 90 Q50 55 78 90" stroke="#fff" stroke-width="8" fill="none" stroke-linecap="round"/></svg>
        </div>`;
    }

    buildMessageHtml(msg) {
        if (!msg) return '';
        const isCitizen = msg.sender_role === 'Citizen App';
        const isAdmin = !isCitizen;
        const bubbleClass = isCitizen ? 'chat-incoming' : 'chat-outgoing';
        
        const avatarHtml = isCitizen
            ? this.getAvatarHtml(msg.sender_profile_image || (this.selectedIncident ? this.selectedIncident.profile_image : null), msg.sender_gender || (this.selectedIncident ? this.selectedIncident.gender : null), 32)
            : '';

        let tsHtml = '';
        if (msg.timestamp) {
            const d = new Date(Number(msg.timestamp));
            if (!isNaN(d.getTime())) {
                tsHtml = `<div style="font-size: 10px; opacity: 0.75; text-align: ${isAdmin ? 'right' : 'left'}; margin-top: 6px;">${d.toLocaleDateString('en-US', {month: 'short', day: '2-digit', year: 'numeric'})} &bull; ${d.toLocaleTimeString('en-US', {hour: '2-digit', minute: '2-digit'})}</div>`;
            }
        }

        let mediaHtml = '';
        if (msg.media_url) {
            const mediaSrc = msg.media_url.startsWith('http') ? msg.media_url : `${window.SERVER_URL || ''}${msg.media_url}`;
            const isVideo = msg.message_type === 'video' || (msg.media_url && msg.media_url.match(/\.(mp4|webm|mov|3gp|mkv|avi)$/i));
            if (isVideo) {
                mediaHtml = `<video src="${mediaSrc}" style="max-width: 280px; max-height: 250px; border-radius: 8px; margin-bottom: 6px; display: block; background: #000; cursor: pointer;" controls playsinline preload="metadata"></video>`;
            } else {
                mediaHtml = `<img src="${mediaSrc}" style="max-width: 280px; max-height: 250px; border-radius: 8px; margin-bottom: 6px; display: block; cursor: pointer;" alt="Chat attachment" />`;
            }
        }

        let contentHtml = '';
        if (msg.message_content && msg.message_content.trim() !== '') {
            const escaped = msg.message_content
                .replace(/&/g, '&amp;')
                .replace(/</g, '&lt;')
                .replace(/>/g, '&gt;')
                .replace(/\n/g, '<br>');
            contentHtml = `<div style="word-break: break-word; line-height: 1.4;">${escaped}</div>`;
        }

        if (!mediaHtml && !contentHtml) {
            return '';
        }

        const bubbleHtml = `<div class="chat-bubble ${bubbleClass}" style="${(!contentHtml && mediaHtml) ? 'background: transparent; padding: 0; box-shadow: none;' : ''}">${mediaHtml}${contentHtml}${tsHtml}</div>`;

        if (isAdmin) {
            const adminRole = msg.sender_role || 'Command Center';
            return `
                <div class="chat-message-row" style="display: flex; flex-direction: column; align-items: flex-end; align-self: flex-end; margin-top: 10px; max-width: 85%;">
                    <span style="font-size: 11px; color: var(--text-secondary); font-weight: 600; margin-bottom: 2px; margin-right: 2px;">${adminRole}</span>
                    ${bubbleHtml}
                </div>
            `;
        } else {
            const firstName = (this.selectedIncident && this.selectedIncident.reporter) ? this.selectedIncident.reporter.split(' ')[0] : 'Citizen';
            return `
                <div class="chat-message-row" style="display: flex; gap: 8px; align-items: flex-start; align-self: flex-start; margin-top: 10px; max-width: 85%;">
                    <div>${avatarHtml}</div>
                    <div style="display: flex; flex-direction: column; align-items: flex-start;">
                        <span style="font-size: 12px; color: var(--text-secondary); font-weight: 600; margin-bottom: 2px; margin-left: 2px;">${firstName}</span>
                        ${bubbleHtml}
                    </div>
                </div>
            `;
        }
    }

    async renderDispatcherChat(inc) {
        const chatContainer = document.getElementById("dispatcher-chat-container");
        const chatFeed = document.getElementById("dispatcher-chat-feed");
        const commsActions = document.getElementById("admin-comms-actions");
        const chatInputGroup = chatContainer ? chatContainer.querySelector(".chat-input-group") : null;
        
        if (!chatContainer || !chatFeed) return;

        chatContainer.style.display = "flex";
        
        const isClosed = inc.status === 'resolved' || inc.status === 'cancelled';
        if (commsActions) {
            commsActions.style.display = isClosed ? "none" : "flex";
        }
        if (chatInputGroup) {
            chatInputGroup.style.display = isClosed ? "none" : "flex";
        }
        
        let newFeedHtml = "";

        const firstName = inc.reporter ? inc.reporter.split(' ')[0] : 'Citizen';
        const defaultAvatarHtml = this.getAvatarHtml(inc.profile_image, inc.gender, 32);

        // Parse legacy details
        const notesArr = (inc.details || "").split(" | ");
        const baseDetails = notesArr[0] || "";
        
        // System initial message
        if (baseDetails) {
            newFeedHtml += `<div class="chat-bubble chat-incoming" style="align-self: flex-start; max-width: 85%; margin-top: 6px;"><strong>System:</strong> SOS Received. Details: ${baseDetails}</div>`;
        }
        
        let chatMessages = [];
        this.seenMessageIds = new Set();
        
        // Fetch new messages from API
        if (inc.id && !inc.id.startsWith("DRAFT-")) {
            try {
                const token = localStorage.getItem("alerto_admin_token");
                const headers = {};
                if (token) headers['Authorization'] = `Bearer ${token}`;
                const response = await fetch(`/api/incidents/${inc.id}/messages`, { headers });
                if (response.ok) {
                    const data = await response.json();
                    if (data.success && data.messages && data.messages.length > 0) {
                        chatMessages = data.messages;
                        data.messages.forEach(msg => {
                            const idKey = msg.id ? String(msg.id) : null;
                            const clientKey = msg.client_message_id ? String(msg.client_message_id) : null;
                            if (idKey && this.seenMessageIds.has(idKey)) return;
                            if (clientKey && this.seenMessageIds.has(clientKey)) return;
                            if (idKey) this.seenMessageIds.add(idKey);
                            if (clientKey) this.seenMessageIds.add(clientKey);

                            newFeedHtml += this.buildMessageHtml(msg);
                        });
                    }
                }
            } catch (err) {
                console.error("Failed to fetch admin messages", err);
            }
        }
        
        // Render Legacy Details AND offline appended notes without duplicating DB messages
        if (notesArr.length > 1) {
            for (let i = 1; i < notesArr.length; i++) {
                const note = notesArr[i];
                let text = "";
                let isDispatcher = false;

                if (note.startsWith("Dispatcher:")) {
                    text = note.replace("Dispatcher:", "").trim();
                    isDispatcher = true;
                } else if (note.startsWith("Notes:")) {
                    text = note.replace("Notes:", "").trim();
                } else {
                    continue; // e.g. "Files Attached: X media logs"
                }

                // Check if this text is already in DB messages to prevent duplication
                const isDuplicate = chatMessages.some(msg => msg.message_type === 'text' && msg.message_content === text);
                if (isDuplicate) {
                    continue; // Skip rendering this as it is already drawn from DB
                }

                if (isDispatcher) {
                    newFeedHtml += `
                        <div class="chat-message-row" style="display: flex; flex-direction: column; align-items: flex-end; align-self: flex-end; margin-top: 10px; max-width: 85%;">
                            <span style="font-size: 11px; color: var(--text-secondary); font-weight: 600; margin-bottom: 2px; margin-right: 2px;">Command Center</span>
                            <div class="chat-bubble chat-outgoing">${text}</div>
                        </div>
                    `;
                } else {
                    newFeedHtml += `
                        <div class="chat-message-row" style="display: flex; gap: 8px; align-items: flex-start; align-self: flex-start; margin-top: 10px; max-width: 85%;">
                            <div>${defaultAvatarHtml}</div>
                            <div style="display: flex; flex-direction: column; align-items: flex-start;">
                                <span style="font-size: 12px; color: var(--text-secondary); font-weight: 600; margin-bottom: 2px; margin-left: 2px;">${firstName}</span>
                                <div class="chat-bubble chat-incoming">${text}</div>
                            </div>
                        </div>
                    `;
                }
            }
        }

        if (isClosed) {
            newFeedHtml += `
                <div style="text-align: center; font-size: 11px; color: var(--text-secondary); padding: 10px 0; margin-top: 8px; font-style: italic; border-top: 1px dashed var(--border-color, #e5e7eb);">
                    <i class="fa-solid fa-lock"></i> Incident is ${inc.status} &bull; Chat is closed
                </div>
            `;
        }
        
        chatFeed.innerHTML = newFeedHtml;
        chatFeed.scrollTo({ top: chatFeed.scrollHeight, behavior: 'smooth' });
    }

    async sendDispatcherChat() {
        if (!this.selectedIncident || this.isSendingChat) return;
        const input = document.getElementById("admin-chat-input");
        const sendBtn = document.getElementById("btn-admin-send");
        if (!input) return;
        const msg = input.value.trim();
        if (!msg) return;

        this.isSendingChat = true;
        if (sendBtn) sendBtn.disabled = true;
        input.value = "";
        
        const clientMessageId = 'admin-' + Date.now() + '-' + Math.random().toString(36).substring(2, 9);
        const fd = new FormData();
        const senderId = this.user ? (this.user.username || this.user.id || 'ADMIN') : 'ADMIN';
        const senderRole = this.user && this.user.type === 'barangay_admin' ? `Barangay ${this.user.barangay || 'Official'}` : 'Command Center';
        fd.append('senderId', senderId);
        fd.append('senderRole', senderRole);
        fd.append('messageType', 'text');
        fd.append('messageContent', msg);
        fd.append('clientMessageId', clientMessageId);
        
        try {
            const token = localStorage.getItem("alerto_admin_token");
            const headers = {};
            if (token) headers['Authorization'] = `Bearer ${token}`;
            const res = await fetch(`/api/incidents/${this.selectedIncident.id}/messages`, {
                method: 'POST',
                headers,
                body: fd
            });
            if (!res.ok) {
                const errData = await res.json().catch(() => ({}));
                throw new Error(errData.error || `Server returned ${res.status}`);
            }
        } catch (err) {
            console.error("Failed to send text message", err);
            input.value = msg;
            alert("Failed to send message: " + (err.message || "Network error. Please try again."));
        } finally {
            this.isSendingChat = false;
            if (sendBtn) sendBtn.disabled = false;
            input.focus();
        }
    }

    initiateCall(type) {
        if (!this.selectedIncident) return;
        alert(`Initiating ${type} call to user for incident ${this.selectedIncident.id}...`);
        this.socket.emit('admin-call-initiate', {
            incidentId: this.selectedIncident.id,
            type: type
        });
    }

    updateUnitDropdown() {
        if (!this.selectedIncident) return;
        
        if (this.user && this.user.type === 'barangay_admin') {
            const statusOptions = [
                { value: 'pending', label: 'Pending' },
                { value: 'acknowledged', label: 'Acknowledged' },
                { value: 'dispatching', label: 'Responding / Dispatching' },
                { value: 'resolved', label: 'Resolved' },
                { value: 'closed', label: 'Closed' },
                { value: 'cancelled', label: 'Cancelled' }
            ];
            this.statusSelector.innerHTML = statusOptions.map(o => `<option value="${o.value}">${o.label}</option>`).join('');
            const curStatus = (this.selectedIncident.status || 'pending').toLowerCase();
            this.statusSelector.value = statusOptions.some(o => o.value === curStatus) ? curStatus : 'pending';
        } else {
            this.statusSelector.value = this.selectedIncident.status || 'Draft';
        }
        this.statusSelector.disabled = false;
        
        this.unitSelector.innerHTML = '<option value="">-- Select Available Personnel/Unit --</option>';
        this.vehicleSelector.innerHTML = '<option value="">-- Select Available Vehicle --</option>';
        
        if (this.user && this.user.type === 'barangay_admin') {
            const brgyOpt = document.createElement("option");
            brgyOpt.value = "barangay_patrol";
            brgyOpt.textContent = `Barangay ${this.user.barangay} Tanod / Quick Response Team`;
            this.unitSelector.appendChild(brgyOpt);
        }

        const availableUnits = this.responders.filter(r => r.status === 'available');
        
        // Simple Haversine helper
        const getDistance = (lat1, lon1, lat2, lon2) => {
            const p = 0.017453292519943295;
            const c = Math.cos;
            const a = 0.5 - c((lat2 - lat1) * p)/2 + 
                    c(lat1 * p) * c(lat2 * p) * 
                    (1 - c((lon2 - lon1) * p))/2;
            return 12742 * Math.asin(Math.sqrt(a)); 
        };
        
        // Sort by distance to incident
        availableUnits.sort((a, b) => {
            return getDistance(a.lat, a.lng, this.selectedIncident.lat, this.selectedIncident.lng) - getDistance(b.lat, b.lng, this.selectedIncident.lat, this.selectedIncident.lng);
        });
        
        const recommendedGroup = document.createElement("optgroup");
        recommendedGroup.label = "Recommended Responders";
        const otherGroup = document.createElement("optgroup");
        otherGroup.label = "Other Available Responders";
        
        let closestRecommendedLabeled = false;
        
        availableUnits.forEach((r) => {
            const cat = (this.selectedIncident.category || "").toLowerCase();
            let isRecommended = false;
            
            if (cat === "fire" && r.type === "fire") isRecommended = true;
            else if (cat === "medical" && r.type === "medical") isRecommended = true;
            else if (cat === "crime" && r.type === "police") isRecommended = true;
            else if (cat === "accident" && (r.type === "medical" || r.type === "police")) isRecommended = true;
            else if (cat === "flood" || cat === "rescue" || cat === "hardware emergency" || cat === "other" || cat === "barangay") isRecommended = true;
            
            const opt = document.createElement("option");
            opt.value = r.id;
            
            let label = `${r.name} [${r.type.toUpperCase()}]`;
            if (isRecommended && !closestRecommendedLabeled) {
                label += " (Closest)";
                closestRecommendedLabeled = true;
            }
            opt.textContent = label;
            
            if (isRecommended) {
                recommendedGroup.appendChild(opt);
            } else {
                otherGroup.appendChild(opt);
            }
        });
        
        if (recommendedGroup.children.length > 0) this.unitSelector.appendChild(recommendedGroup);
        if (otherGroup.children.length > 0) this.unitSelector.appendChild(otherGroup);
        
        const availableVehicles = this.rescue_vehicles.filter(v => v.status === 'available' || v.status === 'Available');
        availableVehicles.forEach(v => {
            const opt = document.createElement("option");
            opt.value = v.id || v.name;
            opt.textContent = `${v.name} (${v.number})`;
            this.vehicleSelector.appendChild(opt);
        });

        if (this.selectedIncident.assignedUnit) this.unitSelector.value = this.selectedIncident.assignedUnit;
        if (this.selectedIncident.assignedVehicle) this.vehicleSelector.value = this.selectedIncident.assignedVehicle;

        this.unitSelector.disabled = false;
        this.vehicleSelector.disabled = false;
        this.dispatchBtn.disabled = false;
    }

    async handleDispatch() {
        if (!this.selectedIncident) return;
        
        const unitId = this.unitSelector.value;
        const vehicleId = this.vehicleSelector.value;
        const status = this.statusSelector.value;

        this.unitSelector.disabled = true;
        this.vehicleSelector.disabled = true;
        this.statusSelector.disabled = true;
        this.dispatchBtn.disabled = true;
        
        try {
            const payload = {
                status: status,
                assignedUnit: unitId,
                assignedVehicle: vehicleId,
                updatedBy: this.user ? (this.user.name || (this.user.type === 'barangay_admin' ? `Barangay ${this.user.barangay} Official` : 'Command Center')) : 'Command Center'
            };
            
            if (status === 'dispatching' && unitId) {
                payload.responseProgress = 'en_route';
            } else if (status === 'resolved' || status === 'closed') {
                payload.responseProgress = null; // Clear on resolve
                if (this.gpsStreams && this.gpsStreams[this.selectedIncident.id]) {
                    clearInterval(this.gpsStreams[this.selectedIncident.id]);
                    delete this.gpsStreams[this.selectedIncident.id];
                }
            }
            
            const res = await fetch(`/api/incidents/${this.selectedIncident.id}`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            });

            if (this.user && this.user.type === 'barangay_admin' && res.ok) {
                this.selectedIncident.status = status;
                if (unitId) this.selectedIncident.assignedUnit = unitId;
                if (vehicleId) this.selectedIncident.assignedVehicle = vehicleId;

                const statusLabelMap = {
                    pending: 'Pending',
                    acknowledged: 'Acknowledged',
                    dispatching: 'Responding / Dispatching',
                    resolved: 'Resolved',
                    closed: 'Closed',
                    cancelled: 'Cancelled'
                };
                const statusLabel = statusLabelMap[(status || '').toLowerCase()] || status;
                await this.postAutomatedOfficialMessage(`[Status Update] Emergency report status updated to "${statusLabel}" by Barangay ${this.user.barangay} Officials.`);

                this.selectIncidentForDispatch(this.selectedIncident.id);
                this.renderLogsTable();
                this.renderHistoryRecords();
                this.updateAnalytics();
            }

            alert('Incident updated successfully.');
            
            if (unitId && status === 'dispatching') {
                const unit = this.responders.find(r => r.id === unitId);
                if (unit) this.streamVehicleGPS(unit, this.selectedIncident);
            }
        } catch(e) {
            console.error(e);
            alert('Failed to update incident.');
        } finally {
            if (this.selectedIncident) {
                this.unitSelector.disabled = false;
                this.vehicleSelector.disabled = false;
                this.statusSelector.disabled = false;
                this.dispatchBtn.disabled = false;
            }
        }
    }

    async acknowledgeIncident(id) {
        const inc = this.incidents.find(i => i.id === id) || this.selectedIncident;
        if (!inc) return;
        this.selectedIncident = inc;

        try {
            const officialName = this.user ? (this.user.name || `Barangay ${this.user.barangay} Official`) : 'Barangay Official';
            const res = await fetch(`/api/incidents/${id}`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    status: 'acknowledged',
                    updatedBy: officialName
                })
            });
            if (res.ok) {
                inc.status = 'acknowledged';
                await this.postAutomatedOfficialMessage(`[Official Acknowledgment] Emergency report has been acknowledged by Barangay ${this.user ? this.user.barangay : ''} Officials. Assistance is being coordinated.`);
                this.selectIncidentForDispatch(id);
                this.renderLogsTable();
                this.renderHistoryRecords();
                this.updateAnalytics();
            }
        } catch (err) {
            console.error("Failed to acknowledge incident:", err);
            alert("Failed to acknowledge report.");
        }
    }

    async postAutomatedOfficialMessage(messageText) {
        if (!this.selectedIncident || !messageText) return;
        const senderId = this.user ? (this.user.username || this.user.id || 'ADMIN') : 'ADMIN';
        const senderRole = this.user && this.user.type === 'barangay_admin'
            ? `Barangay ${this.user.barangay || 'Official'}`
            : 'Command Center';
        const clientMessageId = 'admin-status-' + Date.now() + '-' + Math.random().toString(36).substring(2, 9);
        try {
            const token = localStorage.getItem("alerto_admin_token");
            const headers = { 'Content-Type': 'application/json' };
            if (token) headers['Authorization'] = `Bearer ${token}`;
            await fetch(`/api/incidents/${this.selectedIncident.id}/messages`, {
                method: 'POST',
                headers,
                body: JSON.stringify({
                    senderId,
                    senderRole,
                    messageType: 'text',
                    messageContent: messageText,
                    clientMessageId
                })
            });
        } catch (e) {
            console.error("Failed to post automated official message:", e);
        }
    }

    streamVehicleGPS(unit, incident) {
        const startLat = unit.lat;
        const startLng = unit.lng;
        const endLat = incident.lat;
        const endLng = incident.lng;
        
        const totalSteps = 50;
        let step = 0;
        
        const dispatchTime = Date.now();
        this.gpsStreams = this.gpsStreams || {};
        this.gpsStreams[incident.id] = setInterval(() => {
            step++;
            const r = step / totalSteps;
            
            const currentLat = startLat + (endLat - startLat) * r;
            const currentLng = startLng + (endLng - startLng) * r;
            
            // Emit coordinates update to server (will reflect to citizen map as well!)
            this.socket.emit('responder-gps-update', {
                id: unit.id,
                lat: currentLat,
                lng: currentLng
            });

            if (step >= totalSteps) {
                clearInterval(this.gpsStreams[incident.id]);
                delete this.gpsStreams[incident.id];
                
                // Simulate on-site arrival
                setTimeout(() => {
                    fetch(`/api/incidents/${incident.id}`, {
                        method: 'PUT',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ status: 'dispatching', responseProgress: 'on_scene' })
                    });
                    
                    // Simulate start of rescue operations shortly after arrival
                    setTimeout(() => {
                        fetch(`/api/incidents/${incident.id}`, {
                            method: 'PUT',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({ status: 'dispatching', responseProgress: 'rescue_in_progress' })
                        });
                        
                        // Track response duration metrics (from dispatch to start of rescue)
                        const elapsed = Math.round((Date.now() - dispatchTime) / 1000);
                        CommandDashboard.responseTimes = CommandDashboard.responseTimes || [];
                        CommandDashboard.responseTimes.push(elapsed);
                        
                        this.playSuccessChime();
                    }, 4000); // Wait 4s on scene before rescue in progress
                }, 800);
            }
        }, 60);
    }

    renderLogsTable() {
        const tbody = document.getElementById("logs-tbody");
        if (!tbody) return;

        if (this.incidents.length === 0) {
            tbody.innerHTML = `<tr><td colspan="8" style="text-align:center; color:var(--text-muted);">No emergencies logged.</td></tr>`;
            return;
        }

        const filterSelect = document.getElementById("logs-filter-status");
        const statusFilter = filterSelect ? filterSelect.value.toLowerCase() : "all";

        const filteredIncidents = this.incidents.filter(inc => {
            if (statusFilter === "all") return true;
            return (inc.status || "").toLowerCase() === statusFilter;
        });

        if (filteredIncidents.length === 0) {
            tbody.innerHTML = `<tr><td colspan="8" style="text-align:center; color:var(--text-muted);">No emergencies match the selected status.</td></tr>`;
            return;
        }

        let html = '';
        filteredIncidents.forEach(inc => {
            const time = new Date(inc.createdAt).toLocaleTimeString();
            const latencyMs = inc.networkReceivedAt ? (inc.networkReceivedAt - inc.createdAt) : 0;
            
            let latencyHTML = '';
            if (latencyMs < 500) {
                latencyHTML = `<span class="latency-label-low"><i class="fa-solid fa-check"></i> ${latencyMs}ms</span>`;
            } else {
                latencyHTML = `<span class="latency-label-high"><i class="fa-solid fa-cloud-arrow-up"></i> ${Math.round(latencyMs/1000)}s (Synced)</span>`;
            }

            const stLower = (inc.status || 'pending').toLowerCase();
            const badgeColor = (stLower === 'resolved' || stLower === 'closed') ? 'var(--success)' : 
                               stLower === 'acknowledged' ? '#059669' :
                               stLower === 'cancelled' ? 'var(--text-muted)' : 
                               stLower === 'draft' ? 'var(--warning)' : 'var(--info)';

            const isBrgyAdmin = this.user && this.user.type === 'barangay_admin';
            const canAck = isBrgyAdmin && (stLower === 'pending' || stLower === 'new');

            html += `
                <tr class="${inc.status === 'new' ? 'new-incident-row' : ''}">
                    <td style="font-size: 13px;">${inc.id}</td>
                    <td style="font-size: 13px;">${isBrgyAdmin ? new Date(inc.createdAt || inc.created_at || inc.timestamp || Date.now()).toLocaleString() : time}</td>
                    <td>
                        <div style="display: flex; align-items: center; gap: 8px;">
                            ${inc.category === 'Hardware Emergency' ? `<div style="width: 24px; height: 24px; border-radius: 50%; background: var(--danger); display: flex; align-items: center; justify-content: center; color: white; font-size: 12px;"><i class="fa-solid fa-microchip"></i></div>` : this.getAvatarHtml(inc.profile_image, inc.gender, 24)}
                            <div>
                                <b style="color: var(--text-primary); font-size: 13px;">${inc.reporter || inc.name || 'Unknown'}</b><br>
                                <span style="font-size:11px; color:var(--text-muted);">${inc.category === 'Hardware Emergency' ? 'SYSTEM TRIGGER' : (inc.reporterPhone || inc.phone || 'Unknown')}</span>
                            </div>
                        </div>
                    </td>
                    <td class="capitalize" style="font-size: 13px;">${inc.type || inc.category || 'Unknown'}</td>
                    <td class="font-mono" style="font-size: 13px; color: var(--text-secondary);">${Number(inc.lat || 0).toFixed(4)}, ${Number(inc.lng || 0).toFixed(4)}</td>
                    <td style="font-size: 13px;">${latencyHTML}</td>
                    <td>${inc.category === 'Hardware Emergency' ? `<span style="color: var(--danger); font-size: 12px; font-weight: bold; text-transform: uppercase;"><i class="fa-solid fa-triangle-exclamation"></i> Alert!</span>` : `<span class="badge" style="background: ${badgeColor}; color: white; padding: 4px 8px; border-radius: 4px; font-size: 11px; font-weight: 600; text-transform: uppercase;">${inc.status}</span>`}</td>
                    <td style="font-size: 13px;">
                        ${inc.status === 'draft' ? 
                            `<i class="fa-regular fa-clock text-warning"></i> Drafting` : 
                            (inc.category === 'Hardware Emergency' ? `<span style="color: var(--text-muted); font-size: 11px;"><i class="fa-solid fa-microchip"></i> Hardware Log</span>` : 
                            (isBrgyAdmin ? `
                                <div style="display:flex; gap:4px; align-items:center;">
                                    <button class="btn btn-secondary" style="padding: 4px 10px; font-size: 11px; background-color: white; border: 1px solid var(--border-color); border-radius: 4px; cursor: pointer;" onclick="window.dashSelectIncident('${inc.id}')">Manage</button>
                                    ${canAck ? `<button class="btn btn-primary" style="padding: 4px 8px; font-size: 11px; background-color: #059669; color: white; border: none; border-radius: 4px; cursor: pointer;" onclick="event.stopPropagation(); window.dashAcknowledgeIncident('${inc.id}')">Ack</button>` : ''}
                                </div>
                            ` : (inc.status !== 'resolved' && inc.status !== 'cancelled' ? 
                                `<button class="btn btn-secondary" style="padding: 4px 12px; font-size: 11px; background-color: white; border: 1px solid var(--border-color); border-radius: 4px; cursor: pointer;" onclick="window.dashSelectIncident('${inc.id}')">Manage</button>` : 
                                (inc.status === 'resolved' ? `<span style="color: var(--success); font-weight: 500;"><i class="fa-solid fa-check"></i> Resolved</span>` : `<span style="color: var(--danger); font-weight: 500;"><i class="fa-solid fa-ban"></i> Cancelled</span>`)
                            )))
                        }
                    </td>
                </tr>
            `;
        });
        tbody.innerHTML = html;
    }

    renderHistoryRecords() {
        if (!this.historyTableBody) return;

        const searchQuery = this.histSearch ? this.histSearch.value.toLowerCase() : "";
        const statusFilter = this.histStatusFilter ? this.histStatusFilter.value : "all";
        const typeFilter = this.histTypeFilter ? this.histTypeFilter.value : "all";
        const dateFilter = this.histDateFilter ? this.histDateFilter.value : "";

        // Status Map
        const getMappedStatus = (rawStatus) => {
            const lower = (rawStatus || '').toLowerCase();
            if (['resolved', 'closed'].includes(lower)) return 'Resolved';
            if (['cancelled', 'canceled'].includes(lower)) return 'Cancelled';
            return 'Pending';
        };

        const filtered = this.incidents.filter(inc => {
            // Search
            if (searchQuery) {
                const searchStr = `${inc.id} ${inc.name} ${inc.address} ${inc.details}`.toLowerCase();
                if (!searchStr.includes(searchQuery)) return false;
            }
            // Status
            const mappedStatus = getMappedStatus(inc.status);
            if (statusFilter !== 'all' && mappedStatus.toLowerCase() !== statusFilter) return false;
            // Type
            if (typeFilter !== 'all' && inc.category !== typeFilter) return false;
            // Date
            if (dateFilter) {
                const incDate = new Date(inc.timestamp).toISOString().split('T')[0];
                if (incDate !== dateFilter) return false;
            }
            return true;
        });

        // Update Summary Cards
        let counts = { pending: 0, resolved: 0, cancelled: 0 };
        this.incidents.forEach(inc => {
            const mapped = getMappedStatus(inc.status).toLowerCase();
            if (counts[mapped] !== undefined) counts[mapped]++;
        });

        if (this.histTotal) this.histTotal.textContent = this.incidents.length;
        if (this.histPending) this.histPending.textContent = counts.pending;
        if (this.histResolved) this.histResolved.textContent = counts.resolved;
        if (this.histCancelled) this.histCancelled.textContent = counts.cancelled;

        // Render Table
        let html = '';
        if (filtered.length === 0) {
            html = `<tr><td colspan="7" class="text-center" style="padding: 24px;">No emergency records found.</td></tr>`;
        } else {
            filtered.forEach(inc => {
                const mappedStatus = getMappedStatus(inc.status);
                let badgeClass = 'bg-warning';
                if (mappedStatus === 'Resolved') badgeClass = 'bg-success';
                if (mappedStatus === 'Cancelled') badgeClass = 'bg-danger';

                const timestamp = inc.createdAt || inc.created_at || inc.timestamp;
                const d = new Date(timestamp);
                const timeStr = isNaN(d) ? 'Unknown Date' : `${d.toLocaleDateString()} ${d.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})}`;
                const reporterName = inc.reporter || inc.name || 'Unknown';
                const cat = inc.type || inc.category || 'Unknown';
                let loc = inc.address;
                if (!loc && inc.lat && inc.lng) loc = `GPS: ${inc.lat.toFixed(4)}, ${inc.lng.toFixed(4)}`;
                if (!loc) loc = 'Unknown Location';
                
                const hasLocation = !!(inc.lat && inc.lng);
                const viewBtn = hasLocation ? `<button class="btn btn-secondary" style="padding: 2px 6px; font-size: 10px; margin-left: 8px; border-radius: 4px;" onclick="window.dashViewMapLocation(${inc.lat}, ${inc.lng}, '${inc.id}')">View</button>` : '';

                html += `
                    <tr style="transition: all 0.2s ease;">
                        <td class="font-mono text-sm" style="font-weight: 500; color: var(--text-primary); padding: 16px 10px;">${inc.id}</td>
                        <td style="text-transform: capitalize; padding: 16px 10px; color: var(--text-secondary);"><span style="background: var(--bg-tertiary); padding: 4px 10px; border-radius: 20px; font-size: 12px; font-weight: 500;">${cat}</span></td>
                        <td style="padding: 16px 10px; color: var(--text-secondary); font-weight: 500;">
                            <div style="display: flex; align-items: center; gap: 8px;">
                                ${this.getAvatarHtml(inc.profile_image, inc.gender, 24)}
                                <span>${reporterName}</span>
                            </div>
                        </td>
                        <td style="padding: 16px 10px;"><div style="display: flex; align-items: center; max-width: 250px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; color: var(--text-secondary);" title="${loc}"><i class="fa-solid fa-location-dot" style="color: var(--danger); margin-right: 4px; opacity: 0.8;"></i> ${loc} ${viewBtn}</div></td>
                        <td class="text-sm" style="padding: 16px 10px; color: var(--text-muted); font-size: 13px;">${timeStr}</td>
                        <td style="padding: 16px 10px;"><span class="badge ${badgeClass}" style="padding: 6px 12px; font-weight: 600;">${mappedStatus}</span></td>
                        <td style="padding: 16px 10px;">
                            <button class="btn btn-secondary" style="padding: 6px 12px; font-size: 12px; border-radius: 6px; font-weight: 500; background: var(--bg-tertiary); color: var(--text-primary); border: 1px solid var(--border-color); box-shadow: 0 1px 2px rgba(0,0,0,0.05);" onclick="window.dashViewHistoryDetails('${inc.id}')">View Details</button>
                        </td>
                    </tr>
                `;
            });
        }
        this.historyTableBody.innerHTML = html;
    }

    viewMapLocation(lat, lng, id) {
        // 1. Switch to Map tab
        const mapTab = document.querySelector("[data-tab='map']");
        if (mapTab && !mapTab.classList.contains("active")) {
            mapTab.click();
        }
        
        // 2. Focus map on coords
        if (this.map) {
            this.map.setView([lat, lng], 18);
            
            // 3. Highlight or add temporary marker
            this.map.closePopup();
            
            let existingMarker = null;
            this.map.eachLayer(layer => {
                if (layer.options && layer.options.incidentId === id) {
                    existingMarker = layer;
                }
            });
            
            if (existingMarker) {
                existingMarker.openPopup();
            } else {
                // Pin for historical incident
                const tempMarker = L.marker([lat, lng], {
                    icon: L.divIcon({
                        className: 'custom-div-icon',
                        html: `<div style="background-color:var(--danger);width:16px;height:16px;border-radius:50%;border:2px solid white;box-shadow:0 0 8px rgba(0,0,0,0.4);"></div>`,
                        iconSize: [16, 16],
                        iconAnchor: [8, 8]
                    })
                }).addTo(this.map);
                
                tempMarker.bindPopup(`<b>Incident ID:</b> ${id}<br><b>Location:</b> Historical Location<br><br><span style="font-size:10px;color:gray;">This is a resolved/archived incident.</span>`).openPopup();
                
                tempMarker.on('popupclose', () => {
                    this.map.removeLayer(tempMarker);
                });
            }
        }
    }

    viewHistoryDetails(id) {
        const inc = this.incidents.find(i => i.id === id);
        if (!inc) return;

        const getMappedStatus = (rawStatus) => {
            const lower = (rawStatus || '').toLowerCase();
            if (['resolved', 'closed'].includes(lower)) return 'Resolved';
            if (['cancelled', 'canceled'].includes(lower)) return 'Cancelled';
            return 'Pending';
        };

        const timestamp = inc.createdAt || inc.created_at || inc.timestamp;
        const d = new Date(timestamp);
        
        document.getElementById("hist-det-id").textContent = inc.id;
        document.getElementById("hist-det-time").textContent = isNaN(d) ? 'Unknown Date' : `${d.toLocaleDateString()} ${d.toLocaleTimeString()}`;
        document.getElementById("hist-det-type").textContent = inc.type || inc.category || 'Unknown';
        
        const severity = inc.severity || 'Normal';
        const sevColor = severity.toLowerCase() === 'critical' ? 'var(--danger)' : 'var(--warning)';
        document.getElementById("hist-det-severity").innerHTML = `<span class="badge" style="background: ${sevColor}; color: white; padding: 4px 8px; border-radius: 4px;">${severity}</span>`;
        
        document.getElementById("hist-det-status").textContent = getMappedStatus(inc.status);
        
        const reporterName = inc.reporter || inc.name || 'Unknown';
        const reporterPhone = inc.reporterPhone || inc.phone || 'No Phone';
        document.getElementById("hist-det-reporter").textContent = `${reporterName} (${reporterPhone})`;
        
        if (this.user && this.user.type === 'barangay_admin') {
            const coordsStr = (inc.lat && inc.lng) ? ` (${Number(inc.lat).toFixed(6)}, ${Number(inc.lng).toFixed(6)})` : '';
            const brgyPrefix = inc.barangay ? `Brgy. ${inc.barangay} — ` : '';
            document.getElementById("hist-det-location").textContent = `${brgyPrefix}${inc.address || 'Reported Location'}${coordsStr}`;
        } else {
            document.getElementById("hist-det-location").textContent = inc.address || 'Unknown Location';
        }
        
        let formattedDetails = (inc.description || inc.details || "No notes available").replace(/ \| /g, "<br><br>");
        if (this.user && this.user.type === 'barangay_admin' && inc.media && Array.isArray(inc.media) && inc.media.length > 0) {
            const mediaItemsHtml = inc.media.map(m => {
                if (typeof m === 'string' && (m.startsWith('data:video/') || m.endsWith('.mp4') || m.endsWith('.webm'))) {
                    return `<video src="${m}" controls style="width:100px; height:80px; object-fit:cover; border-radius:6px; border:1px solid var(--border-color);"></video>`;
                }
                return `<img src="${m}" class="feedback-media-img" style="width:100px; height:80px; object-fit:cover; border-radius:6px; cursor:pointer; border:1px solid var(--border-color);" alt="Attachment">`;
            }).join('');
            formattedDetails += `<div style="margin-top:12px; padding-top:10px; border-top:1px solid var(--border-color);"><strong>Attachments (${inc.media.length}):</strong><div style="display:flex; flex-wrap:wrap; gap:8px; margin-top:6px;">${mediaItemsHtml}</div></div>`;
        }
        document.getElementById("hist-det-desc").innerHTML = formattedDetails;
        
        // Responder details
        let assignedResponder = "None Assigned";
        if (inc.assignedUnit) {
            const resp = this.responders.find(r => r.id === inc.assignedUnit);
            if (resp) assignedResponder = resp.name;
        }
        document.getElementById("hist-det-responder").textContent = assignedResponder;
        document.getElementById("hist-det-vehicle").textContent = inc.assignedVehicle || inc.rescueVehicle || "None Assigned";

        document.getElementById("modal-history-details").classList.remove("hidden");
    }

    renderRespondersGrid() {
        const container = document.getElementById("responders-grid-container");
        if (!container) return;

        const searchQuery = document.getElementById("resp-search").value.toLowerCase();
        const typeFilter = document.getElementById("resp-filter-type").value;
        const statusFilter = document.getElementById("resp-filter-status").value;

        const filtered = this.responders.filter(r => {
            if (searchQuery && !r.name.toLowerCase().includes(searchQuery)) return false;
            if (typeFilter !== 'all' && r.type !== typeFilter) return false;
            if (statusFilter !== 'all' && r.status !== statusFilter) return false;
            return true;
        });

        let html = '';
        filtered.forEach(r => {
            const iconClass = r.type === 'medical' ? 'med' : (r.type === 'fire' ? 'fire' : 'police');
            const statusLower = (r.status || '').toLowerCase();
            const availableClass = statusLower === 'available' ? 'rep-available' : 'rep-busy';
            const displayStatus = statusLower === 'busy' ? 'On Rescue' : (statusLower === 'available' ? 'AVAILABLE' : r.status);
            html += `
                <div class="responder-card">
                    <div class="responder-card-top">
                        <span class="rep-name">${r.name}</span>
                        <span class="rep-status-badge ${availableClass}">${displayStatus}</span>
                    </div>
                    <div class="responder-card-body" style="margin: 12px 0;">
                        <i class="fa-solid ${r.icon} rep-icon ${iconClass}"></i>
                        <div style="text-align:right;">
                            <span style="color:var(--text-secondary); font-size:11px;">Coordinates:</span>
                            <div class="font-mono" style="font-size:12px; color: var(--text-primary); font-weight: 500;">${r.lat.toFixed(4)}, ${r.lng.toFixed(4)}</div>
                        </div>
                    </div>
                    <div style="display: flex; gap: 8px; margin-top: auto;">
                        <button class="btn btn-secondary" style="flex: 1; font-size: 13px; font-weight: 500; background: white; border: 1px solid var(--border-color); color: var(--text-secondary); padding: 8px;" onclick="window.dashEditResponder('${r.id}')"><i class="fa-solid fa-pen"></i> Edit</button>
                        <button class="btn" style="flex: 1; font-size: 13px; font-weight: 500; padding: 8px; background: rgba(239, 68, 68, 0.05); color: var(--danger); border: 1px solid rgba(239, 68, 68, 0.2);" onclick="window.dashDeleteResponder('${r.id}')"><i class="fa-solid fa-trash"></i> Delete</button>
                    </div>
                </div>
            `;
        });
        container.innerHTML = html;
    }

    async handleSaveResponder() {
        const id = document.getElementById("resp-id").value || `resp-${Date.now()}`;
        const isEdit = !!document.getElementById("resp-id").value;
        const name = document.getElementById("resp-name").value;
        const type = document.getElementById("resp-type").value;
        const status = document.getElementById("resp-status").value;
        const lat = parseFloat(document.getElementById("resp-lat").value);
        const lng = parseFloat(document.getElementById("resp-lng").value);
        const icon = document.getElementById("resp-icon").value;

        const url = isEdit ? `/api/responders/${id}` : `/api/responders`;
        const method = isEdit ? `PUT` : `POST`;

        try {
            const res = await fetch(url, {
                method,
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ id, name, type, lat, lng, status, icon })
            });
            const data = await res.json();
            if (data.success) {
                if (window.dashCloseResponderModal) window.dashCloseResponderModal();
            } else {
                alert("Failed to save responder: " + data.error);
            }
        } catch (e) {
            alert("Network error.");
        }
    }

    editResponder(id) {
        const r = this.responders.find(res => res.id === id);
        if (!r) return;
        document.getElementById("resp-id").value = r.id;
        document.getElementById("resp-name").value = r.name;
        document.getElementById("resp-type").value = r.type;
        document.getElementById("resp-status").value = r.status;
        document.getElementById("resp-lat").value = r.lat;
        document.getElementById("resp-lng").value = r.lng;
        document.getElementById("resp-icon").value = r.icon;
        
        document.getElementById("resp-modal-title").textContent = "Edit Responder";
        document.getElementById("responder-modal").classList.remove("hidden");
        document.body.style.overflow = "hidden";
    }

    async deleteResponder(id) {
        if (this.isDeletingResponder) return;
        this.isDeletingResponder = true;
        if (!confirm("Are you sure you want to delete this responder?")) {
            this.isDeletingResponder = false;
            return;
        }
        try {
            const res = await fetch(`/api/responders/${id}`, { method: 'DELETE' });
            const data = await res.json();
            if (!data.success) {
                alert("Failed to delete responder: " + data.error);
            }
        } catch(e) {
            alert("Network error.");
        } finally {
            setTimeout(() => { this.isDeletingResponder = false; }, 500);
        }
    }

    async handleBarangayAssist() {
        const descInput = document.getElementById("brgy-assist-desc");
        const description = descInput.value.trim();
        const token = localStorage.getItem("alerto_admin_token");
        
        if (!description || !token) return;
        
        try {
            const btn = document.querySelector("#brgy-assist-form button");
            const ogText = btn.innerHTML;
            btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Sending...';
            btn.disabled = true;
            
            const res = await fetch("/api/barangay/assistance-request", {
                method: "POST",
                headers: { 
                    "Content-Type": "application/json",
                    "Authorization": `Bearer ${token}` 
                },
                body: JSON.stringify({
                    lat: POZORRUBIO_PLAZA.lat, // Can use current map center instead later
                    lng: POZORRUBIO_PLAZA.lng,
                    description: description
                })
            });
            const data = await res.json();
            
            if (data.success) {
                alert("Emergency Assistance Request sent to MDRRMO.");
                descInput.value = "";
            } else {
                alert("Failed: " + (data.error || "Unknown error"));
            }
            
            btn.innerHTML = ogText;
            btn.disabled = false;
        } catch (e) {
            console.error("Error sending assist request:", e);
            alert("Network error.");
        }
    }

    handleSendBroadcast() {
        const title = document.getElementById("broadcast-title").value.trim();
        const category = document.getElementById("broadcast-category").value;
        const message = document.getElementById("broadcast-message").value.trim();

        const broadcast = {
            id: "BRD-" + Math.floor(1000 + Math.random() * 9000),
            title,
            category,
            message,
            timestamp: Date.now()
        };

        // Send warning Socket emit to server (routes to all active citizens)
        this.socket.emit('broadcast-command-warning', broadcast);

        this.broadcastForm.reset();
        
        // Add locally
        this.broadcasts.unshift(broadcast);
        this.renderBroadcastArchive();
    }

    renderBroadcastArchive() {
        const container = document.getElementById("sent-broadcasts-list");
        if (!container) return;

        if (this.broadcasts.length === 0) {
            container.innerHTML = `<p class="empty-placeholder">No broadcasts issued in this session.</p>`;
            return;
        }

        const sortedBroadcasts = Array.from(this.broadcasts).sort((a, b) => b.timestamp - a.timestamp);
        const html = sortedBroadcasts.map(b => {
            const time = new Date(b.timestamp).toLocaleTimeString();
            return `
                <div class="archive-item ${b.category}">
                    <div class="archive-item-header">
                        <h4>${b.title}</h4>
                        <span>${time}</span>
                    </div>
                    <div class="archive-item-body">
                        <p>${b.message}</p>
                    </div>
                </div>
            `;
        }).join("");
        container.innerHTML = html;
    }


    async loadFeedbacks() {
        const tbody = document.getElementById("feedbacks-table-body");
        if (!tbody) return;
        
        tbody.innerHTML = '<tr><td colspan="8" class="text-center" style="padding: 24px">Loading feedbacks...</td></tr>';
        
        try {
            const res = await fetch("/api/admin/feedbacks");
            const data = await res.json();
            
            if (data.success && data.feedbacks.length > 0) {
                tbody.innerHTML = data.feedbacks.map(f => `
                    <tr>
                        <td style="font-family: monospace; color: var(--text-muted)">#${f.id}</td>
                        <td>
                            <div style="font-weight: 500">${f.user_name || 'Anonymous'}</div>
                            <div style="font-size: 12px; color: var(--text-muted)">${f.user_email || 'No email'}</div>
                        </td>
                        <td><span class="badge" style="background: var(--bg-secondary)">${f.category}</span></td>
                        <td style="font-weight: 500">${f.subject}</td>
                        <td style="max-width: 300px; white-space: normal;">${f.message}</td>
                        <td>
                            ${f.media_path ? `<img src="${f.media_path}" class="feedback-media-img" style="max-height: 50px; border-radius: 4px; border: 1px solid var(--border-color); object-fit: cover; max-width: 80px; cursor: pointer;">` : '<span style="color: var(--text-muted); font-size: 12px">None</span>'}
                        </td>
                        <td style="white-space: nowrap; color: var(--text-muted)">
                            ${new Date(f.created_at).toLocaleString()}
                        </td>
                        <td>
                            <span class="badge" style="background: ${f.status === 'pending' ? 'var(--warning)' : 'var(--success)'}; color: white">
                                ${f.status.toUpperCase()}
                            </span>
                        </td>
                    </tr>
                `).join("");
            } else {
                tbody.innerHTML = '<tr><td colspan="8" class="text-center" style="padding: 24px; color: var(--text-muted)">No feedbacks submitted yet.</td></tr>';
            }
        } catch (e) {
            console.error("Error loading feedbacks:", e);
            tbody.innerHTML = '<tr><td colspan="8" class="text-center text-danger" style="padding: 24px">Error loading feedbacks. Please try again.</td></tr>';
        }
    }

    async updateAnalytics() {
        try {
            const res = await fetch("/api/admin/stats");
            const data = await res.json();
            if (data.success) {
                const s = data.stats;
                document.getElementById("stat-total-users").textContent = s.totalUsers || 0;
                document.getElementById("stat-active-responders").textContent = `${s.activeResponders || 0} / ${s.totalResponders || 0}`;
                document.getElementById("stat-total-sos").textContent = s.totalSOS || 0;
                
                // Calculate active incidents from local array since backend doesn't provide it
                const active = this.incidents.filter(i => {
                    const st = (i.status || '').toLowerCase();
                    return !['resolved', 'cancelled'].includes(st);
                }).length;
                document.getElementById("stat-active-incidents").textContent = `${active} Active`;
            }
        } catch (e) {
            console.warn("Analytics fetch failed:", e);
        }

        const counts = { 
            medical: 0, fire: 0, police: 0, barangay: 0,
            roadcrash: 0, report: 0
        };
        this.incidents.forEach(inc => {
            if (counts[inc.category] !== undefined) counts[inc.category]++;
        });

        const total = this.incidents.length || 1;
        Object.keys(counts).forEach(cat => {
            const pct = Math.round((counts[cat] / total) * 100);
            const bar = document.getElementById(`bar-${cat}`);
            const lbl = document.getElementById(`val-${cat}`);
            if (bar && lbl) {
                bar.style.width = `${pct}%`;
                lbl.textContent = counts[cat];
            }
        });

        const pieContainer = document.getElementById("incidents-pie-chart");
        if (pieContainer && window.Highcharts) {
            const categories = Object.keys(counts);
            const hasData = Object.values(counts).some(v => v > 0);
            const colors = ['#ef4444', '#f97316', '#3b82f6', '#10b981', '#8b5cf6', '#64748b'];
            
            let chartData = [];
            if (hasData) {
                chartData = categories.map((cat, index) => ({
                    name: cat.charAt(0).toUpperCase() + cat.slice(1),
                    y: counts[cat],
                    color: colors[index % colors.length]
                }));
            } else {
                chartData = [{ name: 'No Incidents', y: 1, color: '#334155' }];
            }

            if (this.pieChartInstance) {
                this.pieChartInstance.series[0].setData(chartData, true);
            } else {
                this.pieChartInstance = Highcharts.chart('incidents-pie-chart', {
                    chart: {
                        type: 'pie',
                        backgroundColor: 'transparent',
                        options3d: {
                            enabled: true,
                            alpha: 45,
                            beta: 0
                        }
                    },
                    title: {
                        text: 'Incident Reports by Category',
                        style: { color: '#1e293b', fontWeight: 'bold' }
                    },
                    subtitle: {
                        text: 'Distribution of reported incidents',
                        style: { color: '#64748b' }
                    },
                    accessibility: {
                        point: { valueSuffix: '%' }
                    },
                    tooltip: {
                        enabled: hasData,
                        pointFormat: '{series.name}: <b>{point.percentage:.1f}%</b> ({point.y})',
                        hideDelay: 100
                    },
                    plotOptions: {
                        pie: {
                            allowPointSelect: true,
                            cursor: 'pointer',
                            depth: 35,
                            dataLabels: {
                                enabled: hasData,
                                format: '<b>{point.name}</b><br>{point.percentage:.1f} %',
                                style: { color: '#1e293b', textOutline: 'none', fontWeight: '600' }
                            },
                            showInLegend: true,
                            point: {
                                events: {
                                    mouseOver: function() {
                                        if (hasData) this.slice(true, false, true);
                                    },
                                    mouseOut: function() {
                                        if (hasData) this.slice(false, false, true);
                                    }
                                }
                            }
                        }
                    },
                    legend: {
                        itemStyle: { color: '#64748b', fontWeight: 'normal' }
                    },
                    series: [{
                        name: 'Incidents',
                        colorByPoint: true,
                        data: chartData
                    }],
                    responsive: {
                        rules: [{
                            condition: {
                                maxWidth: 500
                            },
                            chartOptions: {
                                legend: {
                                    layout: 'horizontal',
                                    align: 'center',
                                    verticalAlign: 'bottom'
                                },
                                plotOptions: {
                                    pie: {
                                        dataLabels: {
                                            distance: -15,
                                            style: { fontSize: '10px' }
                                        }
                                    }
                                }
                            }
                        }, {
                            condition: {
                                minWidth: 501
                            },
                            chartOptions: {
                                legend: {
                                    layout: 'vertical',
                                    align: 'right',
                                    verticalAlign: 'middle'
                                }
                            }
                        }]
                    }
                });
            }
        }
    }

    /* Web Audio synthesizers */
    playAlertSound() {
        try {
            const ctx = new (window.AudioContext || window.webkitAudioContext)();
            const tone = (f, d, start) => {
                const osc = ctx.createOscillator();
                const gain = ctx.createGain();
                osc.type = 'triangle';
                osc.frequency.setValueAtTime(f, ctx.currentTime + start);
                gain.gain.setValueAtTime(0.0, ctx.currentTime + start);
                gain.gain.linearRampToValueAtTime(0.12, ctx.currentTime + start + 0.05);
                gain.gain.linearRampToValueAtTime(0.0, ctx.currentTime + start + d);
                
                osc.connect(gain);
                gain.connect(ctx.destination);
                osc.start(ctx.currentTime + start);
                osc.stop(ctx.currentTime + start + d);
            };
            tone(880, 0.2, 0);
            tone(1100, 0.2, 0.15);
        } catch (e) {}
    }

    playSuccessChime() {
        try {
            const ctx = new (window.AudioContext || window.webkitAudioContext)();
            const tone = (f, d, start) => {
                const osc = ctx.createOscillator();
                const gain = ctx.createGain();
                osc.type = 'sine';
                osc.frequency.setValueAtTime(f, ctx.currentTime + start);
                gain.gain.setValueAtTime(0.0, ctx.currentTime + start);
                gain.gain.linearRampToValueAtTime(0.1, ctx.currentTime + start + 0.05);
                gain.gain.linearRampToValueAtTime(0.0, ctx.currentTime + start + d);
                
                osc.connect(gain);
                gain.connect(ctx.destination);
                osc.start(ctx.currentTime + start);
                osc.stop(ctx.currentTime + start + d);
            };
            tone(523.25, 0.3, 0);
            tone(659.25, 0.3, 0.1);
            tone(783.99, 0.4, 0.2);
        } catch (e) {}
    }

    handleCallStatusUpdate(data) {
        const box = document.getElementById("incoming-call-box");
        const title = document.getElementById("incoming-call-title");
        const reporter = document.getElementById("incoming-call-reporter");
        const sub = document.getElementById("incoming-call-subtitle");
        const timer = document.getElementById("dash-call-timer");
        const acceptBtn = document.getElementById("btn-accept-dash-call");
        const declineBtn = document.getElementById("btn-decline-dash-call");

        if (data.status === 'ringing') {
            this.activeCallData = data;
            this.playAlertSound();
            title.textContent = data.type === 'video' ? 'Incoming Video Call' : 'Incoming Voice Call';
            reporter.textContent = `${data.reporter} (${data.phone})`;
            sub.textContent = 'Pozorrubio Emergency Link...';
            sub.className = "status-connecting";
            timer.classList.add("hidden");
            acceptBtn.classList.remove("hidden");
            declineBtn.innerHTML = '<i class="fa-solid fa-phone-slash"></i> Decline';
            box.classList.remove("hidden");
        } else if (data.status === 'connected') {
            sub.textContent = 'Connected (Secure Line)';
            sub.className = "status-connected";
            timer.classList.remove("hidden");
            acceptBtn.classList.add("hidden");
            declineBtn.innerHTML = '<i class="fa-solid fa-phone-slash"></i> Hang Up';

            // Start timer counting
            this.callDuration = 0;
            timer.textContent = "00:00";
            clearInterval(this.dashboardCallInterval);
            this.dashboardCallInterval = setInterval(() => {
                this.callDuration++;
                const mins = String(Math.floor(this.callDuration / 60)).padStart(2, '0');
                const secs = String(this.callDuration % 60).padStart(2, '0');
                timer.textContent = `${mins}:${secs}`;
            }, 1000);
        } else if (data.status === 'ended') {
            box.classList.add("hidden");
            clearInterval(this.dashboardCallInterval);
            this.activeCallData = null;
        }
    }

    acceptCall() {
        if (!this.activeCallData) return;
        this.playSuccessChime();
        this.socket.emit('citizen-call-status-change', {
            ...this.activeCallData,
            status: 'connected'
        });
    }

    declineCall() {
        if (!this.activeCallData) return;
        this.socket.emit('citizen-call-status-change', {
            ...this.activeCallData,
            status: 'ended'
        });
        document.getElementById("incoming-call-box").classList.add("hidden");
        clearInterval(this.dashboardCallInterval);
        this.activeCallData = null;
    }

    handleNewCheckin(data) {
        if (!this.map) return;

        this.playSuccessChime();

        // Plot green check-in marker on the map
        const checkinIcon = L.divIcon({
            className: 'checkin-gps-marker',
            html: '<div style="background-color:#10b981; border:2px solid #fff; border-radius:50%; width:16px; height:16px; box-shadow:0 0 8px rgba(16,185,129,0.8);"></div>',
            iconSize: [16, 16]
        });

        const time = new Date(data.timestamp).toLocaleTimeString();
        L.marker([data.lat, data.lng], { icon: checkinIcon })
            .bindPopup(`<b>Check-in Alert</b><br>${data.name}<br>Time: ${time}`)
            .addTo(this.map)
            .openPopup();

        // Append line to latency/activities terminal log
        const container = document.getElementById("latency-terminal-log");
        if (container) {
            const empty = container.querySelector(".empty-placeholder");
            if (empty) empty.remove();

            const line = document.createElement("div");
            line.className = "terminal-line term-low";
            line.innerHTML = `
                <span>[${time}] Check-in Signal: ${data.name}</span>
                <span>Active GPS: ${data.lat.toFixed(4)}, ${data.lng.toFixed(4)}</span>
            `;
            container.prepend(line);
        }
    }
    setMapType(type) {
        let newUrl = 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';
        if (type === "satellite") {
            newUrl = 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}';
        } else if (type === "terrain") {
            newUrl = 'https://mt1.google.com/vt/lyrs=p&x={x}&y={y}&z={z}';
        }
        this.mapTileLayer.setUrl(newUrl);
        localStorage.setItem("alerto_admin_map_type", type);
    }

    setupMapControls(savedType) {
        const btnLayers = document.getElementById("btn-map-layers");
        const panelMapType = document.getElementById("panel-map-type");
        const typeOptions = document.querySelectorAll(".map-type-option");

        // Sync UI with saved type
        if (savedType) {
            typeOptions.forEach(o => {
                if (o.getAttribute("data-type") === savedType) {
                    o.classList.add("active");
                } else {
                    o.classList.remove("active");
                }
            });
        }

        if (btnLayers && panelMapType) {
            btnLayers.addEventListener("click", (e) => {
                e.stopPropagation();
                panelMapType.classList.toggle("hidden");
            });

            document.addEventListener("click", (e) => {
                if (!panelMapType.contains(e.target) && e.target !== btnLayers) {
                    panelMapType.classList.add("hidden");
                }
            });
        }

        typeOptions.forEach(opt => {
            opt.addEventListener("click", () => {
                typeOptions.forEach(o => o.classList.remove("active"));
                opt.classList.add("active");
                
                const type = opt.getAttribute("data-type");
                this.setMapType(type);
                panelMapType.classList.add("hidden");
            });
        });
    }

    // ID Verifications Management
    async updatePendingIdCount() {
        const token = localStorage.getItem("alerto_admin_token");
        const badge = document.getElementById("badge-pending-id-count");
        if (!token || !badge) return;

        try {
            const res = await fetch("/api/admin/id-verifications?status=Pending", {
                headers: { "Authorization": `Bearer ${token}` }
            });
            const data = await res.json();
            if (data.success && Array.isArray(data.verifications)) {
                const count = data.verifications.length;
                if (count > 0) {
                    badge.textContent = count > 99 ? '99+' : count;
                    badge.style.display = 'inline-block';
                } else {
                    badge.style.display = 'none';
                }
            }
        } catch (e) {
            console.error("Failed to update pending ID count:", e);
        }
    }

    async loadIdVerifications() {
        const tbody = document.getElementById("id-verifications-table-body");
        const filterSelect = document.getElementById("id-verif-status-filter");
        const token = localStorage.getItem("alerto_admin_token");

        if (!tbody || !token) return;

        const statusFilter = filterSelect ? filterSelect.value : "Pending";
        tbody.innerHTML = `
            <tr>
                <td colspan="7" class="text-center" style="padding: 24px; color: var(--text-muted);">
                    <i class="fa-solid fa-spinner fa-spin" style="margin-right: 8px;"></i> Loading verification requests...
                </td>
            </tr>
        `;

        try {
            const queryParam = statusFilter && statusFilter !== "ALL" ? `?status=${encodeURIComponent(statusFilter)}` : "";
            const res = await fetch(`/api/admin/id-verifications${queryParam}`, {
                headers: { "Authorization": `Bearer ${token}` }
            });
            const data = await res.json();

            if (!data.success) {
                tbody.innerHTML = `
                    <tr>
                        <td colspan="7" class="text-center" style="padding: 24px; color: var(--danger);">
                            ${data.error || "Failed to load ID verifications."}
                        </td>
                    </tr>
                `;
                return;
            }

            this.idVerifications = data.verifications || [];

            if (this.idVerifications.length === 0) {
                const label = statusFilter === "ALL" ? "records" : `${statusFilter.toLowerCase()} submissions`;
                tbody.innerHTML = `
                    <tr>
                        <td colspan="7" class="text-center" style="padding: 32px; color: var(--text-muted);">
                            <i class="fa-solid fa-id-card" style="font-size: 28px; display: block; margin-bottom: 8px; opacity: 0.5;"></i>
                            No ${label} found.
                        </td>
                    </tr>
                `;
                return;
            }

            tbody.innerHTML = this.idVerifications.map(item => {
                const dateStr = item.submitted_at 
                    ? new Date(Number(item.submitted_at)).toLocaleString() 
                    : "Unknown";

                let statusPill = "";
                const normStatus = (item.status || "Pending").toLowerCase();
                if (normStatus === "approved") {
                    statusPill = `<span class="status-pill active" style="background:#dcfce7; color:#15803d; border-color:#bbf7d0;"><i class="fa-solid fa-circle-check"></i> Approved</span>`;
                } else if (normStatus === "rejected") {
                    statusPill = `<span class="status-pill" style="background:#fee2e2; color:#b91c1c; border-color:#fca5a5;"><i class="fa-solid fa-circle-xmark"></i> Rejected</span>`;
                } else {
                    statusPill = `<span class="status-pill warning" style="background:#fef3c7; color:#b45309; border-color:#fde68a;"><i class="fa-solid fa-clock"></i> Pending Review</span>`;
                }

                const userName = item.user_name || "Unknown Citizen";
                const phone = item.user_phone || "No phone";
                const email = item.user_email || "";
                const brgy = item.user_barangay ? `Brgy. ${item.user_barangay}` : "Not set";
                const idType = item.id_type || "Government ID";
                const userId = item.user_id;

                return `
                    <tr>
                        <td>
                            <strong style="color: var(--text-primary); display: block;">${userName}</strong>
                            <small style="color: var(--text-muted);">User ID #${userId}</small>
                        </td>
                        <td>
                            <div style="font-size: 13px;">${phone}</div>
                            ${email ? `<div style="font-size: 11px; color: var(--text-muted);">${email}</div>` : ""}
                        </td>
                        <td><span style="display: inline-block; padding: 2px 8px; background: rgba(0,0,0,0.05); border-radius: 4px; font-size: 12px;">${brgy}</span></td>
                        <td><span style="font-weight: 600; color: var(--text-primary); font-size: 12px;">${idType}</span></td>
                        <td style="font-size: 12px; color: var(--text-muted);">${dateStr}</td>
                        <td>${statusPill}</td>
                        <td style="text-align: center;">
                            <div style="display: flex; gap: 6px; justify-content: center; align-items: center; flex-wrap: wrap;">
                                <button class="btn btn-secondary btn-sm" onclick="dashOpenIdReview(${userId})" style="font-size: 11px; padding: 5px 10px; display: inline-flex; align-items: center; gap: 4px;">
                                    <i class="fa-solid fa-eye"></i> Review
                                </button>
                                ${normStatus === 'pending' ? `
                                    <button class="btn btn-sm" onclick="dashQuickApproveId(${userId})" style="font-size: 11px; padding: 5px 8px; background: #16a34a; color: white; border: none; border-radius: 6px; cursor: pointer; display: inline-flex; align-items: center; gap: 4px;" title="Approve ID">
                                        <i class="fa-solid fa-check"></i>
                                    </button>
                                    <button class="btn btn-sm" onclick="dashQuickRejectId(${userId})" style="font-size: 11px; padding: 5px 8px; background: #dc2626; color: white; border: none; border-radius: 6px; cursor: pointer; display: inline-flex; align-items: center; gap: 4px;" title="Reject ID">
                                        <i class="fa-solid fa-xmark"></i>
                                    </button>
                                ` : ''}
                            </div>
                        </td>
                    </tr>
                `;
            }).join("");

        } catch (e) {
            console.error("Failed to load ID verifications:", e);
            tbody.innerHTML = `
                <tr>
                    <td colspan="7" class="text-center" style="padding: 24px; color: var(--danger);">
                        Error loading ID verifications. Check network or server connection.
                    </td>
                </tr>
            `;
        }
    }

    openIdReviewModal(userId) {
        const item = (this.idVerifications || []).find(v => Number(v.user_id) === Number(userId));
        if (!item) {
            alert("ID verification record not found.");
            return;
        }

        const modal = document.getElementById("modal-id-review");
        const infoContainer = document.getElementById("id-review-user-info");
        const photosGrid = document.getElementById("id-photos-grid");
        const rejectContainer = document.getElementById("id-rejection-reason-container");
        const rejectInput = document.getElementById("id-rejection-reason-input");
        const actionsContainer = document.getElementById("id-review-actions");
        const token = localStorage.getItem("alerto_admin_token") || "";

        if (!modal || !infoContainer || !photosGrid || !actionsContainer) return;

        if (rejectContainer) rejectContainer.classList.add("hidden");
        if (rejectInput) rejectInput.value = item.rejection_reason || "";

        const dateStr = item.submitted_at ? new Date(Number(item.submitted_at)).toLocaleString() : "Unknown";
        const reviewedDateStr = item.reviewed_at ? new Date(Number(item.reviewed_at)).toLocaleString() : null;

        infoContainer.innerHTML = `
            <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 12px; font-size: 13px;">
                <div>
                    <span style="color: var(--text-muted); display: block; font-size: 11px; text-transform: uppercase;">Citizen Name</span>
                    <strong style="color: var(--text-primary); font-size: 15px;">${item.user_name || "Unknown"}</strong>
                    <div style="color: var(--text-muted); font-size: 12px;">User ID #${item.user_id}</div>
                </div>
                <div>
                    <span style="color: var(--text-muted); display: block; font-size: 11px; text-transform: uppercase;">Contact Info</span>
                    <div style="font-weight: 600; color: var(--text-primary);">${item.user_phone || "No phone"}</div>
                    <div style="color: var(--text-muted); font-size: 12px;">${item.user_email || "No email"}</div>
                </div>
                <div>
                    <span style="color: var(--text-muted); display: block; font-size: 11px; text-transform: uppercase;">Location & ID Type</span>
                    <div style="font-weight: 600; color: var(--text-primary);">${item.user_barangay ? 'Brgy. ' + item.user_barangay : 'Not set'}</div>
                    <div style="color: #ea580c; font-weight: 600; font-size: 12px;">${item.id_type || 'Government ID'}</div>
                </div>
                <div>
                    <span style="color: var(--text-muted); display: block; font-size: 11px; text-transform: uppercase;">Current Status</span>
                    <div style="margin-top: 4px;">
                        <span class="status-pill ${item.status === 'Approved' ? 'active' : (item.status === 'Rejected' ? '' : 'warning')}" style="padding: 3px 10px; font-size: 12px;">
                            ${item.status || 'Pending'}
                        </span>
                    </div>
                    <div style="color: var(--text-muted); font-size: 11px; margin-top: 4px;">Submitted: ${dateStr}</div>
                    ${reviewedDateStr ? `<div style="color: var(--text-muted); font-size: 11px;">Reviewed: ${reviewedDateStr}</div>` : ''}
                </div>
            </div>
            ${item.status === 'Rejected' && item.rejection_reason ? `
                <div style="margin-top: 12px; padding: 10px 14px; background: #fef2f2; border: 1px solid #fecaca; border-radius: 8px; font-size: 13px; color: #b91c1c;">
                    <strong>Previous Rejection Reason:</strong> ${item.rejection_reason}
                </div>
            ` : ''}
        `;

        const authSuffix = token ? `?token=${encodeURIComponent(token)}` : '';
        const frontSrc = item.front_image_path ? `${item.front_image_path}${authSuffix}` : '';
        const backSrc = item.back_image_path ? `${item.back_image_path}${authSuffix}` : '';

        photosGrid.innerHTML = `
            <div style="border: 1px solid var(--border-color); border-radius: 10px; padding: 12px; background: var(--bg-card); text-align: center;">
                <div style="font-weight: 700; font-size: 13px; margin-bottom: 8px; color: var(--text-primary); display: flex; align-items: center; justify-content: center; gap: 6px;">
                    <i class="fa-solid fa-address-card"></i> Front Side
                </div>
                ${frontSrc ? `
                    <div style="position: relative; overflow: hidden; border-radius: 8px; background: #0f172a; min-height: 220px; display: flex; align-items: center; justify-content: center;">
                        <img src="${frontSrc}" alt="Front ID" class="id-doc-preview-img" style="max-height: 240px; width: 100%; object-fit: contain; cursor: zoom-in; display: block;" onerror="this.onerror=null; this.src='/assets/placeholder-id.png';" />
                    </div>
                    <div style="margin-top: 8px;">
                        <a href="${frontSrc}" target="_blank" rel="noopener noreferrer" style="font-size: 12px; color: #2563eb; text-decoration: none;">
                            <i class="fa-solid fa-arrow-up-right-from-square"></i> Open in new tab
                        </a>
                    </div>
                ` : `<div style="padding: 40px; color: var(--text-muted);">No front photo provided</div>`}
            </div>

            <div style="border: 1px solid var(--border-color); border-radius: 10px; padding: 12px; background: var(--bg-card); text-align: center;">
                <div style="font-weight: 700; font-size: 13px; margin-bottom: 8px; color: var(--text-primary); display: flex; align-items: center; justify-content: center; gap: 6px;">
                    <i class="fa-solid fa-address-card"></i> Back Side
                </div>
                ${backSrc ? `
                    <div style="position: relative; overflow: hidden; border-radius: 8px; background: #0f172a; min-height: 220px; display: flex; align-items: center; justify-content: center;">
                        <img src="${backSrc}" alt="Back ID" class="id-doc-preview-img" style="max-height: 240px; width: 100%; object-fit: contain; cursor: zoom-in; display: block;" onerror="this.onerror=null; this.src='/assets/placeholder-id.png';" />
                    </div>
                    <div style="margin-top: 8px;">
                        <a href="${backSrc}" target="_blank" rel="noopener noreferrer" style="font-size: 12px; color: #2563eb; text-decoration: none;">
                            <i class="fa-solid fa-arrow-up-right-from-square"></i> Open in new tab
                        </a>
                    </div>
                ` : `<div style="padding: 40px; color: var(--text-muted);">No back photo provided</div>`}
            </div>
        `;

        actionsContainer.innerHTML = `
            <button class="btn btn-secondary" type="button" onclick="document.getElementById('modal-id-review').classList.add('hidden')">
                Close
            </button>
            <div style="display: flex; gap: 10px;">
                <button class="btn btn-danger" type="button" id="btn-modal-reject-id" style="background: #dc2626; color: white; border: none; padding: 9px 18px; border-radius: 8px; font-weight: 600; cursor: pointer; display: flex; align-items: center; gap: 6px;">
                    <i class="fa-solid fa-circle-xmark"></i> Reject ID
                </button>
                <button class="btn btn-primary" type="button" id="btn-modal-approve-id" style="background: #16a34a; color: white; border: none; padding: 9px 20px; border-radius: 8px; font-weight: 600; cursor: pointer; display: flex; align-items: center; gap: 6px;">
                    <i class="fa-solid fa-circle-check"></i> Approve & Verify ID
                </button>
            </div>
        `;

        document.getElementById("btn-modal-approve-id").addEventListener("click", () => {
            if (confirm(`Are you sure you want to approve and verify the ID of ${item.user_name || 'this citizen'}? They will be granted full access to the emergency network.`)) {
                this.submitIdReview(userId, 'approve');
            }
        });

        document.getElementById("btn-modal-reject-id").addEventListener("click", () => {
            if (rejectContainer.classList.contains("hidden")) {
                rejectContainer.classList.remove("hidden");
                rejectInput.focus();
                return;
            }
            const reason = rejectInput.value.trim();
            if (!reason) {
                alert("Please provide a reason for rejecting this ID so the citizen knows what to correct.");
                rejectInput.focus();
                return;
            }
            if (confirm(`Reject ID verification for ${item.user_name || 'this citizen'} with reason:\n"${reason}"?`)) {
                this.submitIdReview(userId, 'reject', reason);
            }
        });

        modal.classList.remove("hidden");
    }

    async submitIdReview(userId, action, reason) {
        const token = localStorage.getItem("alerto_admin_token");
        if (!token) {
            alert("Session expired. Please log in again.");
            return;
        }

        const endpoint = action === 'approve'
            ? `/api/admin/id-verifications/${userId}/approve`
            : `/api/admin/id-verifications/${userId}/reject`;

        const bodyData = action === 'reject' ? { rejectionReason: reason || "ID document rejected." } : {};

        try {
            const res = await fetch(endpoint, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "Authorization": `Bearer ${token}`
                },
                body: JSON.stringify(bodyData)
            });
            const data = await res.json();

            if (data.success) {
                const modal = document.getElementById("modal-id-review");
                if (modal) modal.classList.add("hidden");
                await this.updatePendingIdCount();
                await this.loadIdVerifications();
            } else {
                alert(data.error || `Failed to ${action} ID verification.`);
            }
        } catch (e) {
            console.error(`Error submitting ID review (${action}):`, e);
            alert(`Network error while trying to ${action} ID.`);
        }
    }

    promptRejectId(userId) {
        this.openIdReviewModal(userId);
        const rejectContainer = document.getElementById("id-rejection-reason-container");
        const rejectInput = document.getElementById("id-rejection-reason-input");
        if (rejectContainer && rejectInput) {
            rejectContainer.classList.remove("hidden");
            rejectInput.scrollIntoView({ behavior: 'smooth', block: 'center' });
            rejectInput.focus();
        }
    }

    // Weather Status Control Implementation
    async loadWeatherStatus() {
        try {
            const res = await fetch("/api/weather-status");
            const data = await res.json();
            if (data.success && data.weather) {
                this.updateWeatherUI(data.weather);
            }
        } catch (e) {
            console.error("Failed to load weather status:", e);
        }
    }

    updateWeatherUI(weather) {
        if (!weather) return;
        this.currentWeather = weather;

        const status = (weather.status || 'NORMAL').toUpperCase();
        const title = weather.title || (status + " WEATHER");
        const message = weather.message || "";
        const updatedByName = weather.updated_by_name || "MDRRMO Command Center";
        const dateStr = weather.updated_at ? new Date(Number(weather.updated_at)).toLocaleString() : "--:--:--";

        // 1. Update Header Badge
        const headerBadge = document.getElementById("header-weather-badge");
        const headerIcon = document.getElementById("header-weather-icon");
        const headerText = document.getElementById("header-weather-text");
        if (headerText && headerIcon) {
            headerText.textContent = `WEATHER: ${status}`;
            if (status === 'NORMAL') {
                headerIcon.className = "fa-solid fa-sun";
                headerIcon.style.color = "#f59e0b";
                if (headerBadge) {
                    headerBadge.style.borderColor = "#cbd5e1";
                    headerBadge.style.background = "var(--bg-card)";
                    headerBadge.style.color = "var(--text-primary)";
                }
            } else if (status === 'WARNING') {
                headerIcon.className = "fa-solid fa-cloud-bolt";
                headerIcon.style.color = "#3b82f6";
                if (headerBadge) {
                    headerBadge.style.borderColor = "#93c5fd";
                    headerBadge.style.background = "#eff6ff";
                    headerBadge.style.color = "#1d4ed8";
                }
            } else if (status === 'EXTREME') {
                headerIcon.className = "fa-solid fa-triangle-exclamation";
                headerIcon.style.color = "#ef4444";
                if (headerBadge) {
                    headerBadge.style.borderColor = "#fca5a5";
                    headerBadge.style.background = "#fef2f2";
                    headerBadge.style.color = "#dc2626";
                }
            }
        }

        // 2. Update Sidebar Nav Badge
        const navBadge = document.getElementById("badge-weather-nav-status");
        if (navBadge) {
            navBadge.textContent = status;
            if (status === 'NORMAL') {
                navBadge.style.background = "#16a34a";
            } else if (status === 'WARNING') {
                navBadge.style.background = "#2563eb";
            } else if (status === 'EXTREME') {
                navBadge.style.background = "#dc2626";
            }
        }

        // 3. Update Hero Card
        const heroTitle = document.getElementById("weather-hero-title");
        const heroMsg = document.getElementById("weather-hero-message");
        const heroTime = document.getElementById("weather-hero-time");
        const heroAdmin = document.getElementById("weather-hero-admin");
        const heroIconBox = document.getElementById("weather-hero-icon-box");
        const heroCard = document.getElementById("weather-hero-card");

        if (heroTitle) heroTitle.textContent = title;
        if (heroMsg) heroMsg.textContent = message;
        if (heroTime) heroTime.textContent = dateStr;
        if (heroAdmin) heroAdmin.textContent = updatedByName;

        if (heroCard && heroIconBox) {
            if (status === 'NORMAL') {
                heroCard.style.borderColor = "#22c55e";
                heroIconBox.innerHTML = '<i class="fa-solid fa-sun" style="color: #f59e0b;"></i>';
                heroIconBox.style.background = "#fef3c7";
                if (heroMsg) heroMsg.style.borderLeftColor = "#16a34a";
            } else if (status === 'WARNING') {
                heroCard.style.borderColor = "#2563eb";
                heroIconBox.innerHTML = '<i class="fa-solid fa-cloud-bolt" style="color: #1d4ed8;"></i>';
                heroIconBox.style.background = "#dbeafe";
                if (heroMsg) heroMsg.style.borderLeftColor = "#1d4ed8";
            } else if (status === 'EXTREME') {
                heroCard.style.borderColor = "#dc2626";
                heroIconBox.innerHTML = '<i class="fa-solid fa-triangle-exclamation" style="color: #dc2626;"></i>';
                heroIconBox.style.background = "#fee2e2";
                if (heroMsg) heroMsg.style.borderLeftColor = "#dc2626";
            }
        }

        // 4. Update the 3 Push Buttons Active States
        const btnNormal = document.getElementById("btn-weather-normal");
        const btnWarning = document.getElementById("btn-weather-warning");
        const btnExtreme = document.getElementById("btn-weather-extreme");

        const badgeNormal = document.getElementById("badge-btn-normal");
        const badgeWarning = document.getElementById("badge-btn-warning");
        const badgeExtreme = document.getElementById("badge-btn-extreme");

        if (btnNormal && btnWarning && btnExtreme) {
            // Reset active styles
            btnNormal.style.outline = "none";
            btnNormal.style.boxShadow = "0 4px 15px rgba(0,0,0,0.06)";
            if (badgeNormal) badgeNormal.classList.add("hidden");

            btnWarning.style.outline = "none";
            btnWarning.style.boxShadow = "0 4px 15px rgba(29, 78, 216, 0.25)";
            if (badgeWarning) badgeWarning.classList.add("hidden");

            btnExtreme.style.outline = "none";
            btnExtreme.style.boxShadow = "0 4px 15px rgba(220, 38, 38, 0.3)";
            if (badgeExtreme) badgeExtreme.classList.add("hidden");

            if (status === 'NORMAL') {
                btnNormal.style.outline = "4px solid #16a34a";
                btnNormal.style.boxShadow = "0 0 25px rgba(22, 163, 74, 0.45)";
                if (badgeNormal) badgeNormal.classList.remove("hidden");
            } else if (status === 'WARNING') {
                btnWarning.style.outline = "4px solid #facc15";
                btnWarning.style.boxShadow = "0 0 25px rgba(37, 99, 235, 0.6)";
                if (badgeWarning) badgeWarning.classList.remove("hidden");
            } else if (status === 'EXTREME') {
                btnExtreme.style.outline = "4px solid #facc15";
                btnExtreme.style.boxShadow = "0 0 30px rgba(220, 38, 38, 0.7)";
                if (badgeExtreme) badgeExtreme.classList.remove("hidden");
            }
        }
    }

    promptWeatherChange(targetStatus) {
        if (this.user.type !== 'mdrrmo_admin' && this.user.type !== 'authority') {
            alert("Permission Denied: Only authorized MDRRMO Command Center administrators can change the town weather status.");
            return;
        }

        const modal = document.getElementById("modal-weather-confirm");
        const prevCard = document.getElementById("weather-confirm-preview-card");
        const iconBox = document.getElementById("weather-confirm-icon-box");
        const titleEl = document.getElementById("weather-confirm-title");
        const msgEl = document.getElementById("weather-confirm-message");
        const submitBtn = document.getElementById("btn-weather-confirm-submit");

        if (!modal || !prevCard || !submitBtn) return;

        let title = "NORMAL WEATHER";
        let message = "Current weather conditions are normal. Continue monitoring official announcements.";
        let iconHtml = '<i class="fa-solid fa-sun" style="color: #d97706;"></i>';
        let cardBg = "#ffffff";
        let cardBorder = "#16a34a";
        let textColor = "#0f172a";
        let btnBg = "#16a34a";

        if (targetStatus === 'WARNING') {
            title = "WEATHER WARNING";
            message = "Weather warning is currently in effect in Pozorrubio. Please stay alert and take necessary precautions.";
            iconHtml = '<i class="fa-solid fa-cloud-bolt" style="color: #ffffff;"></i>';
            cardBg = "#1d4ed8";
            cardBorder = "#1e40af";
            textColor = "#ffffff";
            btnBg = "#1d4ed8";
        } else if (targetStatus === 'EXTREME') {
            title = "EXTREME WEATHER WARNING";
            message = "Extreme weather warning is currently in effect in Pozorrubio. Stay safe and follow official instructions from the MDRRMO.";
            iconHtml = '<i class="fa-solid fa-triangle-exclamation" style="color: #ffffff;"></i>';
            cardBg = "#dc2626";
            cardBorder = "#991b1b";
            textColor = "#ffffff";
            btnBg = "#dc2626";
        }

        prevCard.style.background = cardBg;
        prevCard.style.borderColor = cardBorder;
        prevCard.style.color = textColor;
        iconBox.innerHTML = iconHtml;
        iconBox.style.background = targetStatus === 'NORMAL' ? '#fef3c7' : 'rgba(255,255,255,0.2)';
        titleEl.textContent = title;
        msgEl.textContent = message;
        submitBtn.style.background = btnBg;

        // Clone/rebind submit listener to avoid duplicate clicks
        const newSubmitBtn = submitBtn.cloneNode(true);
        submitBtn.parentNode.replaceChild(newSubmitBtn, submitBtn);

        newSubmitBtn.addEventListener("click", () => {
            this.submitWeatherChange(targetStatus);
        });

        modal.classList.remove("hidden");
    }

    async submitWeatherChange(targetStatus) {
        const modal = document.getElementById("modal-weather-confirm");
        const token = localStorage.getItem("alerto_admin_token");
        const alertBox = document.getElementById("weather-alert-box");
        const alertMsg = document.getElementById("weather-alert-msg");
        const alertIcon = document.getElementById("weather-alert-icon");

        if (modal) modal.classList.add("hidden");

        if (!token) {
            alert("Session expired. Please sign in again.");
            return;
        }

        try {
            const res = await fetch("/api/admin/weather-status", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "Authorization": `Bearer ${token}`
                },
                body: JSON.stringify({ status: targetStatus })
            });

            const data = await res.json();

            if (data.success && data.weather) {
                this.updateWeatherUI(data.weather);
                this.loadWeatherHistory();

                if (alertBox && alertMsg && alertIcon) {
                    alertBox.className = "";
                    alertBox.style.background = "#dcfce7";
                    alertBox.style.color = "#15803d";
                    alertBox.style.border = "1px solid #bbf7d0";
                    alertIcon.className = "fa-solid fa-circle-check";
                    alertMsg.textContent = `Success: Municipal weather status changed to "${data.weather.title}". All citizen dashboards updated in real time.`;
                    alertBox.classList.remove("hidden");
                    setTimeout(() => { if (alertBox) alertBox.classList.add("hidden"); }, 8000);
                }
            } else {
                if (alertBox && alertMsg && alertIcon) {
                    alertBox.className = "";
                    alertBox.style.background = "#fee2e2";
                    alertBox.style.color = "#b91c1c";
                    alertBox.style.border = "1px solid #fecaca";
                    alertIcon.className = "fa-solid fa-triangle-exclamation";
                    alertMsg.textContent = data.error || "Failed to update weather status.";
                    alertBox.classList.remove("hidden");
                }
            }
        } catch (e) {
            console.error("Error submitting weather status change:", e);
            alert("Network error: Could not reach server to change weather status.");
        }
    }

    async loadWeatherHistory() {
        const tbody = document.getElementById("weather-history-table-body");
        const token = localStorage.getItem("alerto_admin_token");
        if (!tbody) return;

        try {
            const res = await fetch("/api/admin/weather-status/history", {
                headers: { "Authorization": `Bearer ${token}` }
            });
            const data = await res.json();

            if (data.success && Array.isArray(data.history)) {
                if (data.history.length === 0) {
                    tbody.innerHTML = `
                        <tr>
                            <td colspan="4" class="text-center" style="padding: 24px; color: var(--text-muted);">
                                No weather status changes recorded yet.
                            </td>
                        </tr>
                    `;
                    return;
                }

                tbody.innerHTML = data.history.map(item => {
                    const dateStr = item.created_at ? new Date(Number(item.created_at)).toLocaleString() : "Unknown";
                    const statusBadge = item.status === 'NORMAL'
                        ? `<span class="status-pill active" style="background:#dcfce7; color:#15803d; border-color:#bbf7d0; font-size:11px;">NORMAL</span>`
                        : (item.status === 'WARNING'
                            ? `<span class="status-pill warning" style="background:#dbeafe; color:#1d4ed8; border-color:#bfdbfe; font-size:11px;">WARNING</span>`
                            : `<span class="status-pill" style="background:#fee2e2; color:#dc2626; border-color:#fca5a5; font-size:11px;">EXTREME</span>`);

                    const prevBadge = item.previous_status
                        ? `<span style="font-size:11px; color:var(--text-muted); text-transform:uppercase;">${item.previous_status}</span>`
                        : `<span style="color:var(--text-muted); font-size:11px;">Initial</span>`;

                    return `
                        <tr>
                            <td style="color:var(--text-primary); font-weight:600;">${dateStr}</td>
                            <td>${statusBadge}</td>
                            <td>${prevBadge}</td>
                            <td style="color:var(--text-primary);">${item.updated_by_name || 'MDRRMO Officer'}</td>
                        </tr>
                    `;
                }).join("");
            }
        } catch (e) {
            console.error("Failed to load weather history:", e);
            if (tbody) {
                tbody.innerHTML = `<tr><td colspan="4" class="text-center" style="padding: 20px; color: var(--danger);">Failed to load history.</td></tr>`;
            }
        }
    }

    handleWeatherUpdate(data) {
        this.updateWeatherUI(data);
        const activeTab = document.querySelector(".sidebar-nav .nav-btn.active");
        if (activeTab && activeTab.getAttribute("data-tab") === "weather_control") {
            this.loadWeatherHistory();
        }
    }
}

let commandDashboard;
document.addEventListener("DOMContentLoaded", () => {
    // Always require login (no automatic login via localStorage)
    localStorage.removeItem("alerto_admin_auth"); // Clear just in case
    initAuthGateway();
});

function initAuthGateway() {
    const loginForm = document.getElementById("auth-login-form");
    const authError = document.getElementById("auth-error");

    loginForm.addEventListener("submit", async (e) => {
        e.preventDefault();
        const username = document.getElementById("auth-id").value;
        const password = document.getElementById("auth-pass").value;
        const btn = loginForm.querySelector("button");

        try {
            btn.textContent = "Authenticating...";
            authError.classList.add("hidden");
            const res = await fetch("/api/auth/admin-login", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ username, password })
            });
            const data = await res.json();
            
            if (data.success && (["mdrrmo_admin", "bfp_admin", "pnp_admin", "barangay_admin", "authority"].includes(data.user.type))) {
                localStorage.setItem("alerto_admin_auth", JSON.stringify(data.user));
                if (data.token) localStorage.setItem("alerto_admin_token", data.token);
                
                // Set Header based on role
                const dashTitle = document.querySelector(".branding-text h1");
                const dashSub = document.querySelector(".branding-text .subtext");
                if (data.user.type === 'bfp_admin') dashSub.textContent = "BFP Emergency Panel";
                if (data.user.type === 'pnp_admin') dashSub.textContent = "PNP Emergency Panel";
                if (data.user.type === 'barangay_admin') {
                    dashSub.textContent = `Barangay ${data.user.barangay} Panel`;
                    // Hide Responders and Broadcasts tab
                    const respondersTab = document.querySelector(".nav-btn[data-tab='responders']");
                    const broadcastTab = document.getElementById("nav-btn-broadcast");
                    if (respondersTab) respondersTab.style.display = 'none';
                    if (broadcastTab) broadcastTab.style.display = 'none';
                    
                    // Show Barangay Assist button
                    const brgyBtn = document.getElementById("nav-btn-brgy-assist");
                    if (brgyBtn) brgyBtn.classList.remove("hidden");

                    // Rename Incident Logs tab to Emergency Reports for Barangay Account
                    const logsTab = document.querySelector(".nav-btn[data-tab='logs']");
                    if (logsTab) {
                        logsTab.innerHTML = `<i class="fa-solid fa-file-shield"></i> Emergency Reports`;
                    }
                    const logsHeading = document.querySelector("#pane-logs .pane-header h3");
                    if (logsHeading) {
                        logsHeading.textContent = `Barangay ${data.user.barangay} Emergency Reports`;
                    }
                } else if (data.user.type === 'mdrrmo_admin') {
                    // Show Barangay Requests button for MDRRMO
                    const reqsBtn = document.getElementById("nav-btn-assistance-reqs");
                    if (reqsBtn) reqsBtn.classList.remove("hidden");
                } else if (data.user.type === 'bfp_admin' || data.user.type === 'pnp_admin') {
                    const broadcastTab = document.getElementById("nav-btn-broadcast");
                    if (broadcastTab) broadcastTab.style.display = 'none';
                }

                // Weather control permissions
                if (data.user.type !== 'mdrrmo_admin' && data.user.type !== 'authority') {
                    const banner = document.getElementById("weather-unauthorized-banner");
                    if (banner) banner.classList.remove("hidden");
                    const btns = document.querySelectorAll(".weather-push-btn");
                    btns.forEach(b => {
                        b.disabled = true;
                        b.style.opacity = "0.55";
                        b.style.cursor = "not-allowed";
                        b.title = "Restricted to MDRRMO Command Center";
                    });
                } else {
                    const banner = document.getElementById("weather-unauthorized-banner");
                    if (banner) banner.classList.add("hidden");
                    const btns = document.querySelectorAll(".weather-push-btn");
                    btns.forEach(b => {
                        b.disabled = false;
                        b.style.opacity = "1";
                        b.style.cursor = "pointer";
                        b.title = "";
                    });
                }

                // Hide gateway and show dashboard
                document.getElementById("auth-gateway").classList.add("hidden");
                document.getElementById("dash-header").style.display = "flex";
                document.getElementById("dash-main").style.display = "grid";
                
                // Initialize dashboard components
                commandDashboard = new CommandDashboard(data.user);
                window.commandDashboard = commandDashboard;
            } else {
                authError.textContent = data.error || "Authentication failed.";
                authError.classList.remove("hidden");
            }
        } catch (err) {
            authError.textContent = "Network error. Is server running?";
            authError.classList.remove("hidden");
        } finally {
            btn.textContent = "Sign In";
        }
    });
}
// Global Lightbox Logic (Admin Side)
document.addEventListener("click", (e) => {
    const lightbox = document.getElementById("media-lightbox");
    const lightboxContainer = document.getElementById("lightbox-content-container");
    const lightboxClose = document.getElementById("lightbox-close");

    if (!lightbox || !lightboxContainer || !lightboxClose) return;

    if (e.target === lightboxClose || e.target === lightbox) {
        lightbox.classList.add("hidden");
        lightboxContainer.innerHTML = "";
        return;
    }

    if (e.target.tagName === "IMG" && (e.target.closest(".chat-bubble") || e.target.classList.contains("feedback-media-img") || e.target.classList.contains("id-doc-preview-img"))) {
        const img = document.createElement("img");
        img.src = e.target.src;
        lightboxContainer.innerHTML = "";
        lightboxContainer.appendChild(img);
        lightbox.classList.remove("hidden");
    } else if (e.target.tagName === "VIDEO" && e.target.closest(".chat-bubble")) {
        const video = document.createElement("video");
        video.src = e.target.src;
        video.controls = true;
        video.autoplay = true;
        lightboxContainer.innerHTML = "";
        lightboxContainer.appendChild(video);
        lightbox.classList.remove("hidden");
    }
});


