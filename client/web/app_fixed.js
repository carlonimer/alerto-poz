/* ==========================================================================
   ALERTO-POZ: CITIZEN MOBILE CLIENT ENGINE (RE-DESIGNED CONVERSATIONAL FLOW)
   ========================================================================= */

// --- DOM POLYFILL FOR WEB COMPATIBILITY ---
(function() {
    const originalGetElementById = document.getElementById.bind(document);
    document.getElementById = function(id) {
        const el = originalGetElementById(id);
        if (!el) {
            console.warn('Polyfill: Missing DOM element created in memory:', id);
            return document.createElement('div');
        }
        return el;
    };
})();
// ------------------------------------------

// Bounding box for Pozorrubio, Pangasinan (Strict geofencing)
const GEOFENCE = {
    minLat: 16.0500,
    maxLat: 16.1800,
    minLng: 120.4800,
    maxLng: 120.6100
};

const POZORRUBIO_PLAZA = { lat: 16.1114, lng: 120.5482 };

// Real Local Stations in Pozorrubio, Pangasinan
const STATIONS = [
    { name: "Pozorrubio Community Hospital", type: "medical", lat: 16.1086, lng: 120.5424, contact: "(075) 566-7080" },
    { name: "Rural Health Unit I (RHU I)", type: "medical", lat: 16.1110, lng: 120.5490, contact: "0917-889-4321" },
    { name: "Pozorrubio Police Station (PNP)", type: "police", lat: 16.1115, lng: 120.5484, contact: "0998-598-5085" },
    { name: "Pozorrubio Fire Station (BFP)", type: "fire", lat: 16.1118, lng: 120.5487, contact: "0917-123-4567" }
];

// Server connection path for hybrid native app environments
const SERVER_URL = (window.location.protocol === 'file:' || window.location.hostname === '' || window.location.port === '5500' || window.location.port === '5501')
    ? 'http://localhost:3000' // Handle VS Code Live Server & file:// testing; use 10.0.2.2 only if using Android Emulator without Capacitor HTTP server
    : window.location.origin;


class CitizenMobileClient {
    constructor() {
        this.socket = null;
        this.activeUser = null;
        this.gps = { ...POZORRUBIO_PLAZA };
        
        this.isOnline = navigator.onLine;
        this.selectedCategory = "medical";
        this.activeIncident = null; // Current emergency report session (draft or sent)
        this.attachments = []; // Store base64 media data objects: { name, type, data }
        
        // SOS countdown timer properties
        this.sosTimer = null;
        this.countdown = 5;
        this.isCounting = false;
        
        // Call simulation properties
        this.callTimer = null;
        this.callDuration = 0;
        this.isCallActive = false;
        
        // Maps & Markers
        this.homeMap = null;
        this.homeUserMarker = null;
        this.consoleMap = null;
        this.consoleUserMarker = null;
        
        // Active responder unit marker
        this.responderMarker = null;
        this.assignedResponderUnit = null;

        // Custom polygon overlays for hazard map pills
        this.floodOverlay = null;
        this.waterOverlay = null;
        this.bookmarkMarkersGroup = null;
        
        this.initDOM();
        this.checkSession();
        this.initSocket();
        this.initNetworkMonitoring();
    }

