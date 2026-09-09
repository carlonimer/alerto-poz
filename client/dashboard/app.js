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
            });
        });

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
            
            const type = file.type.startsWith("image/") ? "image" : "video";
            const fd = new FormData();
            fd.append('senderId', this.activeUser ? this.activeUser.id : 'ADMIN');
            fd.append('senderRole', 'Command Center');
            fd.append('messageType', type);
            fd.append('media', file);
            
            try {
                const res = await fetch(`/api/incidents/${this.selectedIncident.id}/messages`, { method: "POST", body: fd });
                if (!res.ok) throw new Error("Upload Failed");
            } catch (err) {
                console.error("Media upload error:", err);
            }
            
            e.target.value = "";
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

        // Auto-refresh analytics every 10 seconds
        setInterval(() => this.updateAnalytics(), 10000);
    }

    initSocket() {
        // Handle VS Code Live Server testing ports
        const socketUrl = (window.location.port === '5500' || window.location.port === '5501') 
            ? 'http://localhost:3000' 
            : '';
        this.socket = io(socketUrl);
        
        this.socket.on('connect', () => {
            this.updateNetworkUI(true);
        });
        
        this.socket.on('disconnect', () => {
            this.updateNetworkUI(false);
        });

        // Load initial state database from backend server
        this.socket.on('init-state', (db) => {
            this.incidents = db.incidents;

            this.responders = db.responders;
            this.broadcasts = db.broadcasts;
            this.rescue_vehicles = db.rescue_vehicles || [];
            this.water_devices = db.water_devices || [];
            
            this.renderAll();
        });

        // Live report event
        this.socket.on('new-incident-alert', (report) => {
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
                const feed = document.getElementById("dispatcher-chat-feed");
                if (feed) {
                    const firstName = this.selectedIncident.reporter ? this.selectedIncident.reporter.split(' ')[0] : 'Citizen';
                    const isAdmin = msg.sender_role !== 'Citizen App';
                    const senderName = isAdmin ? 'ALERTOPOZ' : firstName;
                    const bubbleClass = isAdmin ? 'chat-outgoing' : 'chat-incoming';
                    
                    const avatarHtml = isAdmin ? '' : this.getAvatarHtml(msg.sender_profile_image, msg.sender_gender);

                    let tsHtml = '';
                    if (msg.timestamp) {
                        const d = new Date(Number(msg.timestamp));
                        if (!isNaN(d)) {
                            tsHtml = `<div style="font-size: 10px; opacity: 0.7; text-align: ${isAdmin ? 'right' : 'left'}; margin-top: 6px;">${d.toLocaleDateString('en-US', {month: 'short', day: '2-digit', year: 'numeric'})} &bull; ${d.toLocaleTimeString('en-US', {hour: '2-digit', minute: '2-digit'})}</div>`;
                        }
                    }

                    let msgHtml = '';
                    if (msg.message_type === 'text' && msg.message_content) {
                        msgHtml = `<div class="chat-bubble ${bubbleClass}">${msg.message_content}${tsHtml}</div>`;
                    } else if (msg.message_type === 'image' && msg.media_url) {
                        const styleOverride = 'background: transparent; padding: 0; box-shadow: none;';
                        const mt = '0';
                        msgHtml = `<div class="chat-bubble ${bubbleClass}" style="${styleOverride}"><img src="${msg.media_url}" style="max-width: 280px; max-height: 250px; border-radius: 8px; margin-top: ${mt}; display: block;">${tsHtml}</div>`;
                    } else if (msg.message_type === 'video' && msg.media_url) {
                        const styleOverride = 'background: transparent; padding: 0; box-shadow: none;';
                        const mt = '0';
                        msgHtml = `<div class="chat-bubble ${bubbleClass}" style="${styleOverride}"><video src="${msg.media_url}" style="max-width: 280px; max-height: 250px; border-radius: 8px; margin-top: ${mt}; display: block;" controls autoplay muted loop></video>${tsHtml}</div>`;
                    }

                    if (msgHtml) {
                        if (isAdmin) {
                            feed.innerHTML += msgHtml;
                        } else {
                            feed.innerHTML += `
                                <div style="display: flex; gap: 4px; align-items: flex-start; align-self: flex-start; margin-top: 12px;">
                                    <div>${avatarHtml}</div>
                                    <div style="display: flex; flex-direction: column; align-items: flex-start;">
                                        <span style="font-size: 14px; color: var(--text-primary); font-weight: 700; margin-bottom: 0px; margin-left: 2px;">${senderName}</span>
                                        ${msgHtml.replace('margin-top: 12px;', 'margin-top: 0;')}
                                    </div>
                                </div>
                            `;
                        }
                    }
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
            const idx = this.incidents.findIndex(i => i.id === incident.id);
            if (idx !== -1) {
                this.incidents[idx] = incident;
                this.renderLogsTable();
                this.renderHistoryRecords();
                this.updateAnalytics();
                
                // Update marker color if enroute/resolved
                if (incident.status === 'resolved' || incident.status === 'cancelled') {
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
                            if (incident.status === 'pending' || incident.status === 'new') {
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
                
                // Chat auto-update
                if (this.selectedIncident && this.selectedIncident.id === incident.id && incident.status !== 'resolved') {
                    this.selectedIncident = incident;
                    this.renderDispatcherChat(incident);
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
            .bindPopup(`<b>${inc.category.toUpperCase()} INCIDENT</b><br>${inc.details}${manageBtnHTML}`);
            
        if (this.selectedIncident) {
            if (this.selectedIncident.id === inc.id) {
                marker.addTo(this.map);
            }
        } else {
            if (inc.status === 'pending' || inc.status === 'new') {
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
        
        detailsContainer.innerHTML = `
            <div class="incident-summary-card">
                <div class="summary-row">
                    <span class="summary-label">Incident ID:</span>
                    <span class="summary-val font-mono">${inc.id}</span>
                </div>
                <div class="summary-row">
                    <span class="summary-label">Category:</span>
                    <span class="summary-val uppercase">${inc.category}</span>
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
                    
                    fetch(`https://nominatim.openstreetmap.org/reverse?format=json&lat=${inc.lat}&lon=${inc.lng}`)
                        .then(res => res.json())
                        .then(data => {
                            const address = data.display_name || "Unknown Location";
                            marker.bindPopup(`
                                <div style="max-width: 250px; white-space: normal; text-align: center; font-family: 'Inter', sans-serif; padding: 5px;">
                                    <div style="background: #eef2ff; color: #4f46e5; padding: 4px 8px; border-radius: 4px; font-size: 10px; font-weight: 800; display: inline-block; margin-bottom: 6px; text-transform: uppercase;">User Location Detected</div><br>
                                    <span style="font-size: 12px; font-weight: 600; color: #1e293b;">${address}</span>
                                </div>
                            `, {
                                offset: [0, -32],
                                closeButton: false
                            }).openPopup();
                        })
                        .catch(err => {
                            console.error("Reverse geocoding failed", err);
                        });
                }
            }
        }, 150);
    }

    getAvatarHtml(profileImage, gender, size = 32) {
        if (profileImage && profileImage.trim() !== '') {
            const url = profileImage.startsWith('http') ? profileImage : profileImage;
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

    async renderDispatcherChat(inc) {
        const chatContainer = document.getElementById("dispatcher-chat-container");
        const chatFeed = document.getElementById("dispatcher-chat-feed");
        const commsActions = document.getElementById("admin-comms-actions");
        
        if (inc.status === 'resolved' || inc.status === 'cancelled') {
            chatContainer.style.display = "none";
            commsActions.style.display = "none";
            return;
        }

        chatContainer.style.display = "flex";
        commsActions.style.display = "flex";
        
        let newFeedHtml = "";

        const firstName = inc.reporter ? inc.reporter.split(' ')[0] : 'Citizen';
        const defaultAvatarHtml = this.getAvatarHtml(inc.profile_image, inc.gender, 32);

        // Parse legacy details
        const notesArr = (inc.details || "").split(" | ");
        const baseDetails = notesArr[0] || "";
        
        // System initial message
        if (baseDetails) {
            newFeedHtml += `<div class="chat-bubble chat-incoming"><strong>System:</strong> SOS Received. Details: ${baseDetails}</div>`;
        }
        
        let chatMessages = [];
        
        // Fetch new messages from API
        if (inc.id && !inc.id.startsWith("DRAFT-")) {
            try {
                const response = await fetch(`/api/incidents/${inc.id}/messages`);
                if (response.ok) {
                    const data = await response.json();
                    if (data.success && data.messages && data.messages.length > 0) {
                        chatMessages = data.messages;
                        data.messages.forEach(msg => {
                            const isAdmin = msg.sender_role !== 'Citizen App';
                            const senderName = isAdmin ? 'ALERTOPOZ' : firstName;
                            const bubbleClass = isAdmin ? 'chat-outgoing' : 'chat-incoming';
                            
                            const avatarHtml = isAdmin ? '' : this.getAvatarHtml(msg.sender_profile_image || inc.profile_image, msg.sender_gender || inc.gender, 32);

                            let tsHtml = '';
                            if (msg.timestamp) {
                                const d = new Date(Number(msg.timestamp));
                                if (!isNaN(d)) {
                                    tsHtml = `<div style="font-size: 10px; opacity: 0.7; text-align: ${isAdmin ? 'right' : 'left'}; margin-top: 6px;">${d.toLocaleDateString('en-US', {month: 'short', day: '2-digit', year: 'numeric'})} &bull; ${d.toLocaleTimeString('en-US', {hour: '2-digit', minute: '2-digit'})}</div>`;
                                }
                            }

                            let msgHtml = '';
                            if (msg.message_type === 'text' && msg.message_content) {
                                msgHtml = `<div class="chat-bubble ${bubbleClass}">${msg.message_content}${tsHtml}</div>`;
                            } else if (msg.message_type === 'image' && msg.media_url) {
                                const styleOverride = 'background: transparent; padding: 0; box-shadow: none;';
                                const mt = '0';
                                msgHtml = `<div class="chat-bubble ${bubbleClass}" style="${styleOverride}"><img src="${msg.media_url}" style="max-width: 280px; max-height: 250px; border-radius: 8px; margin-top: ${mt}; display: block;">${tsHtml}</div>`;
                            } else if (msg.message_type === 'video' && msg.media_url) {
                                const styleOverride = 'background: transparent; padding: 0; box-shadow: none;';
                                const mt = '0';
                                msgHtml = `<div class="chat-bubble ${bubbleClass}" style="${styleOverride}"><video src="${msg.media_url}" style="max-width: 280px; max-height: 250px; border-radius: 8px; margin-top: ${mt}; display: block;" controls autoplay muted loop></video>${tsHtml}</div>`;
                            }

                            if (msgHtml) {
                                if (isAdmin) {
                                    newFeedHtml += msgHtml;
                                } else {
                                    newFeedHtml += `
                                        <div style="display: flex; gap: 4px; align-items: flex-start; align-self: flex-start; margin-top: 12px;">
                                            <div>${avatarHtml}</div>
                                            <div style="display: flex; flex-direction: column; align-items: flex-start;">
                                                <span style="font-size: 14px; color: var(--text-primary); font-weight: 700; margin-bottom: 0px; margin-left: 2px;">${senderName}</span>
                                                ${msgHtml.replace('margin-top: 12px;', 'margin-top: 0;')}
                                            </div>
                                        </div>
                                    `;
                                }
                            }
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
                    newFeedHtml += `<div class="chat-bubble chat-outgoing">${text}</div>`;
                } else {
                    const msgHtml = `<div class="chat-bubble chat-incoming">${text}</div>`;
                    newFeedHtml += `
                        <div style="display: flex; gap: 4px; align-items: flex-start; align-self: flex-start; margin-top: 12px;">
                            <div>${defaultAvatarHtml}</div>
                            <div style="display: flex; flex-direction: column; align-items: flex-start;">
                                <span style="font-size: 14px; color: var(--text-primary); font-weight: 700; margin-bottom: 0px; margin-left: 2px;">${firstName}</span>
                                ${msgHtml.replace('margin-top: 12px;', 'margin-top: 0;')}
                            </div>
                        </div>
                    `;
                }
            }
        }
        
        chatFeed.innerHTML = newFeedHtml;
        chatFeed.scrollTo({ top: chatFeed.scrollHeight, behavior: 'smooth' });
    }

    async sendDispatcherChat() {
        if (!this.selectedIncident) return;
        const input = document.getElementById("admin-chat-input");
        const msg = input.value.trim();
        if (!msg) return;

        input.value = "";
        
        const fd = new FormData();
        fd.append('senderId', this.activeUser ? this.activeUser.id : 'ADMIN');
        fd.append('senderRole', 'Command Center');
        fd.append('messageType', 'text');
        fd.append('messageContent', msg);
        
        try {
            await fetch(`/api/incidents/${this.selectedIncident.id}/messages`, {
                method: 'POST',
                body: fd
            });
        } catch (err) {
            console.error("Failed to send text message", err);
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
        
        this.statusSelector.value = this.selectedIncident.status || 'Draft';
        this.statusSelector.disabled = false;
        
        this.unitSelector.innerHTML = '<option value="">-- Select Available Personnel/Unit --</option>';
        this.vehicleSelector.innerHTML = '<option value="">-- Select Available Vehicle --</option>';
        
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
        
        availableUnits.forEach((r, index) => {
            const isFireMatch = this.selectedIncident.category === "fire" && r.type === "fire";
            const isMedicalMatch = this.selectedIncident.category === "medical" && r.type === "medical";
            const isPoliceMatch = this.selectedIncident.category === "police" && r.type === "police";
            const isGeneralMatch = this.selectedIncident.category === "roadside" || this.selectedIncident.category === "report" || this.selectedIncident.category === "barangay";
            
            const isRecommended = isFireMatch || isMedicalMatch || isPoliceMatch || isGeneralMatch;
            
            const opt = document.createElement("option");
            opt.value = r.id;
            opt.textContent = `${r.name} [${r.type.toUpperCase()}]${index === 0 && isRecommended ? " (Closest)" : ""}`;
            
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
                assignedVehicle: vehicleId
            };
            
            if (status === 'dispatching' && unitId) {
                payload.responseProgress = 'en_route';
            } else if (status === 'resolved') {
                payload.responseProgress = null; // Clear on resolve
            }
            
            await fetch(`/api/incidents/${this.selectedIncident.id}`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            });
            alert('Incident updated successfully.');
            
            if (unitId && status === 'dispatching') {
                const unit = this.responders.find(r => r.id === unitId);
                if (unit) this.streamVehicleGPS(unit, this.selectedIncident);
            }
        } catch(e) {
            console.error(e);
            alert('Failed to update incident.');
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

            const badgeColor = inc.status === 'resolved' ? 'var(--success)' : 
                               inc.status === 'cancelled' ? 'var(--text-muted)' : 
                               inc.status === 'draft' ? 'var(--warning)' : 'var(--info)';

            html += `
                <tr class="${inc.status === 'new' ? 'new-incident-row' : ''}">
                    <td style="font-size: 13px;">${inc.id}</td>
                    <td style="font-size: 13px;">${time}</td>
                    <td>
                        <div style="display: flex; align-items: center; gap: 8px;">
                            ${this.getAvatarHtml(inc.profile_image, inc.gender, 24)}
                            <div>
                                <b style="color: var(--text-primary); font-size: 13px;">${inc.reporter || 'Unknown'}</b><br>
                                <span style="font-size:11px; color:var(--text-muted);">${inc.reporterPhone || 'Unknown'}</span>
                            </div>
                        </div>
                    </td>
                    <td class="capitalize" style="font-size: 13px;">${inc.type || inc.category || 'Unknown'}</td>
                    <td class="font-mono" style="font-size: 13px; color: var(--text-secondary);">${inc.lat.toFixed(4)}, ${inc.lng.toFixed(4)}</td>
                    <td style="font-size: 13px;">${latencyHTML}</td>
                    <td><span class="badge" style="background: ${badgeColor}; color: white; padding: 4px 8px; border-radius: 4px; font-size: 11px; font-weight: 600; text-transform: uppercase;">${inc.status}</span></td>
                    <td style="font-size: 13px;">
                        ${inc.status === 'draft' ? 
                            `<i class="fa-regular fa-clock text-warning"></i> Drafting` : 
                            (inc.status !== 'resolved' && inc.status !== 'cancelled' ? 
                                `<button class="btn btn-secondary" style="padding: 4px 12px; font-size: 11px; background-color: white; border: 1px solid var(--border-color); border-radius: 4px; cursor: pointer;" onclick="window.dashSelectIncident('${inc.id}')">Manage</button>` : 
                                (inc.status === 'resolved' ? `<span style="color: var(--success); font-weight: 500;"><i class="fa-solid fa-check"></i> Resolved</span>` : `<span style="color: var(--danger); font-weight: 500;"><i class="fa-solid fa-ban"></i> Cancelled</span>`)
                            )
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
        
        document.getElementById("hist-det-location").textContent = inc.address || 'Unknown Location';
        
        let formattedDetails = (inc.description || inc.details || "No notes available").replace(/ \| /g, "<br><br>");
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

        const html = Array.from(this.broadcasts).reverse().map(b => {
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
                            ${f.media_path ? `<a href="#" onclick="const w=window.open('','_blank'); w.document.write('<title>Feedback Attachment</title><img src=\\'${f.media_path}\\' style=\\'max-width:100%; display:block; margin:auto;\\'>'); return false;"><img src="${f.media_path}" style="max-height: 50px; border-radius: 4px; border: 1px solid var(--border-color); object-fit: cover; max-width: 80px; cursor: pointer;"></a>` : '<span style="color: var(--text-muted); font-size: 12px">None</span>'}
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
            roadside: 0, report: 0
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
}

let commandDashboard;
document.addEventListener("DOMContentLoaded", () => {
    // Check if already authenticated
    if (localStorage.getItem("alerto_admin_auth")) {
        document.getElementById("auth-gateway").classList.add("hidden");
        document.getElementById("dash-header").style.display = "flex";
        document.getElementById("dash-main").style.display = "grid";
        commandDashboard = new CommandDashboard(JSON.parse(localStorage.getItem("alerto_admin_auth")));
        window.commandDashboard = commandDashboard;
    } else {
        initAuthGateway();
    }
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
            
            if (data.success && (data.user.type === "authority")) {
                localStorage.setItem("alerto_admin_auth", JSON.stringify(data.user));
                
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

    if (e.target.tagName === "IMG" && e.target.closest(".chat-bubble")) {
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