    initDOM() {
        // Auth Views
        this.authView = document.getElementById("view-auth");
        this.appView = document.getElementById("view-app");
        this.loginCard = document.getElementById("auth-login-card");
        this.registerCard = document.getElementById("auth-register-card");
        this.otpCard = document.getElementById("auth-otp-card");
        this.forgotCard = document.getElementById("auth-forgot-card");
        this.resetCard = document.getElementById("auth-reset-card");

        // Auth Forms
        this.loginForm = document.getElementById("login-form");
        this.registerForm = document.getElementById("register-form");
        this.otpForm = document.getElementById("otp-form");
        this.forgotForm = document.getElementById("forgot-form");
        this.resetForm = document.getElementById("reset-form");

        // Auth Navigation Toggles
        this.signupToggle = document.getElementById("signup-toggle-action");
        this.loginToggle = document.getElementById("login-toggle-action-text");
        this.gotoForgotBtn = document.getElementById("btn-goto-forgot");
        this.backAuthBtns = document.querySelectorAll(".btn-back-auth");

        // Registration Fields & Tabs
        this.tabRegPhone = document.getElementById("tab-reg-phone");
        this.tabRegEmail = document.getElementById("tab-reg-email");
        this.groupRegPhone = document.getElementById("group-register-phone");
        this.groupRegEmail = document.getElementById("group-register-email");
        this.regPassword = document.getElementById("register-password");
        this.regConfirm = document.getElementById("register-confirm");

        // Password Checklist Items
        this.chkLength = document.getElementById("chk-length");
        this.chkUpper = document.getElementById("chk-upper");
        this.chkLower = document.getElementById("chk-lower");
        this.chkNumber = document.getElementById("chk-number");
        this.chkSpecial = document.getElementById("chk-special");

        // Reset Password Checklist Items
        this.resetPasswordInput = document.getElementById("reset-password-input");
        this.chkResetLength = document.getElementById("chk-reset-length");
        this.chkResetUpper = document.getElementById("chk-reset-upper");
        this.chkResetLower = document.getElementById("chk-reset-lower");
        this.chkResetNumber = document.getElementById("chk-reset-number");
        this.chkResetSpecial = document.getElementById("chk-reset-special");

        // OTP inputs
        this.otpBoxes = document.querySelectorAll(".otp-box");
        this.otpTargetLabel = document.getElementById("otp-target-label");
        this.otpTimerText = document.getElementById("otp-timer-text");
        this.btnResendOtp = document.getElementById("btn-resend-otp");

        // Developer Sandbox Elements
        this.devOtpToast = document.getElementById("dev-otp-toast");
        this.devOtpCode = document.getElementById("dev-otp-code");
        this.btnAutofillOtp = document.getElementById("btn-autofill-otp");
        this.devToastClose = document.getElementById("dev-toast-close");
        
        // View States
        this.stateHomepage = document.getElementById("state-homepage");
        this.stateSosChat = document.getElementById("state-sos-chat");
        
        // Geolocation loader
        this.locationLoader = document.getElementById("location-loader");
        
        // Homepage items
        this.addressSearchInput = document.getElementById("address-search-input");
        this.gpsRecenterBtn = document.getElementById("gps-recenter");
        this.btnCheckin = document.getElementById("btn-checkin");
        this.btnBookmarks = document.getElementById("btn-bookmarks");
        this.sosFab = document.getElementById("homepage-sos-fab");
        this.logoutBtn = document.getElementById("btn-profile-logout");
        
        // Pills
        this.pillFlood = document.getElementById("pill-flood");
        this.pillWater = document.getElementById("pill-water");
        
        // Bottom sheet Alerts Drawer
        this.alertsSheet = document.getElementById("alerts-sheet");
        this.sheetDragHandle = document.getElementById("sheet-drag-handle");
        this.alertsBadgeHome = document.getElementById("badge-alerts-home");
        this.alertsHistoryContainer = document.getElementById("broadcasts-history-list");
        
        // Chat View items
        this.btnChatBack = document.getElementById("btn-chat-back");
        this.btnChatOptClose = document.getElementById("btn-chat-opt-close");
        this.responderStatusDot = document.getElementById("responder-status-dot");
        this.responderStatusText = document.getElementById("responder-status-text");
        this.reportStatusBadge = document.getElementById("report-status-badge");
        this.chatGeofenceAddress = document.getElementById("chat-geofence-address");
        this.chatIncidentTime = document.getElementById("chat-incident-time");
        this.chatIncidentId = document.getElementById("chat-incident-id");
        this.btnCopyIncident = document.getElementById("btn-copy-incident");
        
        // Media upload elements
        this.mediaAttachmentInput = document.getElementById("media-attachment-input");
        this.btnChatPlus = document.getElementById("btn-chat-plus");
        
        // Dynamically create preview containers in chat controls
        this.chatControlsFooter = document.querySelector(".chat-footer-controls");
        this.previewsContainer = document.createElement("div");
        this.previewsContainer.className = "chat-media-preview-container hidden";
        this.previewsContainer.id = "chat-media-previews";
        this.chatControlsFooter.insertBefore(this.previewsContainer, document.getElementById("chat-notes-form"));

        // Conversational Elements
        this.chatMessagesContainer = document.getElementById("chat-messages-container");
        this.dynamicChatFeed = document.getElementById("dynamic-chat-feed");
        this.chatNotesForm = document.getElementById("chat-notes-form");
        this.chatDetailsInput = document.getElementById("chat-details-input");
        this.chatSendBtn = document.getElementById("btn-chat-send");
        
        // Grid Submit button
        this.btnTriggerSosAlert = document.getElementById("btn-trigger-sos-alert");
        
        // Countdown Elements (inside chat view)
        this.chatSosCountdownCard = document.getElementById("chat-sos-countdown-card");
        this.progressBar = document.getElementById("progress-bar-indicator-chat");
        this.countdownText = document.getElementById("countdown-label-chat");
        this.cancelSosBtn = document.getElementById("cancel-sos-btn-chat");
        
        // Voice / Video Call Elements
        this.btnAudioCall = document.getElementById("btn-audio-call");
        this.btnVideoCall = document.getElementById("btn-video-call");
        this.callOverlay = document.getElementById("call-overlay");
        this.callVideoGrid = document.getElementById("call-video-grid");
        this.callVoiceProfile = document.getElementById("call-voice-profile");
        this.callTypeTitle = document.getElementById("call-type-title");
        this.callConnectionStatus = document.getElementById("call-connection-status");
        this.callTimerLabel = document.getElementById("call-timer-label");
        this.btnHangupCall = document.getElementById("btn-hangup-call");
        this.voiceWaves = document.getElementById("voice-waves");

        // Global push toast close
        this.pushToast = document.getElementById("ios-notification-toast");
        this.pushToastClose = document.getElementById("push-toast-close");
        this.pushToastHeader = document.getElementById("push-toast-header");
        this.pushToastBody = document.getElementById("push-toast-body");
        
        // Binding Event Handlers
        // Login Submit
        this.loginForm.addEventListener("submit", (e) => {
            e.preventDefault();
            this.handleLoginSubmit();
        });

        // Register Submit
        this.registerForm.addEventListener("submit", (e) => {
            e.preventDefault();
            this.handleRegisterSubmit();
        });

        // OTP Submit
        this.otpForm.addEventListener("submit", (e) => {
            e.preventDefault();
            this.handleOtpSubmit();
        });

        // Forgot Submit
        this.forgotForm.addEventListener("submit", (e) => {
            e.preventDefault();
            this.handleForgotSubmit();
        });

        // Reset Submit
        this.resetForm.addEventListener("submit", (e) => {
            e.preventDefault();
            this.handleResetSubmit();
        });

        // Card navigation
        this.signupToggle.addEventListener("click", (e) => {
            e.preventDefault();
            this.switchAuthCard("register");
        });

        this.loginToggle.addEventListener("click", (e) => {
            e.preventDefault();
            this.switchAuthCard("login");
        });
        
        this.gotoForgotBtn = document.getElementById("btn-goto-forgot");
        if (this.gotoForgotBtn) {
            this.gotoForgotBtn.addEventListener("click", (e) => {
                e.preventDefault();
                this.switchAuthCard("forgot");
            });
        }

        this.backAuthBtns.forEach(btn => {
            btn.addEventListener("click", (e) => {
                e.preventDefault();
                this.switchAuthCard("login");
            });
        });

        // Register Tabs
        this.tabRegPhone.addEventListener("click", () => {
            this.tabRegPhone.classList.add("active");
            this.tabRegEmail.classList.remove("active");
            this.groupRegPhone.classList.remove("hidden");
            this.groupRegEmail.classList.add("hidden");
            document.getElementById("register-email").value = "";
            document.getElementById("register-email").required = false;
            document.getElementById("register-phone").required = true;
        });

        this.tabRegEmail.addEventListener("click", () => {
            this.tabRegEmail.classList.add("active");
            this.tabRegPhone.classList.remove("active");
            this.groupRegEmail.classList.remove("hidden");
            this.groupRegPhone.classList.add("hidden");
            document.getElementById("register-phone").value = "";
            document.getElementById("register-phone").required = false;
            document.getElementById("register-email").required = true;
        });

        // Password eye show/hide buttons
        const passwordToggles = document.querySelectorAll(".password-toggle-btn");
        passwordToggles.forEach(toggle => {
            toggle.addEventListener("click", () => {
                const input = toggle.parentElement.querySelector("input");
                const icon = toggle.querySelector("i");
                if (input.type === "password") {
                    input.type = "text";
                    icon.className = "fa-solid fa-eye";
                } else {
                    input.type = "password";
                    icon.className = "fa-solid fa-eye-slash";
                }
            });
        });

        // Password strength checklists
        this.regPassword.addEventListener("input", () => {
            this.validatePasswordStrength(this.regPassword.value, "register");
        });

        this.resetPasswordInput.addEventListener("input", () => {
            this.validatePasswordStrength(this.resetPasswordInput.value, "reset");
        });

        // OTP inputs auto-tabbing cursor
        this.otpBoxes.forEach((box, idx) => {
            box.addEventListener("input", (e) => {
                const val = box.value;
                if (val && idx < this.otpBoxes.length - 1) {
                    this.otpBoxes[idx + 1].focus();
                }
            });

            box.addEventListener("keydown", (e) => {
                if (e.key === "Backspace" && !box.value && idx > 0) {
                    this.otpBoxes[idx - 1].focus();
                }
            });
        });

        // Resend OTP button
        this.btnResendOtp.addEventListener("click", () => {
            this.handleResendOtpTrigger();
        });

        // Dev sandbox autofill & dismiss
        this.btnAutofillOtp.addEventListener("click", () => {
            const code = this.devOtpCode.textContent;
            if (code && code !== "------") {
                if (this.currentAuthCard === "otp") {
                    for (let i = 0; i < 6; i++) {
                        this.otpBoxes[i].value = code[i];
                    }
                    this.otpBoxes[5].focus();
                } else if (this.currentAuthCard === "reset") {
                    document.getElementById("reset-otp-code").value = code;
                }
            }
        });

        this.devToastClose.addEventListener("click", () => {
            this.devOtpToast.classList.add("hidden");
        });

        this.gpsRecenterBtn.addEventListener("click", () => {
            this.refreshGPS(true);
        });

        this.logoutBtn.addEventListener("click", () => {
            this.handleLogoutToggle();
        });

        this.pillFlood.addEventListener("click", () => this.toggleFloodLayer());
        this.pillWater.addEventListener("click", () => this.toggleWaterLayer());

        this.btnCheckin.addEventListener("click", () => this.handleCheckin());
        this.btnBookmarks.addEventListener("click", () => this.toggleBookmarks());

        this.sosFab.addEventListener("click", () => this.triggerSOSFlow());

        this.btnChatBack.addEventListener("click", () => {
            this.transitionAppState("homepage");
        });
        
        if (this.btnChatOptClose) {
            this.btnChatOptClose.addEventListener("click", () => {
                this.closeIncidentFlow();
            });
        }

        this.btnCopyIncident.addEventListener("click", () => {
            navigator.clipboard.writeText(this.chatIncidentId.textContent);
            alert("Incident ID copied to clipboard!");
        });

        this.sheetDragHandle.addEventListener("click", () => {
            this.toggleAlertsSheet();
        });

        this.chatNotesForm.addEventListener("submit", (e) => {
            e.preventDefault();
            this.sendChatNotes();
        });

        // Trigger manual Send Alert
        this.btnTriggerSosAlert = document.getElementById("btn-trigger-sos-alert");
        if (this.btnTriggerSosAlert) {
            this.btnTriggerSosAlert.addEventListener("click", () => {
                this.triggerSOSFlow();
            });
        }

        // Passcode settings logic
        this.btnMenuPasscode = document.getElementById("btn-menu-passcode");
        this.modalPasscode = document.getElementById("modal-passcode");
        this.btnCancelPasscode = document.getElementById("btn-cancel-passcode");
        this.btnSavePasscode = document.getElementById("btn-save-passcode");

        if (this.btnMenuPasscode) {
            this.btnMenuPasscode.addEventListener("click", () => {
                const msgEl = document.getElementById("passcode-msg");
                const curContainer = document.getElementById("current-passcode-container");
                const confirmPass = document.getElementById("input-confirm-passcode");
                
                document.getElementById("input-current-passcode").value = "";
                document.getElementById("input-new-passcode").value = "";
                if (confirmPass) confirmPass.value = "";
                
                if (this.activeUser && (this.activeUser.hasPasscode || this.activeUser.passcode === "SET")) {
                    if (msgEl) msgEl.textContent = "Enter your current passcode to create a new one.";
                    if (curContainer) curContainer.style.display = "block";
                } else {
                    if (msgEl) msgEl.textContent = "You don't have a passcode yet. Create one to secure sensitive actions.";
                    if (curContainer) curContainer.style.display = "none";
                }
                
                if (this.modalPasscode) this.modalPasscode.classList.remove("hidden");
            });
        }
        
        if (this.btnCancelPasscode) {
            this.btnCancelPasscode.addEventListener("click", () => {
                if (this.modalPasscode) this.modalPasscode.classList.add("hidden");
            });
        }
        if (this.btnSavePasscode) {
            this.btnSavePasscode.addEventListener("click", () => this.savePasscode());
        }



        // Plus (+) button clicks trigger file input dialog
        this.btnChatPlus = document.getElementById("btn-chat-plus");
        this.btnChatPlus.addEventListener("click", () => {
            this.mediaAttachmentInput.click();
        });

        this.mediaAttachmentInput.addEventListener("change", (e) => {
            this.handleMediaUpload(e);
        });

        // Calling buttons
        this.btnAudioCall.addEventListener("click", () => this.startCall("audio"));
        this.btnVideoCall.addEventListener("click", () => this.startCall("video"));
        this.btnHangupCall.addEventListener("click", () => this.endCall());

        // Category selection
        const categoryButtons = document.querySelectorAll(".chat-category-btn");
        categoryButtons.forEach(btn => {
            btn.addEventListener("click", () => {
                categoryButtons.forEach(b => b.classList.remove("active"));
                btn.classList.add("active");
                this.selectedCategory = btn.getAttribute("data-cat");
                this.updateSOSCategory(this.selectedCategory);
            });
        });

        this.cancelSosBtn.addEventListener("click", () => {
            this.cancelSOSCountdown();
        });
        
        this.pushToastClose.addEventListener("click", () => {
            this.pushToast.classList.add("hidden");
        });
    }

    initSocket() {
        this.socket = io(SERVER_URL);
        
        this.socket.on('connect', () => {
            console.log("WebSocket connected successfully");
            this.isOnline = true;
            this.syncOfflineQueue();
        });
        
        this.socket.on('disconnect', () => {
            console.log("WebSocket disconnected");
            this.isOnline = false;
        });

        this.socket.on('broadcast-advisory', (data) => {
            this.receiveBroadcastAlert(data);
        });

        this.socket.on('incident-updated', (incident) => {
            if (this.activeIncident && this.activeIncident.id === incident.id) {
                this.activeIncident = incident;
                this.syncActiveIncidentStatus();
            }
        });

        this.socket.on('responder-updated', (responder) => {
            if (this.activeIncident && this.activeIncident.assignedUnit === responder.id) {
                this.syncResponderStatus(responder);
            }
        });

        // Listen for remote call status updates from command center dashboard
        this.socket.on('call-status-updated', (data) => {
            const myName = this.activeUser ? this.activeUser.name : "Carlo Nimer";
            if (data.reporter === myName && this.isCallActive) {
                if (data.status === 'connected') {
                    this.establishCallConnection();
                } else if (data.status === 'ended') {
                    this.endCall(false);
                }
            }
        });
    }

    initNetworkMonitoring() {
        window.addEventListener('online', () => {
            this.isOnline = true;
            this.syncOfflineQueue();
        });
        
        window.addEventListener('offline', () => {
            this.isOnline = false;
        });
    }

    checkSession() {
        const token = localStorage.getItem("alerto-token");
        const userStr = localStorage.getItem("alerto-user");
        if (token && userStr) {
            try {
                this.activeUser = JSON.parse(userStr);
                this.authView.classList.remove("active");
                this.appView.classList.add("active");
                this.logoutBtn.textContent = "LOG OUT";
                this.logoutBtn.style.backgroundColor = "#ff3b30";
                this.logoutBtn.style.color = "white";
                
                this.initHomepageMap();
                this.refreshGPS(false);
                this.syncBroadcastsFeed();
            } catch (e) {
                localStorage.removeItem("alerto-token");
                localStorage.removeItem("alerto-user");
            }
        }
    }

    switchAuthCard(cardName) {
        this.currentAuthCard = cardName;
        
        // Hide all cards
        this.loginCard.classList.add("hidden");
        this.registerCard.classList.add("hidden");
        this.otpCard.classList.add("hidden");
        this.forgotCard.classList.add("hidden");
        this.resetCard.classList.add("hidden");
        
        // Hide dev toast on transitions
        this.devOtpToast.classList.add("hidden");
        
        if (cardName === "login") {
            this.loginCard.classList.remove("hidden");
        } else if (cardName === "register") {
            this.registerCard.classList.remove("hidden");
            this.registerForm.reset();
            this.validatePasswordStrength("", "register");
            this.tabRegPhone.click();
        } else if (cardName === "otp") {
            this.otpCard.classList.remove("hidden");
            this.otpForm.reset();
            setTimeout(() => this.otpBoxes[0].focus(), 100);
        } else if (cardName === "forgot") {
            this.forgotCard.classList.remove("hidden");
            this.forgotForm.reset();
        } else if (cardName === "reset") {
            this.resetCard.classList.remove("hidden");
            this.resetForm.reset();
            this.validatePasswordStrength("", "reset");
        }
    }

    validatePasswordStrength(pw, mode) {
        const rules = {
            length: pw.length >= 8,
            upper: /[A-Z]/.test(pw),
            lower: /[a-z]/.test(pw),
            number: /\d/.test(pw),
            special: /[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?]/.test(pw)
        };

        const updateItem = (elem, isValid) => {
            if (elem) {
                if (isValid) {
                    elem.className = "checklist-item text-success";
                    elem.querySelector("i").className = "fa-solid fa-circle-check";
                } else {
                    elem.className = "checklist-item text-danger";
                    elem.querySelector("i").className = "fa-solid fa-circle-xmark";
                }
            }
        };

        if (mode === "register") {
            updateItem(this.chkLength, rules.length);
            updateItem(this.chkUpper, rules.upper);
            updateItem(this.chkLower, rules.lower);
            updateItem(this.chkNumber, rules.number);
            updateItem(this.chkSpecial, rules.special);
        } else {
            const chkResetLength = document.getElementById("chk-reset-length");
            const chkResetUpper = document.getElementById("chk-reset-upper");
            const chkResetLower = document.getElementById("chk-reset-lower");
            const chkResetNumber = document.getElementById("chk-reset-number");
            const chkResetSpecial = document.getElementById("chk-reset-special");
            
            updateItem(chkResetLength, rules.length);
            updateItem(chkResetUpper, rules.upper);
            updateItem(chkResetLower, rules.lower);
            updateItem(chkResetNumber, rules.number);
            updateItem(chkResetSpecial, rules.special);
        }
        
        return Object.values(rules).every(v => v);
    }

    async handleLoginSubmit() {
        const loginId = document.getElementById("login-id").value.trim();
        const password = document.getElementById("login-password").value;
        const rememberMe = document.getElementById("remember-me").checked;

        if (!loginId || !password) {
            alert("Please fill in all credentials.");
            return;
        }

        const loginBtn = document.getElementById("btn-login-submit");
        const originalText = loginBtn.innerHTML;
        loginBtn.disabled = true;
        loginBtn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Authenticating...';

        try {
            const res = await fetch(`${SERVER_URL}/api/auth/login`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ loginId, password })
            });

            const data = await res.json();
            if (!res.ok) {
                alert(data.error || "Authentication failed.");
                return;
            }

            if (data.otpRequired) {
                this.otpSession = {
                    target: data.target,
                    type: 'login',
                    rememberMe
                };
                
                this.switchAuthCard("otp");
                this.otpTargetLabel.textContent = data.target.includes('@') 
                    ? `OTP sent to your email: ${data.target}` 
                    : `OTP sent via SMS: ${data.target}`;
                
                this.devOtpCode.textContent = data.otpDevVal;
                this.devOtpToast.classList.remove("hidden");
                this.startOtpTimer();
            }
        } catch (e) {
            console.error(e);
            alert("Network connection error. Server might be offline.");
        } finally {
            loginBtn.disabled = false;
            loginBtn.innerHTML = originalText;
        }
    }

    async handleRegisterSubmit() {
        const name = document.getElementById("register-name").value.trim();
        const isEmailMode = this.tabRegEmail.classList.contains("active");
        const email = isEmailMode ? document.getElementById("register-email").value.trim() : "";
        const phone = !isEmailMode ? document.getElementById("register-phone").value.trim() : "";
        const password = document.getElementById("register-password").value;
        const confirm = document.getElementById("register-confirm").value;

        if (!name || (!email && !phone) || !password || !confirm) {
            alert("All required fields must be completed.");
            return;
        }

        if (password !== confirm) {
            alert("Passwords do not match.");
            return;
        }

        if (!this.validatePasswordStrength(password, "register")) {
            alert("Password does not meet the complexity requirements.");
            return;
        }

        const registerBtn = document.getElementById("btn-register-submit");
        const originalText = registerBtn.innerHTML;
        registerBtn.disabled = true;
        registerBtn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Registering...';

        try {
            const res = await fetch(`${SERVER_URL}/api/auth/register`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ name, email: email || undefined, phone: phone || undefined, password })
            });

            const data = await res.json();
            if (!res.ok) {
                alert(data.error || "Registration failed.");
                return;
            }

            if (data.otpRequired) {
                this.otpSession = {
                    target: data.target,
                    type: 'register',
                    rememberMe: true
                };
                
                this.switchAuthCard("otp");
                this.otpTargetLabel.textContent = data.target.includes('@') 
                    ? `OTP sent to email: ${data.target}` 
                    : `OTP sent via SMS: ${data.target}`;
                
                this.devOtpCode.textContent = data.otpDevVal;
                this.devOtpToast.classList.remove("hidden");
                this.startOtpTimer();
            }
        } catch (e) {
            console.error(e);
            alert("Network connection error.");
        } finally {
            registerBtn.disabled = false;
            registerBtn.innerHTML = originalText;
        }
    }

    async handleOtpSubmit() {
        if (!this.otpSession) return;

        let code = "";
        this.otpBoxes.forEach(box => {
            code += box.value;
        });

        if (code.length < 6) {
            alert("Please enter the complete 6-digit OTP code.");
            return;
        }

        const otpBtn = document.getElementById("btn-otp-submit");
        const originalText = otpBtn.innerHTML;
        otpBtn.disabled = true;
        otpBtn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Verifying...';

        try {
            const res = await fetch(`${SERVER_URL}/api/auth/verify-otp`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    target: this.otpSession.target,
                    code,
                    type: this.otpSession.type
                })
            });

            const data = await res.json();
            if (!res.ok) {
                alert(data.error || "Verification failed.");
                return;
            }

            alert("Verification successful!");
            
            if (this.otpSession.rememberMe) {
                localStorage.setItem("alerto-token", data.token);
                localStorage.setItem("alerto-user", JSON.stringify(data.user));
            }
            
            this.activeUser = data.user;
            this.logoutBtn.textContent = "LOG OUT";
            this.logoutBtn.style.backgroundColor = "#ff3b30";
            this.logoutBtn.style.color = "white";

            this.devOtpToast.classList.add("hidden");
            this.authView.classList.remove("active");
            this.appView.classList.add("active");

            this.initHomepageMap();
            this.refreshGPS(false);
            this.syncBroadcastsFeed();
        } catch (e) {
            console.error(e);
            alert("Connection error during OTP verification.");
        } finally {
            otpBtn.disabled = false;
            otpBtn.innerHTML = originalText;
        }
    }

    startOtpTimer() {
        clearInterval(this.otpTimerInterval);
        
        let duration = 300; 
        let resendDelay = 60; 
        
        this.btnResendOtp.disabled = true;
        this.btnResendOtp.classList.add("disabled");
        this.btnResendOtp.textContent = `Resend Code (${resendDelay}s)`;

        this.otpTimerInterval = setInterval(() => {
            duration--;
            resendDelay--;

            const mins = Math.floor(duration / 60);
            const secs = duration % 60;
            this.otpTimerText.textContent = `Code expires in ${mins}:${String(secs).padStart(2, '0')}`;

            if (duration <= 0) {
                clearInterval(this.otpTimerInterval);
                this.otpTimerText.textContent = "Code expired. Please resend.";
            }

            if (resendDelay > 0) {
                this.btnResendOtp.textContent = `Resend Code (${resendDelay}s)`;
            } else if (resendDelay === 0) {
                this.btnResendOtp.disabled = false;
                this.btnResendOtp.classList.remove("disabled");
                this.btnResendOtp.textContent = "Resend OTP";
            }
        }, 1000);
    }

    async handleResendOtpTrigger() {
        if (!this.otpSession) return;
        
        try {
            const res = await fetch(`${SERVER_URL}/api/auth/resend-otp`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    target: this.otpSession.target,
                    type: this.otpSession.type
                })
            });

            const data = await res.json();
            if (!res.ok) {
                alert(data.error || "Resend failed.");
                return;
            }

            alert("New verification code sent!");
            this.devOtpCode.textContent = data.otpDevVal;
            this.devOtpToast.classList.remove("hidden");
            this.startOtpTimer();
        } catch (e) {
            console.error(e);
            alert("Resend failed. Network connection error.");
        }
    }

    async handleForgotSubmit() {
        const target = document.getElementById("forgot-target").value.trim();
        if (!target) {
            alert("Please enter your registered email or phone.");
            return;
        }

        const forgotBtn = document.getElementById("btn-forgot-submit");
        const originalText = forgotBtn.innerHTML;
        forgotBtn.disabled = true;
        forgotBtn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Sending...';

        try {
            const res = await fetch(`${SERVER_URL}/api/auth/forgot-password`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ target })
            });

            const data = await res.json();
            if (!res.ok) {
                alert(data.error || "Request failed.");
                return;
            }

            alert("Password recovery code sent!");
            this.otpSession = {
                target,
                type: 'forgot',
                rememberMe: true
            };

            this.switchAuthCard("reset");
            this.devOtpCode.textContent = data.otpDevVal;
            this.devOtpToast.classList.remove("hidden");
        } catch (e) {
            console.error(e);
            alert("Network connection error.");
        } finally {
            forgotBtn.disabled = false;
            forgotBtn.innerHTML = originalText;
        }
    }

    async handleResetSubmit() {
        if (!this.otpSession) return;

        const code = document.getElementById("reset-otp-code").value.trim();
        const password = document.getElementById("reset-password-input").value;
        const confirm = document.getElementById("reset-confirm-input").value;

        if (!code || !password || !confirm) {
            alert("Please fill in all recovery fields.");
            return;
        }

        if (password !== confirm) {
            alert("Passwords do not match.");
            return;
        }

        if (!this.validatePasswordStrength(password, "reset")) {
            alert("New password does not meet strength requirements.");
            return;
        }

        const resetBtn = document.getElementById("btn-reset-submit");
        const originalText = resetBtn.innerHTML;
        resetBtn.disabled = true;
        resetBtn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Updating...';

        try {
            const res = await fetch(`${SERVER_URL}/api/auth/reset-password`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    target: this.otpSession.target,
                    code,
                    password
                })
            });

            const data = await res.json();
            if (!res.ok) {
                alert(data.error || "Reset failed.");
                return;
            }

            alert("Password updated successfully! Please log in.");
            this.switchAuthCard("login");
        } catch (e) {
            console.error(e);
            alert("Network connection error.");
        } finally {
            resetBtn.disabled = false;
            resetBtn.innerHTML = originalText;
        }
    }

    handleLogoutToggle() {
        if (confirm("Are you sure you want to log out of Alerto-poz?")) {
            localStorage.removeItem("alerto-token");
            localStorage.removeItem("alerto-user");
            this.activeUser = null;
            
            this.logoutBtn.textContent = "LOGIN";
            this.logoutBtn.style.backgroundColor = "#e5e5ea";
            this.logoutBtn.style.color = "var(--text-primary)";
            
            this.appView.classList.remove("active");
            this.authView.classList.add("active");
            this.switchAuthCard("login");
        }
    }

    refreshGPS(showNotification) {
        if (navigator.geolocation) {
            navigator.geolocation.getCurrentPosition(
                (pos) => {
                    const lat = pos.coords.latitude;
                    const lng = pos.coords.longitude;
                    
                    if (this.isInsidePozorrubio(lat, lng)) {
                        this.gps = { lat, lng };
                    } else {
                        if (showNotification) {
                            alert(`GEOFENCE BOUNDARY SNAP: Coordinates (${lat.toFixed(4)}, ${lng.toFixed(4)}) are outside Pozorrubio limits. Pin snaps back to center.`);
                        }
                        this.gps = { ...POZORRUBIO_PLAZA };
                    }
                    this.syncGPSUI();
                },
                () => {
                    this.gps = { ...POZORRUBIO_PLAZA };
                    this.syncGPSUI();
                },
                { enableHighAccuracy: true, timeout: 5000 }
            );
        }
    }

    isInsidePozorrubio(lat, lng) {
        return (lat >= GEOFENCE.minLat && lat <= GEOFENCE.maxLat && 
                lng >= GEOFENCE.minLng && lng <= GEOFENCE.maxLng);
    }

    syncGPSUI() {
        this.addressSearchInput.value = `📍 ${this.gps.lat.toFixed(4)}, ${this.gps.lng.toFixed(4)} (Pozorrubio, PG)`;
        
        if (this.homeMap && this.homeUserMarker) {
            this.homeUserMarker.setLatLng(this.gps);
            this.homeMap.panTo(this.gps);
        }
        
        if (this.consoleMap && this.consoleUserMarker) {
            this.consoleUserMarker.setLatLng(this.gps);
            this.consoleMap.panTo(this.gps);
        }
    }

    initHomepageMap() {
        if (this.homeMap) return;

        this.homeMap = L.map('homepage-map', {
            zoomControl: false,
            attributionControl: false
        }).setView([this.gps.lat, this.gps.lng], 14);

        L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png').addTo(this.homeMap);

        const citizenDivIcon = L.divIcon({
            className: 'citizen-marker-home',
            html: '<div style="background-color:#0066cc; width:16px; height:16px; border:2.5px solid #fff; border-radius:50%; box-shadow:0 0 10px rgba(0,102,204,0.6);"></div>',
            iconSize: [16, 16]
        });

        this.homeUserMarker = L.marker([this.gps.lat, this.gps.lng], {
            icon: citizenDivIcon,
            draggable: false
        }).addTo(this.homeMap);

        STATIONS.forEach(st => {
            let color = "#3b82f6";
            if (st.type === "fire") color = "#f59e0b";
            if (st.type === "medical") color = "#ef4444";
            
            const stationIcon = L.divIcon({
                className: 'station-marker',
                html: `<div style="background-color:${color}; width:11px; height:11px; border-radius:50%; border:1.5px solid #fff; box-shadow:0 1px 5px rgba(0,0,0,0.25);"></div>`
            });
            
            L.marker([st.lat, st.lng], { icon: stationIcon })
                .bindPopup(`<b>${st.name}</b><br>Contact: ${st.contact}`)
                .addTo(this.homeMap);
        });
    }

    transitionAppState(state) {
        if (state === "homepage") {
            this.stateSosChat.classList.remove("active");
            this.stateHomepage.classList.add("active");
            setTimeout(() => {
                if (this.homeMap) this.homeMap.invalidateSize();
            }, 100);
        } else if (state === "chat") {
            this.stateHomepage.classList.remove("active");
            this.stateSosChat.classList.add("active");
            this.initConsoleMap();
        }
    }

    initConsoleMap() {
        if (this.consoleMap) {
            setTimeout(() => {
                this.consoleMap.invalidateSize();
                this.consoleUserMarker.setLatLng(this.gps);
                this.consoleMap.panTo(this.gps);
            }, 120);
            return;
        }

        setTimeout(() => {
            this.consoleMap = L.map('console-map', {
                zoomControl: false,
                attributionControl: false
            }).setView([this.gps.lat, this.gps.lng], 14);

            L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png').addTo(this.consoleMap);

            const divIcon = L.divIcon({
                className: 'citizen-marker-console',
                html: '<div style="background-color:#ef4444; border:2px solid #fff; border-radius:50%; width:14px; height:14px; box-shadow:0 0 10px rgba(239,68,68,0.8);"></div>',
                iconSize: [14, 14]
            });

            this.consoleUserMarker = L.marker([this.gps.lat, this.gps.lng], {
                icon: divIcon,
                draggable: true
            }).addTo(this.consoleMap);

            this.consoleUserMarker.on('dragend', (e) => {
                const pos = e.target.getLatLng();
                if (this.isInsidePozorrubio(pos.lat, pos.lng)) {
                    this.gps = { lat: pos.lat, lng: pos.lng };
                    this.syncGPSUI();
                    this.updateSOSLocationOnServer();
                } else {
                    alert("Geofence Limit: Location snapped back inside Pozorrubio.");
                    this.consoleUserMarker.setLatLng(this.gps);
                }
            });
        }, 120);
    }

    handleCheckin() {
        if (navigator.geolocation) {
            navigator.geolocation.getCurrentPosition((pos) => {
                const lat = pos.coords.latitude;
                const lng = pos.coords.longitude;
                const name = this.activeUser ? this.activeUser.name : "Carlo Nimer";
                const phone = this.activeUser ? this.activeUser.phone : "09123456789";

                const checkinMsg = `Checked in successfully! Coordinates: ${lat.toFixed(5)}, ${lng.toFixed(5)}`;
                alert(checkinMsg);

                if (this.socket && this.socket.connected && this.isOnline) {
                    this.socket.emit('citizen-checkin-alert', {
                        name,
                        phone,
                        lat,
                        lng,
                        timestamp: Date.now()
                    });
                }
            });
        }
    }

    toggleBookmarks() {
        if (this.bookmarkMarkersGroup) {
            this.homeMap.removeLayer(this.bookmarkMarkersGroup);
            this.bookmarkMarkersGroup = null;
            alert("Bookmark overlays removed.");
            return;
        }

        this.bookmarkMarkersGroup = L.layerGroup();
        
        const bookmarks = [
            { name: "Pozorrubio Municipal Hall", lat: 16.1112, lng: 120.5485 },
            { name: "Pozorrubio Town Plaza", lat: 16.1114, lng: 120.5482 },
            { name: "Bued River Dike (Alert Boundary)", lat: 16.1360, lng: 120.5510 }
        ];

        bookmarks.forEach(bm => {
            const bIcon = L.divIcon({
                className: 'bookmark-pin',
                html: '<div style="background-color:#ff9500; border:1px solid #fff; border-radius:4px; width:8px; height:8px;"></div>'
            });
            L.marker([bm.lat, bm.lng], { icon: bIcon })
                .bindPopup(`<b>${bm.name}</b>`)
                .addTo(this.bookmarkMarkersGroup);
        });

        this.bookmarkMarkersGroup.addTo(this.homeMap);
        alert("Bookmark indicators added to map!");
    }

    toggleFloodLayer() {
        const isActive = this.pillFlood.getAttribute("data-active") === "true";
        if (isActive) {
            this.pillFlood.setAttribute("data-active", "false");
            if (this.floodOverlay) {
                this.homeMap.removeLayer(this.floodOverlay);
                this.floodOverlay = null;
            }
        } else {
            this.pillFlood.setAttribute("data-active", "true");
            const coords = [
                [16.1450, 120.5350],
                [16.1360, 120.5550],
                [16.1280, 120.5700],
                [16.1320, 120.5750],
                [16.1480, 120.5450]
            ];
            this.floodOverlay = L.polygon(coords, {
                color: '#ef4444',
                fillColor: '#ef4444',
                fillOpacity: 0.25,
                weight: 2
            }).addTo(this.homeMap);
            this.homeMap.fitBounds(this.floodOverlay.getBounds());
            alert("Active Flood Risk boundaries toggled!");
        }
    }

    toggleWaterLayer() {
        const isActive = this.pillWater.getAttribute("data-active") === "true";
        if (isActive) {
            this.pillWater.setAttribute("data-active", "false");
            if (this.waterOverlay) {
                this.homeMap.removeLayer(this.waterOverlay);
                this.waterOverlay = null;
            }
        } else {
            this.pillWater.setAttribute("data-active", "true");
            const coords = [
                [16.1150, 120.5400],
                [16.1150, 120.5550],
                [16.1050, 120.5550],
                [16.1050, 120.5400]
            ];
            this.waterOverlay = L.polygon(coords, {
                color: '#0066cc',
                fillColor: '#0066cc',
                fillOpacity: 0.18,
                weight: 1.5
            }).addTo(this.homeMap);
            alert("High water warning areas plotted.");
        }
    }

    toggleAlertsSheet() {
        if (this.alertsSheet.classList.contains("collapsed")) {
            this.alertsSheet.classList.remove("collapsed");
            this.alertsSheet.classList.add("expanded");
        } else {
            this.alertsSheet.classList.remove("expanded");
            this.alertsSheet.classList.add("collapsed");
        }
    }

    triggerSOSFlow() {
        if (!this.activeUser) {
            alert("Please verify your credentials and Log In first.");
            return;
        }

        // Show geolocation transition spinner
        this.locationLoader.classList.remove("hidden");
        
        setTimeout(() => {
            this.locationLoader.classList.add("hidden");
            
            // Check geofence and STRICT GPS ENFORCEMENT
            if (!this.isInsidePozorrubio(this.gps.lat, this.gps.lng)) {
                alert("STRICT GPS REQUIREMENT: Your location is outside the Pozorrubio geofence. ALERTO-POZ requires accurate location to dispatch responders.");
                return;
            }
            if (this.gps.lat === POZORRUBIO_PLAZA.lat && this.gps.lng === POZORRUBIO_PLAZA.lng) {
                alert("STRICT GPS REQUIREMENT: Location access is denied or unavailable. You MUST enable GPS to send an SOS Alert.");
                return;
            }

            // Create Drafting Incident Session
            const generatedID = `ALERTO-${new Date().getFullYear()}-${Math.floor(100000 + Math.random() * 900000)}`;
            const timeString = new Date().toLocaleString('en-US', { 
                month: 'short', day: 'numeric', year: 'numeric', 
                hour: 'numeric', minute: 'numeric', hour12: true 
            });

            this.activeIncident = {
                id: generatedID,
                category: this.selectedCategory,
                details: `Emergency report prepared by ${this.activeUser.name}`,
                lat: this.gps.lat,
                lng: this.gps.lng,
                reporter: this.activeUser.name,
                reporterPhone: this.activeUser.phone,
                createdAt: Date.now(),
                status: "draft",
                assignedUnit: null
            };

            this.attachments = [];
            this.previewsContainer.innerHTML = "";
            this.previewsContainer.classList.add("hidden");

            // Setup Chat UI
            this.chatIncidentId.textContent = generatedID;
            this.chatIncidentTime.textContent = timeString;
            this.chatGeofenceAddress.textContent = `📍 ${this.gps.lat.toFixed(5)}, ${this.gps.lng.toFixed(5)} (Buneg, Pozorrubio)`;
            this.reportStatusBadge.textContent = "Draft";
            this.reportStatusBadge.style.backgroundColor = "rgba(142, 142, 147, 0.15)";
            this.reportStatusBadge.style.color = "var(--text-secondary)";

            this.dynamicChatFeed.innerHTML = "";
            this.clearResponderTracking();

            // Set grid selectors active item
            const categoryButtons = document.querySelectorAll(".chat-category-btn");
            categoryButtons.forEach(b => {
                b.classList.remove("active");
                if (b.getAttribute("data-cat") === this.selectedCategory) {
                    b.classList.add("active");
                }
            });

            this.transitionAppState("chat");
        }, 800);
    }

    handleMediaUpload(e) {
        const files = Array.from(e.target.files);
        if (files.length === 0) return;

        files.forEach(file => {
            const reader = new FileReader();
            reader.onload = (event) => {
                const base64Data = event.target.result;
                const type = file.type.startsWith("image/") ? "image" : "video";
                
                const attObj = {
                    name: file.name,
                    type: type,
                    data: base64Data
                };
                this.attachments.push(attObj);
                this.renderMediaPreviews();
            };
            reader.readAsDataURL(file);
        });
    }

    renderMediaPreviews() {
        if (this.attachments.length === 0) {
            this.previewsContainer.classList.add("hidden");
            this.previewsContainer.innerHTML = "";
            return;
        }

        this.previewsContainer.classList.remove("hidden");
        let html = '';
        this.attachments.forEach((att, idx) => {
            const mediaTag = att.type === "image" 
                ? `<img src="${att.data}">` 
                : `<video src="${att.data}" muted autoplay loop></video>`;
            
            html += `
                <div class="media-thumb-wrapper">
                    ${mediaTag}
                    <button class="media-thumb-remove-btn" onclick="mobileClient.removeAttachment(${idx})">
                        <i class="fa-solid fa-xmark"></i>
                    </button>
                </div>
            `;
        });
        this.previewsContainer.innerHTML = html;
    }

    removeAttachment(idx) {
        this.attachments.splice(idx, 1);
        this.renderMediaPreviews();
    }

    sendChatNotes() {
        const text = this.chatDetailsInput.value.trim();
        if (!text || !this.activeIncident) return;

        this.chatDetailsInput.value = "";
        
        // Append user comment bubble in conversation log
        this.appendChatMessage("You", text, "outgoing-bubble");

        // Concatenate text details to active report drafting details
        this.activeIncident.details += ` | Notes: ${text}`;
        this.activeIncident.has_sent_messages = true;
        localStorage.setItem("alerto-active-incident", JSON.stringify(this.activeIncident));
        
        // If alert is already active, send updates dynamically
        if (this.activeIncident.status !== "draft" && this.socket && this.socket.connected && this.isOnline) {
            this.socket.emit('citizen-sos-report', this.activeIncident);
        }
    }

    updateSOSCategory(cat) {
        if (!this.activeIncident) return;
        this.activeIncident.category = cat;
        this.appendChatMessage("You", `Selected Category: ${cat.toUpperCase()}`, "outgoing-bubble");
        
        if (this.activeIncident.status !== "draft" && this.socket && this.socket.connected && this.isOnline) {
            this.socket.emit('citizen-sos-report', this.activeIncident);
        }
    }

    updateSOSLocationOnServer() {
        if (!this.activeIncident) return;
        this.activeIncident.lat = this.gps.lat;
        this.activeIncident.lng = this.gps.lng;
        
        if (this.activeIncident.status !== "draft" && this.socket && this.socket.connected && this.isOnline) {
            this.socket.emit('citizen-sos-report', this.activeIncident);
        }
    }

    triggerAlertBroadcast() {
        if (!this.activeIncident) return;
        if (this.isCounting) return;

        this.isCounting = true;
        this.countdown = 5;
        
        this.chatSosCountdownCard.classList.remove("hidden");
        this.countdownText.textContent = `${this.countdown}s`;
        this.progressBar.style.strokeDashoffset = "263.89";
        
        this.playTone(440, 0.1);
        
        this.sosTimer = setInterval(() => {
            this.countdown--;
            this.countdownText.textContent = `${this.countdown}s`;
            
            const offset = (this.countdown / 5) * 263.89;
            this.progressBar.style.strokeDashoffset = offset;
            
            if (this.countdown > 0) {
                this.playTone(440, 0.08);
            }
            
            if (this.countdown <= 0) {
                this.transmitEmergencyAlert();
            }
        }, 1000);
    }

    cancelSOSCountdown() {
        if (!this.isCounting) return;
        clearInterval(this.sosTimer);
        this.isCounting = false;
        
        this.chatSosCountdownCard.classList.add("hidden");
        this.playTone(220, 0.25);
        this.appendChatMessage("System", "SOS dispatch countdown cancelled.", "incoming-bubble");
    }

    transmitEmergencyAlert() {
        clearInterval(this.sosTimer);
        this.isCounting = false;
        this.chatSosCountdownCard.classList.add("hidden");
        
        this.playEmergencySiren();

        // Finalize details with files info if uploaded
        if (this.attachments.length > 0) {
            this.activeIncident.details += ` | Files Attached: ${this.attachments.length} media logs`;
            this.activeIncident.media = [...(this.activeIncident.media || []), ...this.attachments];
            
            // Append attachments logs bubbles
            this.attachments.forEach(att => {
                this.appendMediaMessageBubble(att);
            });
        }

        this.activeIncident.status = "pending";
        this.reportStatusBadge.textContent = "Pending";
        this.reportStatusBadge.style.backgroundColor = "rgba(239, 68, 68, 0.15)";
        this.reportStatusBadge.style.color = "var(--danger)";

        // Persist the updated status to localStorage
        localStorage.setItem("alerto-active-incident", JSON.stringify(this.activeIncident));

        // Clear previews
        this.attachments = [];
        this.renderMediaPreviews();
        
        if (this.socket && this.socket.connected && this.isOnline) {
            this.socket.emit('citizen-sos-report', this.activeIncident);
            const sosMessage = `🚨 SOS ALERT RECEIVED<br>
Ticket Code: ${this.activeIncident.id}<br>
Your emergency location has been detected and sent to the Command Center.<br><br>
For emergency validation, please provide:<br>
📸 Validation picture of the incident<br>
🎥 Validation video, if available<br>
📝 Short description of the emergency<br>
👥 Number of people needing assistance<br><br>
⚠️ Do not put yourself in danger to provide pictures or videos.`;
            this.appendChatMessage("", sosMessage, "incoming-bubble");
        } else {
            const queue = JSON.parse(localStorage.getItem("poz_offline_queue")) || [];
            queue.push(this.activeIncident);
            localStorage.setItem("poz_offline_queue", JSON.stringify(queue));
            
            this.appendChatMessage("System", "Network offline. Alert stored in queue and will auto-send on reconnection.", "incoming-bubble");
        }
    }

    appendMediaMessageBubble(att) {
        const wrap = document.createElement("div");
        wrap.className = "chat-message-bubble outgoing-bubble animate-bubble";
        const mediaTag = att.type === "image" 
            ? `<img src="${att.data}" style="max-width:160px; max-height:160px; border-radius:8px; display:block; border:1px solid #fff;">` 
            : `<video src="${att.data}" controls style="max-width:160px; max-height:160px; border-radius:8px; display:block; border:1px solid #fff;"></video>`;
        
        wrap.innerHTML = `
            <div class="bubble-content">
                <p><strong>Attachment:</strong></p>
                ${mediaTag}
            </div>
        `;
        this.dynamicChatFeed.appendChild(wrap);
        this.chatMessagesContainer.scrollTop = this.chatMessagesContainer.scrollHeight;
    }

    appendChatMessage(sender, text, bubbleClass) {
        const wrap = document.createElement("div");
        wrap.className = `chat-message-bubble ${bubbleClass} animate-bubble`;
        wrap.innerHTML = `
            <div class="bubble-content">
                <p>${sender ? `<strong>${sender}:</strong> ` : ''}${text}</p>
            </div>
        `;
        this.dynamicChatFeed.appendChild(wrap);
        this.chatMessagesContainer.scrollTop = this.chatMessagesContainer.scrollHeight;
    }

    // Interactive Audio & Video Calls Simulation
    startCall(type) {
        this.isCallActive = true;
        this.callDuration = 0;
        this.callTimerLabel.textContent = "00:00";
        this.callOverlay.classList.remove("hidden");

        if (type === "video") {
            this.callTypeTitle.textContent = "Emergency Video Call";
            this.callVideoGrid.classList.remove("hidden");
            this.callVoiceProfile.classList.add("hidden");
            this.voiceWaves.classList.add("hidden");
        } else {
            this.callTypeTitle.textContent = "Emergency Voice Call";
            this.callVoiceProfile.classList.remove("hidden");
            this.callVideoGrid.classList.add("hidden");
            this.voiceWaves.classList.remove("hidden");
        }

        this.callConnectionStatus.textContent = "Connecting to Pozorrubio Command Center...";
        this.playTone(660, 0.2);

        // Emit call ringing state to dispatcher
        if (this.socket && this.socket.connected) {
            this.socket.emit('citizen-call-status-change', {
                reporter: this.activeUser ? this.activeUser.name : "Carlo Nimer",
                phone: this.activeUser ? this.activeUser.phone : "09123456789",
                status: 'ringing',
                type: type
            });
        }

        // Set a timeout for 25 seconds of no answer (simulate timeout)
        this.callTimeout = setTimeout(() => {
            this.callConnectionStatus.textContent = "Line Busy (No Answer)";
            this.playTone(220, 0.35);
            setTimeout(() => {
                this.endCall(true);
            }, 2000);
        }, 25000);
    }

    establishCallConnection() {
        // Clear busy timeout
        clearTimeout(this.callTimeout);
        this.callConnectionStatus.textContent = "Call Connected (Secure line)";
        this.playTone(880, 0.15);

        if (this.callTypeTitle.textContent.includes("Video")) {
            this.voiceWaves.classList.add("hidden");
        } else {
            this.voiceWaves.classList.remove("hidden");
        }

        // Start clock
        clearInterval(this.callTimer);
        this.callTimer = setInterval(() => {
            this.callDuration++;
            const mins = String(Math.floor(this.callDuration / 60)).padStart(2, '0');
            const secs = String(this.callDuration % 60).padStart(2, '0');
            this.callTimerLabel.textContent = `${mins}:${secs}`;
        }, 1000);
    }

    endCall(notifyServer = true) {
        if (!this.isCallActive) return;
        
        clearTimeout(this.callTimeout);
        clearInterval(this.callTimer);
        this.isCallActive = false;
        
        this.callOverlay.classList.add("hidden");
        
        const mins = String(Math.floor(this.callDuration / 60)).padStart(2, '0');
        const secs = String(this.callDuration % 60).padStart(2, '0');
        const durationStr = `${mins}:${secs}`;

        // Emit call ended state to dispatcher if triggered locally
        if (notifyServer && this.socket && this.socket.connected) {
            this.socket.emit('citizen-call-status-change', {
                reporter: this.activeUser ? this.activeUser.name : "Carlo Nimer",
                phone: this.activeUser ? this.activeUser.phone : "09123456789",
                status: 'ended',
                type: this.callTypeTitle.textContent.includes("Video") ? "video" : "audio"
            });
        }
        
        this.appendChatMessage("System", `Call ended. Duration: ${durationStr}`, "incoming-bubble");
        this.playTone(330, 0.3);
    }

    syncActiveIncidentStatus() {
        if (!this.activeIncident) return;
        this.reportStatusBadge.textContent = this.activeIncident.status;
        
        // Hide SOS trigger button and categories if already dispatched
        const sosGrid = document.querySelector(".chat-category-grid");
        if (this.activeIncident.status !== "draft") {
            if (sosGrid) sosGrid.style.display = "none";
            if (this.btnTriggerSosAlert) this.btnTriggerSosAlert.style.display = "none";
            if (this.btnChatOptClose && (this.activeIncident.status === "resolved" || this.activeIncident.status === "cancelled")) {
                this.btnChatOptClose.style.display = "none";
            }
        } else {
            if (sosGrid) sosGrid.style.display = "";
            if (this.btnTriggerSosAlert) this.btnTriggerSosAlert.style.display = "";
            if (this.btnChatOptClose) this.btnChatOptClose.style.display = "";
        }
        
        if (this.activeIncident.status === "enroute") {
            this.reportStatusBadge.style.backgroundColor = "rgba(255, 149, 0, 0.15)";
            this.reportStatusBadge.style.color = "#ff9500";
        } else if (this.activeIncident.status === "resolved") {
            this.reportStatusBadge.style.backgroundColor = "rgba(52, 168, 83, 0.15)";
            this.reportStatusBadge.style.color = "#34a853";
            this.appendChatMessage("System", "Emergency marked as RESOLVED by command center.", "incoming-bubble");
            this.clearResponderTracking();
        }
    }

    closeIncidentFlow() {
        if (!this.activeIncident) return;
        
        // If it's just a draft and no messages/SOS sent, close it immediately
        if (this.activeIncident.status === "draft" && !this.activeIncident.has_sent_messages) {
            this.activeIncident = null;
            localStorage.removeItem("alerto-active-incident");
            this.transitionAppState("homepage");
            return;
        }
        
        // Otherwise, it was sent or has messages, so require passcode
        const modal = document.getElementById("modal-verify-close");
        if (!modal) return;
        modal.classList.remove("hidden");
        
        const input = document.getElementById("input-verify-close");
        const btnConfirm = document.getElementById("btn-confirm-close");
        const btnCancel = document.getElementById("btn-cancel-close");
        const errorText = document.getElementById("verify-close-error");
        
        input.value = "";
        errorText.classList.add("hidden");
        
        const handleCancel = () => {
            modal.classList.add("hidden");
            btnCancel.removeEventListener("click", handleCancel);
            btnConfirm.removeEventListener("click", handleConfirm);
        };
        
        const handleConfirm = async () => {
            const pass = input.value.trim();
            if (!pass) return;
            
            try {
                const res = await fetch(`${SERVER_URL}/api/user/passcode/verify`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ phone: this.activeUser.phone, passcode: pass })
                });
                const data = await res.json();
                
                if (data.valid) {
                    modal.classList.add("hidden");
                    
                    // Proceed with cancellation
                    this.activeIncident.status = "cancelled";
                    if (this.socket && this.socket.connected && this.isOnline) {
                        this.socket.emit('citizen-sos-report', this.activeIncident);
                        // Also notify command center to cancel via API
                        fetch(`${SERVER_URL}/api/incidents/${this.activeIncident.id}`, {
                            method: 'PUT',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({ status: 'cancelled' })
                        }).catch(console.error);
                    }
                    
                    this.appendChatMessage("System", "Incident cancelled by user.", "incoming-bubble");
                    this.activeIncident = null;
                    localStorage.removeItem("alerto-active-incident");
                    this.transitionAppState("homepage");
                    btnCancel.removeEventListener("click", handleCancel);
                    btnConfirm.removeEventListener("click", handleConfirm);
                } else {
                    errorText.textContent = "Incorrect passcode.";
                    errorText.classList.remove("hidden");
                }
            } catch (err) {
                errorText.textContent = "Error verifying passcode.";
                errorText.classList.remove("hidden");
            }
        };
        
        btnCancel.addEventListener("click", handleCancel);
        btnConfirm.addEventListener("click", handleConfirm);
    }

    async savePasscode() {
        if (!this.activeUser) return;
        const hasExistingPasscode = this.activeUser.hasPasscode || this.activeUser.passcode === "SET";
        const cur = document.getElementById("input-current-passcode").value;
        const newPass = document.getElementById("input-new-passcode").value;
        const confirmPass = document.getElementById("input-confirm-passcode").value;
        
        if (hasExistingPasscode && !cur) {
            alert("Current passcode is required.");
            return;
        }
        
        if (!newPass || !confirmPass) {
            alert("Please enter and confirm your new passcode.");
            return;
        }
        
        if (newPass !== confirmPass) {
            alert("New passcodes do not match.");
            return;
        }
        
        if (!/^\d{4,6}$/.test(newPass)) {
            alert("Passcode must be a 4 to 6 digit number.");
            return;
        }
        
        // Add spinner to button
        const originalText = this.btnSavePasscode.innerHTML;
        this.btnSavePasscode.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Saving...';
        this.btnSavePasscode.disabled = true;

        try {
            const res = await fetch(`${SERVER_URL}/api/user/passcode`, {
                method: "POST", headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    id: this.activeUser.id,
                    currentPasscode: cur,
                    newPasscode: newPass
                })
            });
            const data = await res.json();
            if (res.ok && data.success) {
                this.activeUser.hasPasscode = true;
                this.activeUser.passcode = "SET"; // Legacy compatibility
                localStorage.setItem("alerto-user", JSON.stringify(this.activeUser));
                if (this.modalPasscode) this.modalPasscode.classList.add("hidden");
                if (hasExistingPasscode) {
                    alert("Passcode updated successfully!");
                } else {
                    alert("Passcode created successfully.");
                }
            } else {
                alert(data.error || "Failed to save passcode");
            }
        } catch (e) {
            alert("Error saving passcode");
        } finally {
            this.btnSavePasscode.innerHTML = originalText;
            this.btnSavePasscode.disabled = false;
        }
    }

    syncResponderStatus(responder) {
        if (!this.activeIncident || this.activeIncident.assignedUnit !== responder.id) return;
        
        this.assignedResponderUnit = responder;
        this.responderStatusText.textContent = `${responder.name} En Route`;
        this.responderStatusDot.className = "status-dot-green";
        
        this.appendChatMessage("System", `Responder dispatched: ${responder.name} is on the way.`, "incoming-bubble");
    }

    updateResponderLiveMarker(id, lat, lng) {
        if (!this.consoleMap) return;

        if (this.responderMarker) {
            this.responderMarker.setLatLng([lat, lng]);
        } else {
            const vehicleIcon = L.divIcon({
                className: 'vehicle-marker-chat',
                html: '<div style="background-color:#34a853; border:2px solid #fff; border-radius:50%; width:16px; height:16px; box-shadow:0 0 8px rgba(52,168,83,0.8); display:flex; align-items:center; justify-content:center;"><i class="fa-solid fa-truck-medical" style="color:white; font-size:9px;"></i></div>',
                iconSize: [16, 16]
            });
            this.responderMarker = L.marker([lat, lng], { icon: vehicleIcon }).addTo(this.consoleMap);
        }

        const bounds = L.latLngBounds([this.gps, [lat, lng]]);
        this.consoleMap.fitBounds(bounds, { padding: [30, 30] });
    }

    clearResponderTracking() {
        this.responderStatusText.textContent = "No active responder";
        this.responderStatusDot.className = "status-dot-grey";
        
        if (this.responderMarker && this.consoleMap) {
            this.consoleMap.removeLayer(this.responderMarker);
            this.responderMarker = null;
        }
        this.assignedResponderUnit = null;
    }

    receiveBroadcastAlert(broadcast) {
        this.pushToastHeader.textContent = broadcast.title;
        this.pushToastBody.textContent = broadcast.message;
        this.pushToast.classList.remove("hidden");
        
        this.playEmergencySiren();
        
        const alerts = JSON.parse(localStorage.getItem("poz_broadcasts_history")) || [];
        alerts.unshift(broadcast);
        localStorage.setItem("poz_broadcasts_history", JSON.stringify(alerts));
        
        this.syncBroadcastsFeed();
    }

    syncBroadcastsFeed() {
        const alerts = JSON.parse(localStorage.getItem("poz_broadcasts_history")) || [];
        
        if (alerts.length > 0) {
            this.alertsBadgeHome.textContent = alerts.length;
            this.alertsBadgeHome.classList.remove("hidden");
        } else {
            this.alertsBadgeHome.classList.add("hidden");
        }

        if (alerts.length === 0) {
            this.alertsHistoryContainer.innerHTML = `
                <div class="empty-placeholder-sheet">
                    <i class="fa-solid fa-bell-slash"></i>
                    <p>No active broadcast alerts received in this session yet.</p>
                </div>
            `;
            return;
        }

        let html = '';
        alerts.forEach(b => {
            const time = new Date(b.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            const fakeDist = this.getHaversineDistance(this.gps.lat, this.gps.lng, 16.1114, 120.5482) + 2.5;

            html += `
                <div class="broadcast-alert-card-sheet">
                    <div class="alert-thumbnail-box">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                    </div>
                    <div class="alert-content-details">
                        <div class="alert-title-row">
                            <h4>${b.title}</h4>
                            <span class="alert-time-muted">${time}</span>
                        </div>
                        <p class="alert-desc-text">${b.message}</p>
                        <div class="alert-footer-stats">
                            <span class="alert-loc-dist">📍 ${fakeDist.toFixed(2)} km away</span>
                            <button class="alert-update-btn-blue"><i class="fa-solid fa-arrows-rotate"></i> Update</button>
                        </div>
                    </div>
                </div>
            `;
        });
        this.alertsHistoryContainer.innerHTML = html;
    }

    syncOfflineQueue() {
        const queue = JSON.parse(localStorage.getItem("poz_offline_queue")) || [];
        if (queue.length === 0 || !this.socket || !this.socket.connected) return;
        
        console.log(`Syncing ${queue.length} offline reports...`);
        queue.forEach((report, idx) => {
            setTimeout(() => {
                this.socket.emit('citizen-sos-report', report);
            }, idx * 500);
        });

        setTimeout(() => {
            localStorage.setItem("poz_offline_queue", JSON.stringify([]));
            this.playTone(880, 0.1);
            setTimeout(() => this.playTone(1320, 0.15), 120);
        }, queue.length * 500);
    }

    getHaversineDistance(lat1, lon1, lat2, lon2) {
        const R = 6371;
        const dLat = (lat2 - lat1) * Math.PI / 180;
        const dLon = (lon2 - lon1) * Math.PI / 180;
        const a = 
            Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * 
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return R * c;
    }

    playTone(freq, duration) {
        try {
            const ctx = new (window.AudioContext || window.webkitAudioContext)();
            const osc = ctx.createOscillator();
            const gain = ctx.createGain();
            
            osc.frequency.value = freq;
            osc.type = 'sine';
            
            gain.gain.setValueAtTime(0.08, ctx.currentTime);
            gain.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + duration);
            
            osc.connect(gain);
            gain.connect(ctx.destination);
            
            osc.start();
            osc.stop(ctx.currentTime + duration);
        } catch (e) {}
    }

    playEmergencySiren() {
        try {
            const ctx = new (window.AudioContext || window.webkitAudioContext)();
            const siren = (base, target, delay) => {
                const osc = ctx.createOscillator();
                const gain = ctx.createGain();
                
                osc.type = 'sawtooth';
                osc.frequency.setValueAtTime(base, ctx.currentTime + delay);
                osc.frequency.linearRampToValueAtTime(target, ctx.currentTime + delay + 0.3);
                osc.frequency.linearRampToValueAtTime(base, ctx.currentTime + delay + 0.6);
                
                gain.gain.setValueAtTime(0.0, ctx.currentTime + delay);
                gain.gain.linearRampToValueAtTime(0.08, ctx.currentTime + delay + 0.05);
                gain.gain.linearRampToValueAtTime(0.0, ctx.currentTime + delay + 0.6);
                
                osc.connect(gain);
                gain.connect(ctx.destination);
                
                osc.start(ctx.currentTime + delay);
                osc.stop(ctx.currentTime + delay + 0.6);
            };
            
            siren(600, 900, 0);
            siren(600, 900, 0.65);
        } catch (e) {}
    }
}

let mobileClient;
document.addEventListener("DOMContentLoaded", () => {
    mobileClient = new CitizenMobileClient();
});
