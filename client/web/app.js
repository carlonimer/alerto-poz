/* ==========================================================================
   ALERTO-POZ: CITIZEN MOBILE CLIENT ENGINE (RE-DESIGNED CONVERSATIONAL FLOW)
   ========================================================================= */

// --- DOM POLYFILL FOR WEB COMPATIBILITY ---
(function () {
    const originalGetElementById = document.getElementById.bind(document);
    document.getElementById = function (id) {
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

// Server connection path for hybrid native app environments
const SERVER_URL = (window.location.protocol === 'file:' || window.location.hostname === '' || window.location.port === '5500' || window.location.port === '5501')
    ? 'http://localhost:3000' // Handle VS Code Live Server & file:// testing; use 10.0.2.2 only if using Android Emulator without Capacitor HTTP server
    : window.location.origin;


class CitizenMobileClient {
    constructor() {
        this.socket = null;
        this.activeUser = null;
        this.gps = { ...POZORRUBIO_PLAZA };
        this.incidents = [];
        this.responders = [];
        this.responderMarkers = {};

        this.isOnline = navigator.onLine;
        this.selectedCategory = null;
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
        this.setupMapSettings();
        this.checkSession();
        this.initSocket();
        this.initNetworkMonitoring();
    }

    ensureAuthenticated(callback) {
        if (this.activeUser) {
            callback();
        } else {
            this.switchAuthCard("login");
            this.appView.classList.remove("active");
            if (this.loadingView) this.loadingView.classList.remove("active");
            this.authView.classList.add("active");
        }
    }

    initDOM() {
        // Auth Views
        this.loadingView = document.getElementById("view-loading");
        this.authView = document.getElementById("view-auth");
        this.appView = document.getElementById("view-app");
        this.loginCard = document.getElementById("auth-login-card");
        this.registerCard = document.getElementById("auth-register-card");
        this.otpCard = document.getElementById("auth-otp-card");
        this.forgotCard = document.getElementById("auth-forgot-card");
        this.resetCard = document.getElementById("auth-reset-card");
        this.forgotOtpCard = document.getElementById("auth-reset-otp-card");

        // Auth Forms
        this.loginForm = document.getElementById("login-form");
        this.registerForm = document.getElementById("register-form");
        this.otpForm = document.getElementById("otp-form");
        this.forgotForm = document.getElementById("forgot-form");
        this.resetForm = document.getElementById("reset-form");
        this.forgotOtpForm = document.getElementById("forgot-otp-form");

        // Forgot OTP elements
        this.forgotOtpBoxes = document.querySelectorAll(".forgot-otp-box");
        this.forgotOtpTargetLabel = document.getElementById("forgot-otp-target-label");
        this.forgotOtpTimerText = document.getElementById("forgot-otp-timer-text");
        this.btnForgotResendOtp = document.getElementById("btn-forgot-resend-otp");

        // Auth Navigation Toggles
        this.signupToggle = document.getElementById("signup-toggle-action");
        this.loginToggle = document.getElementById("login-toggle-action-text");
        this.gotoForgotBtn = document.getElementById("btn-goto-forgot");
        this.backAuthBtns = document.querySelectorAll(".btn-back-auth");

        // Registration Fields & Tabs
        this.methodBtns = document.querySelectorAll(".method-btn");
        this.regMethodError = document.getElementById("reg-method-error");
        this.groupRegPhone = document.getElementById("group-register-phone");
        this.groupRegEmail = document.getElementById("group-register-email");
        this.regPassword = document.getElementById("register-password");
        this.regConfirm = document.getElementById("register-confirm");

        // Password Checklist Items
        this.chkLength = document.getElementById("chk-length");
        this.chkUpper = document.getElementById("chk-upper");
        this.chkLower = document.getElementById("chk-lower");
        this.chkNumber = document.getElementById("chk-number");

        // Draft Conflict Modal
        this.modalDraftConflict = document.getElementById("modal-draft-conflict");
        this.btnContinueDraftPrompt = document.getElementById("btn-continue-draft");
        this.btnCancelDraftPrompt = document.getElementById("btn-cancel-draft-prompt");
        this.chkSpecial = document.getElementById("chk-special");

        // Reset Password Checklist Items
        this.resetPasswordInput = document.getElementById("reset-password-input");
        this.chkResetLength = document.getElementById("chk-reset-length");
        this.chkResetUpper = document.getElementById("chk-reset-upper");
        this.chkResetLower = document.getElementById("chk-reset-lower");
        this.chkResetNumber = document.getElementById("chk-reset-number");
        this.chkResetSpecial = document.getElementById("chk-reset-special");

        // OTP inputs
        this.otpBoxes = document.querySelectorAll("#auth-otp-card .otp-box");
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
        this.stateProfile = document.getElementById("state-profile");

        // Geolocation loader
        this.locationLoader = document.getElementById("location-loader");

        // Homepage items
        this.addressSearchInput = document.getElementById("address-search-input");
        this.gpsRecenterBtn = document.getElementById("gps-recenter");
        this.sosFab = document.getElementById("homepage-sos-fab");
        this.logoutBtn = document.getElementById("btn-profile-logout");
        this.btnProfile = document.getElementById("btn-profile");
        this.btnProfileBack = document.getElementById("btn-profile-back");

        // Pills
        this.pillFlood = document.getElementById("pill-flood");
        this.pillWater = document.getElementById("pill-water");

        // Bottom sheet Alerts Drawer
        this.alertsBadgeHome = document.getElementById("badge-alerts-home");
        this.alertsHistoryContainer = document.getElementById("broadcasts-history-list");

        // Chat View items
        this.btnChatOptClose = document.getElementById("btn-chat-opt-close");
        this.btnIncidentOptions = document.getElementById("btn-incident-options");
        this.chatOptionsMenu = document.getElementById("chat-options-menu");
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
        const inputWrapper = document.querySelector(".chat-input-wrapper");
        if (this.chatControlsFooter && inputWrapper) {
            this.chatControlsFooter.insertBefore(this.previewsContainer, inputWrapper);
        }


        // Conversational Elements
        this.chatMessagesContainer = document.getElementById("chat-messages-container");
        this.dynamicChatFeed = document.getElementById("dynamic-chat-feed");
        this.chatNotesForm = document.getElementById("chat-notes-form");
        this.chatDetailsInput = document.getElementById("chat-details-input");
        this.chatSendBtn = document.getElementById("btn-chat-send");

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

        // Forgot OTP Submit
        if (this.forgotOtpForm) {
            this.forgotOtpForm.addEventListener("submit", (e) => {
                e.preventDefault();
                this.handleForgotOtpSubmit();
            });
        }

        // Forgot OTP auto-tab
        this.forgotOtpBoxes.forEach((box, idx) => {
            box.addEventListener("input", (e) => {
                if (box.value && idx < this.forgotOtpBoxes.length - 1) {
                    this.forgotOtpBoxes[idx + 1].focus();
                }
            });
            box.addEventListener("keydown", (e) => {
                if (e.key === "Backspace" && !box.value && idx > 0) {
                    this.forgotOtpBoxes[idx - 1].focus();
                }
            });
        });

        // Forgot OTP Resend
        if (this.btnForgotResendOtp) {
            this.btnForgotResendOtp.addEventListener("click", () => {
                this.handleForgotResendOtp();
            });
        }

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
        this.methodBtns.forEach(btn => {
            btn.addEventListener("click", () => {
                this.methodBtns.forEach(b => b.classList.remove("active"));
                btn.classList.add("active");
                if (this.regMethodError) this.regMethodError.classList.add("hidden");

                const method = btn.getAttribute("data-method");
                if (method === "phone") {
                    this.groupRegPhone.classList.remove("hidden");
                    this.groupRegEmail.classList.add("hidden");
                    document.getElementById("register-email").value = "";
                    document.getElementById("register-email").required = false;
                    document.getElementById("register-phone").required = true;
                } else {
                    this.groupRegEmail.classList.remove("hidden");
                    this.groupRegPhone.classList.add("hidden");
                    document.getElementById("register-phone").value = "";
                    document.getElementById("register-phone").required = false;
                    document.getElementById("register-email").required = true;
                }
            });
        });

        // Password eye show/hide buttons
        const passwordToggles = document.querySelectorAll(".password-toggle-btn");
        passwordToggles.forEach(toggle => {
            const toggleVisibility = (e) => {
                e.preventDefault(); // Prevent input from losing focus
                const input = toggle.parentElement.querySelector("input");
                const icon = toggle.querySelector("i");
                if (input.type === "password") {
                    input.type = "text";
                    icon.className = "fa-solid fa-eye";
                } else {
                    input.type = "password";
                    icon.className = "fa-solid fa-eye-slash";
                }
            };
            toggle.addEventListener("click", toggleVisibility);
            toggle.addEventListener("touchstart", toggleVisibility, { passive: false });
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
                } else if (this.currentAuthCard === "forgotOtp") {
                    for (let i = 0; i < 6; i++) {
                        if (this.forgotOtpBoxes[i]) {
                            this.forgotOtpBoxes[i].value = code[i];
                        }
                    }
                    if (this.forgotOtpBoxes[5]) this.forgotOtpBoxes[5].focus();
                }
            }
        });

        this.devToastClose.addEventListener("click", () => {
            this.devOtpToast.classList.add("hidden");
        });

        this.gpsRecenterBtn.addEventListener("click", () => {
            this.locateMe();
        });

        // Logout listener moved to handle custom modal directly

        if (this.btnProfile) {
            this.btnProfile.addEventListener("click", () => this.ensureAuthenticated(() => this.transitionAppState("profile")));
        }

        if (this.btnProfileBack) {
            this.btnProfileBack.addEventListener("click", () => this.transitionAppState("homepage"));
        }

        this.pillFlood.addEventListener("click", () => this.ensureAuthenticated(() => this.toggleFloodLayer()));
        this.pillWater.addEventListener("click", () => this.ensureAuthenticated(() => this.toggleWaterLayer()));

        this.sosFab.addEventListener("click", () => this.ensureAuthenticated(() => this.triggerSOSFlow()));

        if (this.btnContinueDraftPrompt) {
            this.btnContinueDraftPrompt.addEventListener("click", () => {
                this.modalDraftConflict.classList.add("hidden");
                if (this.conflictIncident) {
                    this.continueDraft(this.conflictIncident);
                }
            });
        }

        if (this.btnCancelDraftPrompt) {
            this.btnCancelDraftPrompt.addEventListener("click", () => {
                this.modalDraftConflict.classList.add("hidden");
                if (this.conflictIncident) {
                    this.cancelDraft(this.conflictIncident.id);
                }
            });
        }


        // History Modal Listeners
        const btnMenuHistory = document.getElementById("btn-menu-history");
        const btnUserHistory = document.getElementById("btn-user-history");
        const btnHistoryBack = document.getElementById("btn-history-back");
        const modalHistory = document.getElementById("modal-history");

        const openHistory = () => {
            if (modalHistory) modalHistory.classList.remove("hidden");
            sessionStorage.setItem("alerto-last-modal", "history");
            this.loadHistory();
        };

        const closeHistory = () => {
            if (modalHistory) modalHistory.classList.add("hidden");
            sessionStorage.removeItem("alerto-last-modal");
        };

        if (btnMenuHistory) btnMenuHistory.addEventListener("click", () => this.ensureAuthenticated(openHistory));
        if (btnUserHistory) btnUserHistory.addEventListener("click", () => this.ensureAuthenticated(openHistory));
        if (btnHistoryBack) btnHistoryBack.addEventListener("click", closeHistory);

        // History Details Listeners
        const modalHistoryDetails = document.getElementById("modal-history-details");
        const btnHistoryDetailsBack = document.getElementById("btn-history-details-back");
        if (btnHistoryDetailsBack) {
            btnHistoryDetailsBack.addEventListener("click", () => {
                if (modalHistoryDetails) modalHistoryDetails.classList.add("hidden");
            });
        }

        // Search & Filters for History
        const historySearch = document.getElementById("history-search");
        const historyType = document.getElementById("history-filter-type");
        const historyStatus = document.getElementById("history-filter-status");

        const triggerRender = () => this.renderHistoryList();
        if (historySearch) historySearch.addEventListener("input", triggerRender);
        if (historyType) historyType.addEventListener("change", triggerRender);
        if (historyStatus) historyStatus.addEventListener("change", triggerRender);

        // 3-dot options menu toggle
        if (this.btnIncidentOptions && this.chatOptionsMenu) {
            this.btnIncidentOptions.addEventListener("click", (e) => {
                e.stopPropagation();
                this.chatOptionsMenu.classList.toggle("hidden");
            });

            // Close dropdown when clicking outside
            document.addEventListener("click", (e) => {
                if (!this.chatOptionsMenu.contains(e.target) && !this.btnIncidentOptions.contains(e.target)) {
                    this.chatOptionsMenu.classList.add("hidden");
                }
            });
        }

        if (this.btnChatOptClose) {
            this.btnChatOptClose.addEventListener("click", () => {
                this.chatOptionsMenu.classList.add("hidden"); // close dropdown first
                this.closeIncidentFlow();
            });
        }

        this.btnCopyIncident.addEventListener("click", () => {
            navigator.clipboard.writeText(this.chatIncidentId.textContent);
            alert("Incident ID copied to clipboard!");
        });

        const btnBell = document.getElementById("btn-notifications-bell");
        const alertsSheet = document.getElementById("alerts-sheet");
        const btnCloseAlertsSheet = document.getElementById("btn-close-alerts-sheet");
        const sheetDragHandle = document.getElementById("sheet-drag-handle");
        const alertsOverlay = document.getElementById("alerts-overlay");

        const toggleAlertsSheet = (forceClose = false) => {
            if (!alertsSheet) return;
            const isCollapsed = alertsSheet.classList.contains("collapsed");
            
            if (isCollapsed && !forceClose) {
                alertsSheet.classList.remove("collapsed");
                alertsSheet.classList.add("expanded");
                if (alertsOverlay) alertsOverlay.classList.remove("hidden");
            } else {
                alertsSheet.classList.remove("expanded");
                alertsSheet.classList.add("collapsed");
                if (alertsOverlay) alertsOverlay.classList.add("hidden");
            }
        };

        if (btnBell) {
            btnBell.addEventListener("click", () => {
                toggleAlertsSheet();
            });
        }
        if (btnCloseAlertsSheet) {
            btnCloseAlertsSheet.addEventListener("click", () => toggleAlertsSheet(true));
        }
        if (sheetDragHandle) {
            sheetDragHandle.addEventListener("click", () => toggleAlertsSheet(true));
        }
        if (alertsOverlay) {
            alertsOverlay.addEventListener("click", () => toggleAlertsSheet(true));
        }

        this.chatNotesForm.addEventListener("submit", (e) => {
            e.preventDefault();
            this.sendChatNotes();
        });

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



        // Plus (+) button clicks trigger file input dialog (Gallery)
        this.btnChatPlus.addEventListener("click", () => {
            this.mediaAttachmentInput.removeAttribute("capture");
            this.mediaAttachmentInput.setAttribute("accept", "image/*,video/*");
            this.mediaAttachmentInput.setAttribute("multiple", "multiple");
            this.mediaAttachmentInput.click();
        });

        this.cameraFacingMode = 'environment'; // Default to back camera for mobile web

        const startCamera = async (videoElement) => {
            if (this.cameraStream) {
                this.cameraStream.getTracks().forEach(track => track.stop());
            }
            try {
                this.cameraStream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: this.cameraFacingMode }, audio: false });
                videoElement.srcObject = this.cameraStream;
            } catch (err) {
                console.error("Camera access denied or unavailable", err);
                alert("Camera access denied or unavailable. Please check your browser permissions.");
                const modal = document.getElementById("modal-camera-capture");
                if (modal) modal.classList.add("hidden");
            }
        };

        const btnChatCamera = document.getElementById("btn-chat-camera");
        if (btnChatCamera) {
            btnChatCamera.addEventListener("click", async () => {
                const modal = document.getElementById("modal-camera-capture");
                const video = document.getElementById("camera-video-feed");
                if (modal && video) {
                    modal.classList.remove("hidden");
                    await startCamera(video);
                }
            });
        }

        const btnCameraSwitch = document.getElementById("btn-camera-switch");
        if (btnCameraSwitch) {
            btnCameraSwitch.addEventListener("click", async () => {
                this.cameraFacingMode = this.cameraFacingMode === 'environment' ? 'user' : 'environment';
                const video = document.getElementById("camera-video-feed");
                if (video) {
                    await startCamera(video);
                }
            });
        }

        // Camera modal button listeners
        const btnCameraCancel = document.getElementById("btn-camera-cancel");
        const btnCameraCancelPreview = document.getElementById("btn-camera-cancel-preview");
        
        const closeCameraModal = () => {
            const modal = document.getElementById("modal-camera-capture");
            if (modal) modal.classList.add("hidden");
            if (this.cameraStream) {
                this.cameraStream.getTracks().forEach(track => track.stop());
                this.cameraStream = null;
            }
            // Reset to capture phase
            const video = document.getElementById("camera-video-feed");
            const preview = document.getElementById("camera-preview-img");
            const actionsCapture = document.getElementById("camera-actions-capture");
            const actionsPreview = document.getElementById("camera-actions-preview");
            if (video) video.style.display = "";
            if (preview) { preview.style.display = "none"; preview.src = ""; }
            if (actionsCapture) actionsCapture.style.display = "flex";
            if (actionsPreview) actionsPreview.style.display = "none";
            this.capturedCameraBlob = null;
        };

        if (btnCameraCancel) btnCameraCancel.addEventListener("click", closeCameraModal);
        if (btnCameraCancelPreview) btnCameraCancelPreview.addEventListener("click", closeCameraModal);

        // Capture button — take snapshot and show preview
        const btnCameraCapture = document.getElementById("btn-camera-capture");
        if (btnCameraCapture) {
            btnCameraCapture.addEventListener("click", () => {
                const video = document.getElementById("camera-video-feed");
                const canvas = document.getElementById("camera-canvas");
                const preview = document.getElementById("camera-preview-img");
                const actionsCapture = document.getElementById("camera-actions-capture");
                const actionsPreview = document.getElementById("camera-actions-preview");
                if (video && canvas) {
                    canvas.width = video.videoWidth;
                    canvas.height = video.videoHeight;
                    const ctx = canvas.getContext("2d");
                    ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
                    
                    // Show preview, hide live feed
                    const dataUrl = canvas.toDataURL("image/jpeg", 0.9);
                    if (preview) { preview.src = dataUrl; preview.style.display = "block"; }
                    video.style.display = "none";
                    if (actionsCapture) actionsCapture.style.display = "none";
                    if (actionsPreview) actionsPreview.style.display = "flex";
                    
                    // Store the blob for later confirm
                    canvas.toBlob((blob) => {
                        this.capturedCameraBlob = blob;
                    }, "image/jpeg", 0.9);
                }
            });
        }

        // Retake button — go back to live camera feed
        const btnCameraRetake = document.getElementById("btn-camera-retake");
        if (btnCameraRetake) {
            btnCameraRetake.addEventListener("click", () => {
                const video = document.getElementById("camera-video-feed");
                const preview = document.getElementById("camera-preview-img");
                const actionsCapture = document.getElementById("camera-actions-capture");
                const actionsPreview = document.getElementById("camera-actions-preview");
                if (video) video.style.display = "";
                if (preview) { preview.style.display = "none"; preview.src = ""; }
                if (actionsCapture) actionsCapture.style.display = "flex";
                if (actionsPreview) actionsPreview.style.display = "none";
                this.capturedCameraBlob = null;
            });
        }

        // Confirm button — send the captured photo
        const btnCameraConfirm = document.getElementById("btn-camera-confirm");
        if (btnCameraConfirm) {
            btnCameraConfirm.addEventListener("click", () => {
                if (this.capturedCameraBlob) {
                    const file = new File([this.capturedCameraBlob], "camera-capture.jpg", { type: "image/jpeg" });
                    const fakeEvent = {
                        target: {
                            files: [file],
                            value: ""
                        }
                    };
                    this.handleMediaUpload(fakeEvent);
                }
                closeCameraModal();
            });
        }

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

        this.initProfileEvents();
    }

    initProfileEvents() {
        // Back Button
        document.getElementById("btn-profile-back").addEventListener("click", () => {
            this.transitionAppState("home");
        });

        // Logout
        document.getElementById("btn-profile-logout").addEventListener("click", () => {
            document.getElementById("modal-logout-confirm").classList.remove("hidden");
        });
        document.getElementById("btn-cancel-logout").addEventListener("click", () => {
            document.getElementById("modal-logout-confirm").classList.add("hidden");
        });
        document.getElementById("btn-confirm-logout").addEventListener("click", () => {
            document.getElementById("modal-logout-confirm").classList.add("hidden");
            this.handleLogoutToggle(true); // pass true to bypass native confirm
        });

        // Map Settings
        document.getElementById("btn-menu-mapsettings").addEventListener("click", async () => {
            document.getElementById("modal-map-settings").classList.remove("hidden");
            try {
                const res = await fetch(`${SERVER_URL}/api/user/map-settings/${this.activeUser.id}`);
                const data = await res.json();
                if (data && data.user_id) {
                    document.getElementById("setting-map-type").value = data.map_type;
                    document.getElementById("setting-nav-pref").value = data.navigation_preference;
                    document.getElementById("setting-notif-rad").value = data.notification_radius;
                    document.getElementById("val-notif-rad").innerText = data.notification_radius;
                    document.getElementById("setting-alert-rad").value = data.emergency_alert_radius;
                    document.getElementById("val-alert-rad").innerText = data.emergency_alert_radius;
                    document.getElementById("setting-live-location").checked = !!data.live_location;
                    document.getElementById("setting-gps-enabled").checked = !!data.gps_enabled;
                    document.getElementById("setting-real-time-tracking").checked = !!data.real_time_tracking;
                    document.getElementById("setting-show-traffic").checked = !!data.show_traffic;
                    document.getElementById("setting-show-disaster").checked = !!data.show_disaster_zones;
                    document.getElementById("setting-show-evacuation").checked = !!data.show_evacuation_centers;
                    document.getElementById("setting-show-boundaries").checked = !!data.show_barangay_boundaries;
                    document.getElementById("setting-auto-refresh").checked = !!data.auto_refresh;
                    document.getElementById("setting-dark-mode").checked = !!data.dark_mode;
                }
            } catch (e) { console.error(e); }
        });

        document.getElementById("setting-notif-rad").addEventListener("input", (e) => {
            document.getElementById("val-notif-rad").innerText = e.target.value;
        });
        document.getElementById("setting-alert-rad").addEventListener("input", (e) => {
            document.getElementById("val-alert-rad").innerText = e.target.value;
        });

        document.getElementById("btn-cancel-map-settings").addEventListener("click", () => {
            document.getElementById("modal-map-settings").classList.add("hidden");
        });

        document.getElementById("btn-save-map-settings").addEventListener("click", async () => {
            const payload = {
                user_id: this.activeUser.id,
                map_type: document.getElementById("setting-map-type").value,
                navigation_preference: document.getElementById("setting-nav-pref").value,
                notification_radius: parseInt(document.getElementById("setting-notif-rad").value),
                emergency_alert_radius: parseInt(document.getElementById("setting-alert-rad").value),
                live_location: document.getElementById("setting-live-location").checked ? 1 : 0,
                gps_enabled: document.getElementById("setting-gps-enabled").checked ? 1 : 0,
                real_time_tracking: document.getElementById("setting-real-time-tracking").checked ? 1 : 0,
                show_traffic: document.getElementById("setting-show-traffic").checked ? 1 : 0,
                show_disaster_zones: document.getElementById("setting-show-disaster").checked ? 1 : 0,
                show_evacuation_centers: document.getElementById("setting-show-evacuation").checked ? 1 : 0,
                show_barangay_boundaries: document.getElementById("setting-show-boundaries").checked ? 1 : 0,
                auto_refresh: document.getElementById("setting-auto-refresh").checked ? 1 : 0,
                dark_mode: document.getElementById("setting-dark-mode").checked ? 1 : 0
            };
            try {
                await fetch(`${SERVER_URL}/api/user/map-settings`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(payload)
                });
                alert("Map settings saved.");
                document.getElementById("modal-map-settings").classList.add("hidden");
            } catch (e) { alert("Failed to save settings."); }
        });

        // Duplicate passcode listeners removed to prevent double firing        // Edit Profile
        document.getElementById("btn-open-edit-profile").addEventListener("click", () => {
            document.getElementById("modal-edit-profile").classList.remove("hidden");
            document.getElementById("edit-profile-firstname").value = this.activeUser.first_name || '';
            document.getElementById("edit-profile-middlename").value = this.activeUser.middle_name || '';
            document.getElementById("edit-profile-lastname").value = this.activeUser.last_name || '';
            document.getElementById("edit-profile-suffix").value = this.activeUser.suffix || '';
            document.getElementById("edit-profile-birthdate").value = this.activeUser.birthdate || '';
            document.getElementById("edit-profile-gender").value = this.activeUser.gender || '';
            document.getElementById("edit-profile-address").value = this.activeUser.address || '';
            document.getElementById("edit-profile-email").value = this.activeUser.email || '';
            document.getElementById("edit-profile-phone").value = this.activeUser.phone || '';
        });

        document.getElementById("btn-cancel-edit-profile").addEventListener("click", () => {
            document.getElementById("modal-edit-profile").classList.add("hidden");
        });

        document.getElementById("btn-save-edit-profile").addEventListener("click", async () => {
            const first = document.getElementById("edit-profile-firstname").value.trim();
            const last = document.getElementById("edit-profile-lastname").value.trim();
            const email = document.getElementById("edit-profile-email").value.trim();
            const phone = document.getElementById("edit-profile-phone").value.trim();

            if (!first || !last) return alert("First and Last name are required.");
            if (!email && !phone) return alert("Email or Phone number is required.");

            const payload = {
                id: this.activeUser.id,
                name: `${first} ${last}`,
                first_name: first,
                middle_name: document.getElementById("edit-profile-middlename").value.trim(),
                last_name: last,
                suffix: document.getElementById("edit-profile-suffix").value.trim(),
                birthdate: document.getElementById("edit-profile-birthdate").value,
                gender: document.getElementById("edit-profile-gender").value,
                address: document.getElementById("edit-profile-address").value.trim(),
                email: email,
                phone: phone,
                profile_image: this.activeUser.profile_image
            };

            try {
                const res = await fetch(`${SERVER_URL}/api/user/profile`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(payload)
                });
                const data = await res.json();
                if (res.ok) {
                    alert("Profile updated successfully!");
                    document.getElementById("modal-edit-profile").classList.add("hidden");
                } else {
                    alert(data.error || "Update failed.");
                }
            } catch (e) { alert("Network error."); }
        });

        // Feedback
        document.getElementById("btn-menu-feedback").addEventListener("click", () => {
            document.getElementById("modal-feedback").classList.remove("hidden");
            document.getElementById("feedback-subject").value = "";
            document.getElementById("feedback-message").value = "";
            document.getElementById("feedback-media-preview").style.display = "none";
            document.getElementById("feedback-media-upload").value = "";
        });

        document.getElementById("btn-cancel-feedback").addEventListener("click", () => {
            document.getElementById("modal-feedback").classList.add("hidden");
        });

        document.getElementById("btn-feedback-screenshot").addEventListener("click", () => {
            document.getElementById("feedback-media-upload").click();
        });

        document.getElementById("feedback-media-upload").addEventListener("change", (e) => {
            const file = e.target.files[0];
            if (file) {
                if (file.size > 5 * 1024 * 1024) return alert("File size must be less than 5MB");
                const reader = new FileReader();
                reader.onload = (ev) => {
                    document.getElementById("feedback-media-preview").src = ev.target.result;
                    document.getElementById("feedback-media-preview").style.display = "block";
                };
                reader.readAsDataURL(file);
            }
        });

        document.getElementById("btn-save-feedback").addEventListener("click", async () => {
            const subject = document.getElementById("feedback-subject").value.trim();
            const message = document.getElementById("feedback-message").value.trim();
            const category = document.getElementById("feedback-category").value;
            const imgEl = document.getElementById("feedback-media-preview");
            const media_path = imgEl.style.display !== "none" ? imgEl.src : null;

            if (!subject || !message) return alert("Subject and Message are required.");

            try {
                const res = await fetch(`${SERVER_URL}/api/feedback`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ user_id: this.activeUser.id, subject, category, message, media_path })
                });
                if (res.ok) {
                    alert("Feedback submitted successfully!");
                    document.getElementById("modal-feedback").classList.add("hidden");
                } else {
                    alert("Failed to submit feedback.");
                }
            } catch (e) { alert("Network error."); }
        });

        // Profile Picture Upload & Crop
        let cropper = null;
        document.getElementById("btn-edit-avatar").addEventListener("click", () => {
            document.getElementById("profile-image-upload").click();
        });

        document.getElementById("profile-image-upload").addEventListener("change", (e) => {
            const file = e.target.files[0];
            if (!file) return;
            if (file.size > 5 * 1024 * 1024) return alert("File size must be less than 5MB");

            const reader = new FileReader();
            reader.onload = (ev) => {
                document.getElementById("modal-image-crop").classList.remove("hidden");
                const image = document.getElementById("cropper-image");
                image.src = ev.target.result;

                if (cropper) cropper.destroy();
                // Ensure the modal is visible before initializing cropper so it calculates dimensions correctly
                setTimeout(() => {
                    if (window.Cropper) {
                        cropper = new Cropper(image, {
                            aspectRatio: 1,
                            viewMode: 1
                        });
                    } else {
                        alert("Image cropping library not loaded yet.");
                        document.getElementById("modal-image-crop").classList.add("hidden");
                    }
                }, 100);
            };
            reader.readAsDataURL(file);
            e.target.value = "";
        });

        document.getElementById("btn-cancel-crop").addEventListener("click", () => {
            document.getElementById("modal-image-crop").classList.add("hidden");
            if (cropper) cropper.destroy();
            cropper = null;
        });

        document.getElementById("btn-crop-zoom-in").addEventListener("click", () => cropper && cropper.zoom(0.1));
        document.getElementById("btn-crop-zoom-out").addEventListener("click", () => cropper && cropper.zoom(-0.1));
        document.getElementById("btn-crop-rotate-left").addEventListener("click", () => cropper && cropper.rotate(-90));
        document.getElementById("btn-crop-rotate-right").addEventListener("click", () => cropper && cropper.rotate(90));

        document.getElementById("btn-save-crop").addEventListener("click", () => {
            if (!cropper) return;
            const canvas = cropper.getCroppedCanvas({ width: 400, height: 400 });

            canvas.toBlob(async (blob) => {
                const formData = new FormData();
                formData.append('id', this.activeUser.id);
                formData.append('profile_image', blob, 'avatar.jpg');

                try {
                    const res = await fetch(`${SERVER_URL}/api/user/profile-picture`, {
                        method: 'POST',
                        body: formData
                    });
                    if (res.ok) {
                        alert("Profile picture updated!");
                        document.getElementById("modal-image-crop").classList.add("hidden");
                        cropper.destroy();
                        cropper = null;
                    } else {
                        alert("Failed to upload picture.");
                    }
                } catch (e) { alert("Network error."); }
            }, "image/jpeg", 0.9);
        });
    }

    initSocket() {
        this.socket = io(SERVER_URL);

        this.socket.on('connect', () => {
            console.log("WebSocket connected successfully");
            this.isOnline = true;
            this.syncOfflineQueue();
        });

        this.socket.on('init-state', (db) => {
            if (db && db.responders) {
                this.responders = db.responders;
                this.updateRespondersOnMap();
            }
        });

        this.socket.on('responder-updated', (responder) => {
            const idx = this.responders.findIndex(r => r.id === responder.id);
            if (idx !== -1) {
                this.responders[idx] = responder;
            } else {
                this.responders.push(responder);
            }
            this.updateRespondersOnMap();
        });

        this.socket.on('disconnect', () => {
            console.log("WebSocket disconnected");
            this.isOnline = false;
        });

        this.socket.on('broadcast-advisory', (data) => {
            this.receiveBroadcastAlert(data);
        });

        this.socket.on('chat-message-receive', (msg) => {
            if (this.activeIncident && String(this.activeIncident.id) === String(msg.incident_id)) {
                // If it's not from us, append it
                if (String(msg.sender_id) !== String(this.activeUser.id)) {
                    const senderName = msg.sender_role === 'Citizen App' ? 'Citizen' : 'Command Center';
                    const bubbleClass = 'incoming-bubble';

                    if (msg.message_type === 'text' && msg.message_content) {
                        this.appendChatMessage(senderName, msg.message_content, bubbleClass, msg.timestamp, msg.sender_profile_image, msg.sender_gender);
                    } else if ((msg.message_type === 'image' || msg.message_type === 'video') && msg.media_url) {
                        const attObj = {
                            type: msg.message_type,
                            data: `${SERVER_URL}${msg.media_url}`
                        };
                        this.appendMediaMessageBubble(attObj, senderName, bubbleClass, msg.timestamp, msg.sender_profile_image, msg.sender_gender);
                    }
                }
            }
        });

        this.socket.on('incident-updated', (incident) => {
            if (this.activeIncident && this.activeIncident.id === incident.id) {
                this.activeIncident = incident;
                this.syncActiveIncidentStatus();
            }
            // Auto-refresh history if modal is active
            const modalHistory = document.getElementById("modal-history");
            if (modalHistory && !modalHistory.classList.contains("hidden")) {
                this.loadHistory();
            }
        });

        this.socket.on('responder-updated', (responder) => {
            if (this.activeIncident && this.activeIncident.assignedUnit === responder.id) {
                this.syncResponderStatus(responder);
            }
        });

        this.socket.on('profile-updated', (user) => {
            if (this.activeUser && this.activeUser.id === user.id) {
                // If it contains more than just ID, it's a full update
                if (user.name) {
                    this.activeUser = user;
                    if (sessionStorage.getItem('alerto-user')) {
                        sessionStorage.setItem("alerto-user", JSON.stringify(this.activeUser)); // sync local copy
                    } else {
                        localStorage.setItem("alerto-user", JSON.stringify(this.activeUser)); // sync local copy
                    }

                    // Sync UI
                    this.syncProfileUI();
                }
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

    async checkSession() {
        let token = localStorage.getItem("alerto-token");
        let userStr = localStorage.getItem("alerto-user");
        let isSessionStorage = false;

        if (!token) {
            token = sessionStorage.getItem("alerto-token");
            userStr = sessionStorage.getItem("alerto-user");
            isSessionStorage = true;
        }

        if (token && userStr) {
            try {
                const res = await fetch(`${SERVER_URL}/api/auth/validate`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ token })
                });

                const data = await res.json();
                if (res.ok && data.valid) {
                    this.activeUser = data.user;
                    if (isSessionStorage) {
                        sessionStorage.setItem("alerto-user", JSON.stringify(this.activeUser)); // sync local copy
                    } else {
                        localStorage.setItem("alerto-user", JSON.stringify(this.activeUser)); // sync local copy
                    }

                    this.authView.classList.remove("active");
                    if (this.loadingView) this.loadingView.classList.remove("active");
                    this.appView.classList.add("active");
                    this.logoutBtn.textContent = "LOG OUT";
                    this.logoutBtn.style.backgroundColor = "#ff3b30";
                    this.logoutBtn.style.color = "white";
                    if (this.btnProfile) this.btnProfile.textContent = "PROFILE";

                    this.initHomepageMap();
                    this.refreshGPS(false);
                    this.syncBroadcastsFeed();

                    // Restore active incident state from backend (Single Source of Truth)
                    try {
                        const activeRes = await fetch(`${SERVER_URL}/api/incidents/active/${this.activeUser.id}`);
                        if (activeRes.ok) {
                            const activeData = await activeRes.json();
                            if (activeData.success && activeData.active && activeData.incident) {
                                this.activeIncident = activeData.incident;
                                localStorage.setItem("alerto-active-incident", JSON.stringify(this.activeIncident));
                            } else {
                                this.activeIncident = null;
                                localStorage.removeItem("alerto-active-incident");
                            }
                        }
                    } catch (e) {
                        console.error("Failed to fetch active incident from server, checking local storage", e);
                        const savedIncident = localStorage.getItem("alerto-active-incident");
                        if (savedIncident) {
                            try { this.activeIncident = JSON.parse(savedIncident); } catch (e) {}
                        }
                    }

                    if (this.activeIncident) {
                        try {
                            // Restore UI for ID and time
                            if (this.activeIncident.id && String(this.activeIncident.id) !== "draft") {
                                this.chatIncidentId.textContent = this.activeIncident.id;
                            }

                            const dt = new Date(this.activeIncident.createdAt || Date.now());
                            const timeString = new Intl.DateTimeFormat('en-US', {
                                timeZone: 'Asia/Manila', month: 'short', day: '2-digit', year: 'numeric',
                                hour: '2-digit', minute: '2-digit', hour12: true
                            }).format(dt);
                            this.chatIncidentTime.textContent = timeString;

                            if (this.activeIncident.category) {
                                this.selectedCategory = this.activeIncident.category;

                                // Only hide the selection grid if the user has ALREADY sent the emergency
                                if (this.activeIncident.has_sent_messages || this.activeIncident.status !== 'draft') {
                                    // Hide category selection grid
                                    const catGrid = document.querySelector(".emergency-categories-grid");
                                    if (catGrid) {
                                        catGrid.closest(".chat-message-bubble").style.display = "none";
                                    }
                                } else {
                                    // Make sure the previously selected category button looks active
                                    const categoryButtons = document.querySelectorAll(".chat-category-btn");
                                    categoryButtons.forEach(b => {
                                        if (b.getAttribute("data-cat") === this.selectedCategory) {
                                            b.classList.add("active");
                                        }
                                    });
                                }
                            }

                            this.syncActiveIncidentStatus();
                            await this.restoreChatHistory();
                            
                            if (this.activeIncident.status !== 'draft') {
                                this.appendChatMessage("System", "Emergency session restored.", "incoming-bubble", Date.now());
                            }
                        } catch (e) {
                            console.error("Failed to restore UI for active incident", e);
                        }
                    }

                    // Always restore the session UI (Chat screen) if there is an active emergency
                    let lastState = this.activeIncident ? "chat" : "homepage";

                    if (lastState && ["homepage", "home", "chat", "profile"].includes(lastState)) {
                        this.transitionAppState(lastState);
                    } else {
                        this.transitionAppState("homepage");
                    }

                    const lastModal = sessionStorage.getItem("alerto-last-modal");
                    if (lastModal === "history") {
                        document.getElementById("modal-history").classList.remove("hidden");
                    }
                } else {
                    throw new Error("Invalid session");
                }
            } catch (e) {
                console.error("Session validation failed:", e);
                // Optimistic offline login
                if (e.name === 'TypeError') {
                    console.log("Offline or server unreachable, using cached session.");
                    this.activeUser = JSON.parse(userStr);
                    this.authView.classList.remove("active");
                    if (this.loadingView) this.loadingView.classList.remove("active");
                    this.appView.classList.add("active");
                    this.logoutBtn.textContent = "LOG OUT";
                    this.logoutBtn.style.backgroundColor = "#ff3b30";
                    this.logoutBtn.style.color = "white";
                    if (this.btnProfile) this.btnProfile.textContent = "PROFILE";

                    this.initHomepageMap();
                    this.refreshGPS(false);
                    this.syncBroadcastsFeed();

                    // Always force the user to the homepage on reload
                    let lastState = "homepage";

                    if (lastState && ["homepage", "home", "chat", "profile"].includes(lastState)) {
                        this.transitionAppState(lastState);
                    } else {
                        this.transitionAppState("homepage");
                    }

                    const lastModal = sessionStorage.getItem("alerto-last-modal");
                    if (lastModal === "history") {
                        document.getElementById("modal-history").classList.remove("hidden");
                    }
                } else {
                    this.clearLocalSession();
                }
            }
        } else {
            this.clearLocalSession();
        }
    }

    clearLocalSession() {
        this.activeUser = null;
        localStorage.removeItem("alerto-token");
        localStorage.removeItem("alerto-user");
        localStorage.removeItem("alerto-last-state");
        sessionStorage.removeItem("alerto-token");
        sessionStorage.removeItem("alerto-user");
        sessionStorage.removeItem("alerto-last-state");
        if (this.btnProfile) this.btnProfile.textContent = "LOGIN";

        // Show login if no session is available and currently loading
        if (this.appView) this.appView.classList.remove("active");
        if (this.loadingView) this.loadingView.classList.remove("active");
        if (this.authView) this.authView.classList.add("active");
        this.switchAuthCard("login");
    }

    handleLogoutToggle(skipConfirm = false) {
        if (!this.activeUser) {
            this.switchAuthCard("login");
            this.appView.classList.remove("active");
            this.authView.classList.add("active");
            return;
        }

        if (!skipConfirm) {
            const conf = confirm("Are you sure you want to log out?");
            if (!conf) return;
        }

        this.clearLocalSession();
        this.logoutBtn.textContent = "LOG IN / REGISTER";
        this.logoutBtn.style.backgroundColor = "#007aff";
        this.logoutBtn.style.color = "white";
        if (this.btnProfile) this.btnProfile.textContent = "LOGIN";

        this.switchAuthCard("login");
        this.appView.classList.remove("active");
        this.authView.classList.add("active");
    }

    switchAuthCard(cardName) {
        this.currentAuthCard = cardName;

        // Clear OTP inputs when switching cards to avoid stale data
        if (this.otpBoxes) this.otpBoxes.forEach(box => box.value = "");
        if (this.forgotOtpBoxes) this.forgotOtpBoxes.forEach(box => box.value = "");

        // Hide all cards
        this.loginCard.classList.add("hidden");
        this.registerCard.classList.add("hidden");
        this.otpCard.classList.add("hidden");
        this.forgotCard.classList.add("hidden");
        this.resetCard.classList.add("hidden");
        if (this.forgotOtpCard) this.forgotOtpCard.classList.add("hidden");

        // Hide dev toast on transitions
        this.devOtpToast.classList.add("hidden");

        if (cardName === "login") {
            this.loginCard.classList.remove("hidden");
        } else if (cardName === "register") {
            this.registerCard.classList.remove("hidden");
            this.registerForm.reset();
            this.validatePasswordStrength("", "register");
            if (this.methodBtns) {
                this.methodBtns.forEach(b => b.classList.remove("active"));
            }
            if (this.groupRegPhone) this.groupRegPhone.classList.add("hidden");
            if (this.groupRegEmail) this.groupRegEmail.classList.add("hidden");
            document.getElementById("register-phone").required = false;
            document.getElementById("register-email").required = false;
            if (this.regMethodError) this.regMethodError.classList.add("hidden");
        } else if (cardName === "otp") {
            this.otpCard.classList.remove("hidden");
            this.otpForm.reset();
            setTimeout(() => this.otpBoxes[0].focus(), 100);
        } else if (cardName === "forgot") {
            this.forgotCard.classList.remove("hidden");
            this.forgotForm.reset();
        } else if (cardName === "forgotOtp") {
            if (this.forgotOtpCard) {
                this.forgotOtpCard.classList.remove("hidden");
                if (this.forgotOtpForm) this.forgotOtpForm.reset();
                setTimeout(() => { if (this.forgotOtpBoxes[0]) this.forgotOtpBoxes[0].focus(); }, 100);
                this.startForgotOtpTimer();
            }
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
        if (loginBtn.disabled) return;
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
                    ? `OTP sent to your email: ${this.maskContact(data.target)}`
                    : `OTP sent via SMS: ${this.maskContact(data.target)}`;

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

    maskContact(target) {
        if (!target) return "";
        if (target.includes("@")) {
            const parts = target.split("@");
            if (parts[0].length <= 2) return target;
            return parts[0].substring(0, 2) + "***@" + parts[1];
        } else {
            return target.substring(0, 4) + "****" + target.substring(target.length - 3);
        }
    }

    async handleRegisterSubmit() {
        const activeMethodBtn = document.querySelector(".method-btn.active");
        if (!activeMethodBtn) {
            if (this.regMethodError) this.regMethodError.classList.remove("hidden");
            return;
        }

        const isEmailMode = activeMethodBtn.getAttribute("data-method") === "email";
        const name = document.getElementById("register-name").value.trim();
        const email = isEmailMode ? document.getElementById("register-email").value.trim() : "";
        const phone = !isEmailMode ? document.getElementById("register-phone").value.trim() : "";
        const password = document.getElementById("register-password").value;
        const confirm = document.getElementById("register-confirm").value;

        if (!name) {
            alert("Please enter your full name.");
            return;
        }

        if (isEmailMode) {
            if (!email) {
                alert("Please enter your email address.");
                return;
            }
            const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
            if (!emailRegex.test(email)) {
                alert("Please enter a valid email address.");
                return;
            }
        } else {
            if (!phone) {
                alert("Please enter your phone number.");
                return;
            }
            const phoneRegex = /^(09|\+639)\d{9}$/;
            if (!phoneRegex.test(phone)) {
                alert("Please enter a valid Philippine mobile number (e.g. 09123456789 or +639123456789).");
                return;
            }
        }

        if (!password) {
            alert("Password is required.");
            return;
        }

        if (!confirm || password !== confirm) {
            alert("Passwords do not match.");
            return;
        }

        if (!this.validatePasswordStrength(password, "register")) {
            alert("Password does not meet the complexity requirements.");
            return;
        }

        const registerBtn = document.getElementById("btn-register-submit");
        if (registerBtn.disabled) return;
        const originalText = registerBtn.innerHTML;
        registerBtn.disabled = true;
        registerBtn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Registering...';

        try {
            const res = await fetch(`${SERVER_URL}/api/auth/register`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    name,
                    email: isEmailMode ? email : undefined,
                    phone: !isEmailMode ? phone : undefined,
                    password,
                    registrationMethod: isEmailMode ? "email" : "phone"
                })
            });
            const data = await res.json();

            if (!res.ok) {
                alert(data.error || "Registration failed.");
            } else {
                this.otpSession = {
                    target: data.target,
                    type: 'register',
                    rememberMe: true
                };

                this.switchAuthCard("otp");
                this.otpTargetLabel.textContent = data.target.includes('@')
                    ? `OTP sent to email: ${this.maskContact(data.target)}`
                    : `OTP sent via SMS: ${this.maskContact(data.target)}`;

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
        if (otpBtn.disabled) return;
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
                otpBtn.disabled = false;
                otpBtn.innerHTML = originalText;
                alert(data.error || "Verification failed.");
                return;
            }

            if (this.otpSession.type === 'register') {
                alert("Account created successfully. You can now sign in.");
                this.switchAuthCard("login");
                this.otpSession = null;
            } else {
                alert("Verification successful!");

                if (this.otpSession.rememberMe) {
                    localStorage.setItem("alerto-token", data.token);
                    localStorage.setItem("alerto-user", JSON.stringify(data.user));
                } else {
                    sessionStorage.setItem("alerto-token", data.token);
                    sessionStorage.setItem("alerto-user", JSON.stringify(data.user));
                }

                this.activeUser = data.user;
                this.logoutBtn.textContent = "LOG OUT";
                this.logoutBtn.style.backgroundColor = "#ff3b30";
                this.logoutBtn.style.color = "white";
                if (this.btnProfile) this.btnProfile.textContent = "PROFILE";

                if (this.devOtpToast) this.devOtpToast.classList.add("hidden");
                this.authView.classList.remove("active");
                this.appView.classList.add("active");

                this.initHomepageMap();
                this.refreshGPS(false);
                this.syncBroadcastsFeed();
            }
        } catch (e) {
            console.error(e);
            otpBtn.disabled = false;
            otpBtn.innerHTML = originalText;
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
        if (forgotBtn.disabled) return;
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

            this.forgotSession = {
                target,
                type: 'forgot'
            };

            // Show the forgot OTP verification card
            this.switchAuthCard("forgotOtp");
            if (this.forgotOtpTargetLabel) {
                this.forgotOtpTargetLabel.textContent = target.includes('@')
                    ? `Code sent to ${this.maskContact(target)}`
                    : `Code sent via SMS to ${this.maskContact(target)}`;
            }
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

    startForgotOtpTimer() {
        if (this.forgotOtpInterval) clearInterval(this.forgotOtpInterval);
        let remaining = 300; // 5 minutes
        this.forgotResendCooldown = 60;

        if (this.btnForgotResendOtp) {
            this.btnForgotResendOtp.disabled = true;
            this.btnForgotResendOtp.classList.add("disabled");
            this.btnForgotResendOtp.textContent = `Resend Code (60s)`;
        }

        this.forgotOtpInterval = setInterval(() => {
            remaining--;
            this.forgotResendCooldown--;

            const mins = Math.floor(remaining / 60);
            const secs = remaining % 60;
            if (this.forgotOtpTimerText) {
                this.forgotOtpTimerText.textContent = `Code expires in ${mins}:${secs.toString().padStart(2, '0')}`;
            }

            if (this.forgotResendCooldown > 0 && this.btnForgotResendOtp) {
                this.btnForgotResendOtp.textContent = `Resend Code (${this.forgotResendCooldown}s)`;
            } else if (this.forgotResendCooldown <= 0 && this.btnForgotResendOtp) {
                this.btnForgotResendOtp.disabled = false;
                this.btnForgotResendOtp.classList.remove("disabled");
                this.btnForgotResendOtp.textContent = "Resend Code";
            }

            if (remaining <= 0) {
                clearInterval(this.forgotOtpInterval);
                if (this.forgotOtpTimerText) {
                    this.forgotOtpTimerText.textContent = "Code expired. Please resend.";
                }
            }
        }, 1000);
    }

    async handleForgotResendOtp() {
        if (!this.forgotSession) return;

        this.btnForgotResendOtp.disabled = true;
        this.btnForgotResendOtp.textContent = "Sending...";

        try {
            const res = await fetch(`${SERVER_URL}/api/auth/resend-otp`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    target: this.forgotSession.target,
                    type: 'forgot'
                })
            });

            const data = await res.json();
            if (!res.ok) {
                alert(data.error || "Resend failed.");
                return;
            }

            this.devOtpCode.textContent = data.otpDevVal;
            this.devOtpToast.classList.remove("hidden");
            this.startForgotOtpTimer();
        } catch (e) {
            console.error(e);
            alert("Resend failed. Network connection error.");
        }
    }

    async handleForgotOtpSubmit() {
        if (!this.forgotSession) return;

        let code = "";
        this.forgotOtpBoxes.forEach(box => {
            code += box.value;
        });

        if (code.length < 6) {
            alert("Please enter the complete 6-digit verification code.");
            return;
        }

        const otpBtn = document.getElementById("btn-forgot-otp-submit");
        if (otpBtn.disabled) return;
        const originalText = otpBtn.innerHTML;
        otpBtn.disabled = true;
        otpBtn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Verifying...';

        try {
            const res = await fetch(`${SERVER_URL}/api/auth/verify-otp`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    target: this.forgotSession.target,
                    code,
                    type: 'forgot'
                })
            });

            const data = await res.json();
            if (!res.ok) {
                otpBtn.disabled = false;
                otpBtn.innerHTML = originalText;
                alert(data.error || "Verification failed.");
                return;
            }

            // OTP verified! Store the reset token and go to password page
            if (this.forgotOtpInterval) clearInterval(this.forgotOtpInterval);
            this.forgotSession.resetToken = data.reset_token;
            this.switchAuthCard("reset");
        } catch (e) {
            console.error(e);
            otpBtn.disabled = false;
            otpBtn.innerHTML = originalText;
            alert("Connection error during verification.");
        } finally {
            otpBtn.disabled = false;
            otpBtn.innerHTML = originalText;
        }
    }

    async handleResetSubmit() {
        if (!this.forgotSession || !this.forgotSession.resetToken) {
            alert("Your reset session has expired. Please restart the password recovery process.");
            this.switchAuthCard("forgot");
            return;
        }

        const password = document.getElementById("reset-password-input").value;
        const confirm = document.getElementById("reset-confirm-input").value;

        if (!password || !confirm) {
            alert("Please fill in all fields.");
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
        if (resetBtn.disabled) return;
        const originalText = resetBtn.innerHTML;
        resetBtn.disabled = true;
        resetBtn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Updating...';

        try {
            const res = await fetch(`${SERVER_URL}/api/auth/reset-password`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    target: this.forgotSession.target,
                    token: this.forgotSession.resetToken,
                    password
                })
            });

            const data = await res.json();
            if (!res.ok) {
                if (data.error && data.error.includes("expired")) {
                    alert(data.error);
                    this.switchAuthCard("forgot");
                } else {
                    alert(data.error || "Reset failed.");
                }
                return;
            }

            this.forgotSession = null;
            alert("Your password has been successfully updated. Please sign in with your new password.");
            this.switchAuthCard("login");
        } catch (e) {
            console.error(e);
            alert("Network connection error.");
        } finally {
            resetBtn.disabled = false;
            resetBtn.innerHTML = originalText;
        }
    }

    refreshGPS(showNotification) {
        if (!navigator.geolocation) return;

        if (!this.watchId) {
            this.watchId = navigator.geolocation.watchPosition(
                (pos) => {
                    const lat = pos.coords.latitude;
                    const lng = pos.coords.longitude;
                    const accuracy = pos.coords.accuracy;

                    this.gps = { lat, lng };
                    this.syncGPSUI();

                    if (this.homeUserMarker) {
                        this.homeUserMarker.setLatLng([lat, lng]);
                    }
                    if (this.homeMap) {
                        if (!this.accuracyCircle) {
                            this.accuracyCircle = L.circle([lat, lng], {
                                radius: accuracy,
                                color: '#0066cc',
                                fillColor: '#0066cc',
                                fillOpacity: 0.15,
                                weight: 1
                            }).addTo(this.homeMap);
                        } else {
                            this.accuracyCircle.setLatLng([lat, lng]);
                            this.accuracyCircle.setRadius(accuracy);
                        }
                    }

                    if (this.consoleUserMarker) {
                        this.consoleUserMarker.setLatLng([lat, lng]);
                    }
                },
                (err) => {
                    console.warn("GPS Watch Error: ", err);
                },
                { enableHighAccuracy: true, maximumAge: 5000, timeout: 10000 }
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
        }

        if (this.consoleMap && this.consoleUserMarker) {
            this.consoleUserMarker.setLatLng(this.gps);
        }
    }

    updateRespondersOnMap() {
        if (!this.homeMap) return;

        // Clear existing markers
        Object.values(this.responderMarkers).forEach(m => this.homeMap.removeLayer(m));
        this.responderMarkers = {};

        this.responders.forEach(st => {
            let color = "#3b82f6";
            if (st.type === "fire") color = "#f59e0b";
            if (st.type === "medical") color = "#ef4444";

            let repIconHTML = `<div style="background-color:${color}; width:24px; height:24px; border-radius:50%; border:2px solid #fff; box-shadow:0 2px 5px rgba(0,0,0,0.3); display:flex; align-items:center; justify-content:center;" title="${st.name}">
                <i class="fa-solid ${st.icon}" style="color:white; font-size:12px;"></i>
            </div>`;

            const stationIcon = L.divIcon({
                className: `station-marker rep-${st.id}`,
                html: repIconHTML,
                iconAnchor: [12, 12]
            });

            const m = L.marker([st.lat, st.lng], { icon: stationIcon })
                .bindPopup(`<b>${st.name}</b><br>Status: ${st.status === 'busy' ? 'Busy/Dispatched' : 'Available'}`)
                .addTo(this.homeMap);
            
            this.responderMarkers[st.id] = m;
        });
    }

    initHomepageMap() {
        if (this.homeMap) return;

        let center = [this.gps.lat, this.gps.lng];
        let zoom = 14;
        try {
            const savedState = localStorage.getItem("alerto_user_map_state");
            if (savedState) {
                const parsed = JSON.parse(savedState);
                if (parsed.lat && parsed.lng && parsed.zoom) {
                    center = [parsed.lat, parsed.lng];
                    zoom = parsed.zoom;
                }
            }
        } catch (e) {
            console.error("Error reading saved map state:", e);
        }

        this.homeMap = L.map('homepage-map', {
            zoomControl: false,
            attributionControl: false
        }).setView(center, zoom);

        this.homeMap.on('moveend', () => {
            const c = this.homeMap.getCenter();
            localStorage.setItem("alerto_user_map_state", JSON.stringify({ lat: c.lat, lng: c.lng, zoom: this.homeMap.getZoom() }));
        });

        const savedType = localStorage.getItem("alerto_user_map_type") || "default";
        const tileLayers = {
            'default': 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            'satellite': 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
            'terrain': 'https://mt1.google.com/vt/lyrs=p&x={x}&y={y}&z={z}'
        };
        const layerUrl = tileLayers[savedType] || tileLayers['default'];

        this.homeTileLayer = L.tileLayer(layerUrl);
        this.homeTileLayer.addTo(this.homeMap);

        // Sync map type UI
        const options = document.querySelectorAll(".map-type-option");
        options.forEach(o => {
            if (o.dataset.type === savedType) o.classList.add("active");
            else o.classList.remove("active");
        });

        const citizenDivIcon = L.divIcon({
            className: 'citizen-marker-home',
            html: '<div style="background-color:#0066cc; width:16px; height:16px; border:2.5px solid #fff; border-radius:50%; box-shadow:0 0 10px rgba(0,102,204,0.6);"></div>',
            iconSize: [16, 16]
        });

        this.homeUserMarker = L.marker([this.gps.lat, this.gps.lng], {
            icon: citizenDivIcon
        }).addTo(this.homeMap);

        this.updateRespondersOnMap();
    }

    transitionAppState(state) {
        if (sessionStorage.getItem("alerto-token")) {
            sessionStorage.setItem("alerto-last-state", state);
        } else {
            localStorage.setItem("alerto-last-state", state);
        }
        if (state === "homepage" || state === "home") {
            this.stateSosChat.classList.remove("active");
            if (this.stateProfile) this.stateProfile.classList.remove("active");
            this.stateHomepage.classList.add("active");
            setTimeout(() => {
                if (this.homeMap) this.homeMap.invalidateSize();
            }, 100);
        } else if (state === "chat") {
            this.stateHomepage.classList.remove("active");
            if (this.stateProfile) this.stateProfile.classList.remove("active");
            this.stateSosChat.classList.add("active");
            this.initConsoleMap();
        } else if (state === "profile") {
            this.stateHomepage.classList.remove("active");
            this.stateSosChat.classList.remove("active");
            if (this.stateProfile) this.stateProfile.classList.add("active");
            this.syncProfileUI();
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

            // Store the current tile layer reference for the console map
            this.consoleTileLayer = null;
            const defaultTileUrl = 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';

            // Apply saved console map type
            const consoleTileLayers = {
                'default': 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                'satellite': 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
                'terrain': 'https://mt1.google.com/vt/lyrs=p&x={x}&y={y}&z={z}'
            };
            const savedConsoleMapType = localStorage.getItem("alerto_console_map_type") || "default";
            // Remove default tile layer and add saved one
            this.consoleMap.eachLayer((layer) => {
                if (layer instanceof L.TileLayer) this.consoleMap.removeLayer(layer);
            });
            this.consoleTileLayer = L.tileLayer(consoleTileLayers[savedConsoleMapType] || defaultTileUrl).addTo(this.consoleMap);

            // Map style toggle button + dropdown
            const btnMapStyleToggle = document.getElementById("btn-map-style-toggle");
            const mapStyleDropdown = document.getElementById("console-map-style-dropdown");

            if (btnMapStyleToggle && mapStyleDropdown) {
                // Toggle dropdown on icon click
                btnMapStyleToggle.addEventListener("click", (e) => {
                    e.stopPropagation();
                    mapStyleDropdown.classList.toggle("hidden");
                });

                // Close dropdown when clicking outside
                document.addEventListener("click", (e) => {
                    if (!mapStyleDropdown.contains(e.target) && e.target !== btnMapStyleToggle) {
                        mapStyleDropdown.classList.add("hidden");
                    }
                });

                // Highlight active type
                const allOpts = mapStyleDropdown.querySelectorAll(".console-map-type-opt");
                allOpts.forEach(opt => {
                    if (opt.dataset.type === savedConsoleMapType) {
                        opt.style.background = "#3b82f6";
                        opt.style.color = "white";
                    }
                    opt.addEventListener("click", () => {
                        const type = opt.dataset.type;
                        if (this.consoleTileLayer) this.consoleMap.removeLayer(this.consoleTileLayer);
                        this.consoleTileLayer = L.tileLayer(consoleTileLayers[type] || defaultTileUrl).addTo(this.consoleMap);
                        localStorage.setItem("alerto_console_map_type", type);
                        // Update highlight
                        allOpts.forEach(o => { o.style.background = "none"; o.style.color = "var(--text-primary)"; });
                        opt.style.background = "#3b82f6";
                        opt.style.color = "white";
                        mapStyleDropdown.classList.add("hidden");
                    });
                });
            }

        }, 120);

        // Hide/Show map toggle (outside setTimeout so it's always registered)
        const btnToggleMap = document.getElementById("btn-toggle-console-map");
        const consoleMapEl = document.getElementById("console-map");
        if (btnToggleMap && consoleMapEl) {
            // Restore saved visibility
            const savedHidden = localStorage.getItem("alerto_console_map_hidden") === "true";
            if (savedHidden) {
                consoleMapEl.style.display = "none";
                btnToggleMap.querySelector("i").className = "fa-solid fa-chevron-down";
            }

            btnToggleMap.addEventListener("click", () => {
                const isHidden = consoleMapEl.style.display === "none";
                if (isHidden) {
                    consoleMapEl.style.display = "";
                    btnToggleMap.querySelector("i").className = "fa-solid fa-chevron-up";
                    localStorage.setItem("alerto_console_map_hidden", "false");
                    // Refresh map tiles after showing
                    if (this.consoleMap) {
                        setTimeout(() => this.consoleMap.invalidateSize(), 150);
                    }
                } else {
                    consoleMapEl.style.display = "none";
                    btnToggleMap.querySelector("i").className = "fa-solid fa-chevron-down";
                    localStorage.setItem("alerto_console_map_hidden", "true");
                }
            });
        }
    }

    locateMe() {
        if (!navigator.geolocation) {
            alert("Your browser does not support geolocation.");
            return;
        }

        const btn = document.getElementById("gps-recenter");
        if (btn) btn.innerHTML = '<i class="fa-solid fa-circle-notch fa-spin"></i>';

        navigator.geolocation.getCurrentPosition(
            (pos) => {
                this.manualLocationOverride = false;
                if (btn) btn.innerHTML = '<i class="fa-solid fa-location-arrow"></i>';

                const lat = pos.coords.latitude;
                const lng = pos.coords.longitude;

                this.gps = { lat, lng };
                this.syncGPSUI();

                if (this.homeMap) {
                    this.homeMap.flyTo([lat, lng], 17, {
                        animate: true,
                        duration: 1.5
                    });
                }

                // Ensure real-time tracking is active
                this.refreshGPS(false);
            },
            (err) => {
                if (btn) btn.innerHTML = '<i class="fa-solid fa-location-arrow" style="color: #ef4444;"></i>';
                if (err.code === err.PERMISSION_DENIED) {
                    alert("Location permission denied. Please enable location services in your browser settings to use 'Locate Me'.");
                } else if (err.code === err.POSITION_UNAVAILABLE) {
                    alert("Location information is unavailable. Please check your GPS signal.");
                } else if (err.code === err.TIMEOUT) {
                    alert("Location request timed out. Please try again or check your GPS signal.");
                } else {
                    alert("An unknown error occurred while fetching your location.");
                }
            },
            { enableHighAccuracy: true, timeout: 20000, maximumAge: 30000 }
        );
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
            this.homeMap.fitBounds(this.waterOverlay.getBounds());
            alert("High water warning areas plotted.");
        }
    }

    async triggerSOSFlow() {
        if (!this.activeUser) {
            alert("Please verify your credentials and Log In first.");
            return;
        }

        // Show geolocation transition spinner
        this.locationLoader.classList.remove("hidden");

        setTimeout(async () => {
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

            if (!this.activeUser.phone || this.activeUser.phone.trim() === '') {
                alert("Please update your contact number before sending an emergency request.\n\nYou can add your phone number in the Profile / Account Settings.");
                return;
            }

            const hasPasscode = this.activeUser.hasPasscode || this.activeUser.passcode === "SET";
            if (!hasPasscode) {
                alert("Please create a passcode before sending an emergency request.\n\nYou can create your passcode in the Profile / Account Settings.");
                return;
            }

            try {
                // Call backend to create a temporary Draft and check for existing unfinished emergencies
                const res = await fetch(`${SERVER_URL}/api/incidents/draft`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        reporterId: this.activeUser.id,
                        reporterPhone: this.activeUser.phone,
                        lat: this.gps.lat,
                        lng: this.gps.lng,
                        reporter: this.activeUser.name,
                        createdAt: Date.now()
                    })
                });

                const data = await res.json();

                if (res.status === 409) {
                    // Conflict: Existing emergency found
                    this.conflictIncident = data.incident;
                    if (this.modalDraftConflict) this.modalDraftConflict.classList.remove("hidden");
                    return;
                }

                if (res.status === 400) {
                    alert(data.error || "Bad Request");
                    return;
                }

                if (!res.ok || !data.success) {
                    throw new Error(data.error || "Failed to initialize emergency session.");
                }

                // Successful Draft Creation (ID will be DRAFT-userId)
                this.activeIncident = data.incident;

                this.transitionAppState("chat");

                // Clear dynamic chat feed (preserving the category selection grid)
                if (this.dynamicChatFeed) this.dynamicChatFeed.innerHTML = "";

                // Reset category UI
                this.selectedCategory = null;
                const categoryButtons = document.querySelectorAll(".chat-category-btn");
                categoryButtons.forEach(b => b.classList.remove("active"));

                this.chatDetailsInput.disabled = false;
                this.chatSendBtn.disabled = false;
                this.btnAttachMedia.disabled = false;

                this.chatIncidentId.textContent = "ALR-DRAFT";
                this.chatIncidentTime.textContent = "Not Sent";
                this.reportStatusBadge.textContent = "Draft";
                this.reportStatusBadge.style.backgroundColor = "rgba(142, 142, 147, 0.15)";
                this.reportStatusBadge.style.color = "var(--text-secondary)";

                localStorage.setItem("alerto-active-incident", JSON.stringify(this.activeIncident));

            } catch (err) {
                console.warn("Could not connect to ALERTO-POZ Command Center. Falling back to local offline draft.", err);

                // Offline fallback
                this.activeIncident = {
                    id: 'draft',
                    status: 'draft',
                    reporterId: this.activeUser.id,
                    reporterPhone: this.activeUser.phone,
                    reporter: this.activeUser.name,
                    lat: this.gps.lat,
                    lng: this.gps.lng,
                    category: null,
                    details: "",
                    media: [],
                    createdAt: Date.now(),
                    has_sent_messages: false
                };

                this.transitionAppState("chat");

                // Clear dynamic chat feed (preserving the category selection grid)
                if (this.dynamicChatFeed) this.dynamicChatFeed.innerHTML = "";

                // Reset category UI
                this.selectedCategory = null;
                const categoryButtons = document.querySelectorAll(".chat-category-btn");
                categoryButtons.forEach(b => b.classList.remove("active"));

                this.chatDetailsInput.disabled = false;
                this.chatSendBtn.disabled = false;
                this.btnAttachMedia.disabled = false;

                this.chatIncidentId.textContent = "ALR-DRAFT";
                this.chatIncidentTime.textContent = "Not Sent";
                this.reportStatusBadge.textContent = "Draft";
                this.reportStatusBadge.style.backgroundColor = "rgba(142, 142, 147, 0.15)";
                this.reportStatusBadge.style.color = "var(--text-secondary)";

                localStorage.setItem("alerto-active-incident", JSON.stringify(this.activeIncident));
            }

        }, 800);
    }

    handleMediaUpload(e) {
        const files = Array.from(e.target.files);
        if (files.length === 0) return;

        files.forEach(file => {
            const type = file.type.startsWith("image/") ? "image" : "video";
            const attObj = {
                name: file.name,
                type: type,
                file: file // Store the actual file object for FormData
            };
            this.attachments.push(attObj);

            // Create a temporary object URL for preview purposes
            const objectUrl = URL.createObjectURL(file);
            attObj.previewUrl = objectUrl;

            this.renderMediaPreviews();
        });

        // Automatically send the media immediately
        this.sendChatNotes();

        // Reset the file input value so the same file can be selected again
        e.target.value = "";
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
                ? `<img src="${att.previewUrl}">`
                : `<video src="${att.previewUrl}" muted autoplay loop></video>`;

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

    async sendChatNotes() {
        const text = this.chatDetailsInput.value.trim();
        const hasAttachments = this.attachments.length > 0;

        if (!text && !hasAttachments) return;
        if (!this.activeIncident) return;

        // Validation: Must select an emergency type before sending the first message
        if (this.activeIncident.status === "draft" && !this.activeIncident.has_sent_messages) {
            if (!this.activeIncident.category) {
                this.appendChatMessage("System", "⚠️ Please select an emergency type first.", "incoming-bubble");
                return;
            }
        }

        this.chatDetailsInput.value = "";

        // Append user comment bubble in conversation log immediately for responsiveness
        if (text) {
            this.appendChatMessage("You", text, "outgoing-bubble", Date.now(), this.activeUser?.profile_image, this.activeUser?.gender);
        }

        // Copy attachments for processing and clear UI
        const attachmentsToSend = [...this.attachments];
        if (attachmentsToSend.length > 0) {
            this.attachments = [];
            this.renderMediaPreviews();
        }

        // Keep the old details appending for backward compatibility
        if (text) this.activeIncident.details += ` | Notes: ${text}`;
        if (attachmentsToSend.length > 0) this.activeIncident.details += ` | Files Attached: ${attachmentsToSend.length} media logs`;

        // If this is the first message, ACTIVATE the incident via socket to get the real ticket ID
        if (this.activeIncident.status.toLowerCase() === "draft" && !this.activeIncident.has_sent_messages) {
            this.activeIncident.status = "pending"; // Activating
            this.activeIncident.has_sent_messages = true;

            if (this.socket && this.socket.connected && this.isOnline) {
                this.socket.emit('citizen-sos-report', this.activeIncident, async (response) => {
                    if (response && response.success) {
                        this.activeIncident = response.incident;

                        const timeString = new Date().toLocaleString('en-US', {
                            month: 'short', day: 'numeric', year: 'numeric',
                            hour: 'numeric', minute: 'numeric', hour12: true
                        });

                        // Update UI with generated info from backend
                        this.chatIncidentId.textContent = this.activeIncident.id;
                        this.chatIncidentTime.textContent = timeString;
                        this.reportStatusBadge.textContent = "Pending";
                        this.reportStatusBadge.style.backgroundColor = "rgba(239, 68, 68, 0.15)";
                        this.reportStatusBadge.style.color = "var(--danger)";

                        localStorage.setItem("alerto-active-incident", JSON.stringify(this.activeIncident));

                        // Now that we have the real ID, POST messages and media
                        await this.postMessagesAndMedia(text, attachmentsToSend);

                        const sosMessage = `🚨 INCIDENT ACTIVATED<br>
Ticket Code: <b>${this.activeIncident.id}</b><br>
Your emergency request has been received.<br>
Keep this ticket number for reference.<br><br>
Your emergency location and details have been sent to the Command Center.<br>
For emergency validation, please provide:<br>
📸 Validation picture of the incident<br>
🎥 Validation video, if available<br>
Stay calm and provide clear updates.`;
                        setTimeout(() => {
                            this.appendChatMessage("Command Center (Auto)", sosMessage, "incoming-bubble");
                        }, 500);
                    } else {
                        alert("Error activating emergency: " + (response ? response.error : "Unknown error"));
                    }
                });
            } else {
                localStorage.setItem("alerto-active-incident", JSON.stringify(this.activeIncident));
                this.appendChatMessage("System", "You are offline. Trying to send SMS fallback...", "incoming-bubble");
            }
        } else {
            // It's already active
            this.activeIncident.has_sent_messages = true;
            localStorage.setItem("alerto-active-incident", JSON.stringify(this.activeIncident));

            // Send updated details via socket
            if (this.activeIncident.status !== "requesting_id" && this.socket && this.socket.connected && this.isOnline) {
                this.socket.emit('citizen-sos-report', this.activeIncident);
            }

            // POST messages and media
            await this.postMessagesAndMedia(text, attachmentsToSend);
        }
    }

    async postMessagesAndMedia(text, attachments) {
        if (!this.activeIncident || !this.activeIncident.id) return;

        if (text) {
            const fd = new FormData();
            fd.append('senderId', this.activeUser.id);
            fd.append('senderRole', 'Citizen App');
            fd.append('messageType', 'text');
            fd.append('messageContent', text);
            try {
                await fetch(`${SERVER_URL}/api/incidents/${this.activeIncident.id}/messages`, {
                    method: 'POST',
                    body: fd
                });
            } catch (e) { console.error("Message send error", e); }
        }

        for (const att of attachments) {
            if (!att.file) continue;
            const fd = new FormData();
            fd.append('senderId', this.activeUser.id);
            fd.append('senderRole', 'Citizen App');
            fd.append('messageType', att.type);
            fd.append('media', att.file);
            try {
                const response = await fetch(`${SERVER_URL}/api/incidents/${this.activeIncident.id}/messages`, {
                    method: 'POST',
                    body: fd
                });
                const data = await response.json();
                if (data.success && data.message && data.message.media_url) {
                     this.appendMediaMessageBubble({ type: att.type, data: `${SERVER_URL}${data.message.media_url}` }, "You", "outgoing-bubble", data.message.timestamp, this.activeUser?.profile_image, this.activeUser?.gender);
                }
            } catch (e) { console.error("Media upload error", e); }
        }
    }

    updateSOSCategory(cat) {
        if (!this.activeIncident) return;
        this.activeIncident.category = cat;
        this.appendChatMessage("You", `Selected Category: ${cat.toUpperCase()}`, "outgoing-bubble", Date.now(), this.activeUser?.profile_image, this.activeUser?.gender);

        localStorage.setItem("alerto-active-incident", JSON.stringify(this.activeIncident));

        // Only broadcast if active and already has an ID
        if (this.activeIncident.status !== "draft" && this.activeIncident.status !== "requesting_id" && this.socket && this.socket.connected && this.isOnline) {
            this.socket.emit('citizen-sos-report', this.activeIncident);
        }
    }

    updateSOSLocationOnServer() {
        if (!this.activeIncident) return;
        this.activeIncident.lat = this.gps.lat;
        this.activeIncident.lng = this.gps.lng;

        if (this.activeIncident.status !== "draft" && this.activeIncident.status !== "requesting_id" && this.socket && this.socket.connected && this.isOnline) {
            this.socket.emit('citizen-sos-report', this.activeIncident);
        }
    }

    getAvatarHtml(profileImage, gender) {
        if (profileImage && profileImage.trim() !== '') {
            const url = profileImage.startsWith('http') ? profileImage : `${SERVER_URL}${profileImage}`;
            return `<img src="${url}" style="width: 32px; height: 32px; border-radius: 50%; object-fit: cover; box-shadow: 0 2px 5px rgba(0,0,0,0.1); flex-shrink: 0;" />`;
        }
        const g = (gender || '').toLowerCase();
        let color = '#ced4da';
        if (g === 'male') color = '#4dabf7';
        else if (g === 'female') color = '#f06595';
        
        return `<div style="width: 32px; height: 32px; border-radius: 50%; background: ${color}; display: flex; justify-content: center; align-items: center; box-shadow: 0 2px 5px rgba(0,0,0,0.1); flex-shrink: 0;">
            <svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg" style="width: 100%; height: 100%; border-radius: 50%;"><circle cx="50" cy="50" r="50" fill="${color}"/><circle cx="50" cy="40" r="18" fill="#fff"/><path d="M22 90 Q50 55 78 90" stroke="#fff" stroke-width="8" fill="none" stroke-linecap="round"/></svg>
        </div>`;
    }

    appendMediaMessageBubble(att, sender = "You", bubbleClass = "outgoing-bubble", timestampMs = Date.now(), profileImage = null, gender = null) {
        const wrap = document.createElement("div");
        wrap.className = `chat-message-bubble ${bubbleClass} animate-bubble`;

        // Format timestamp in Asia/Manila
        const optionsDate = { timeZone: 'Asia/Manila', year: 'numeric', month: 'short', day: '2-digit' };
        const optionsTime = { timeZone: 'Asia/Manila', hour: '2-digit', minute: '2-digit', hour12: true };
        const d = new Date(timestampMs);
        const dateStr = new Intl.DateTimeFormat('en-US', optionsDate).format(d);
        const timeStr = new Intl.DateTimeFormat('en-US', optionsTime).format(d);
        const formattedTimestamp = `${dateStr} • ${timeStr}`;

        const mediaTag = att.type === "image"
            ? `<img src="${att.data}" style="max-width:280px; max-height:250px; border-radius:8px; display:block;">`
            : `<video src="${att.data}" controls style="max-width:280px; max-height:250px; border-radius:8px; display:block;"></video>`;

        if (sender === "System" || sender === "Command Center" || sender === "Command Center (Auto)" || sender === "Admin" || sender === "Administrator" || sender === "Admin User") {
            sender = "ALERTOPOZ";
        }

        if (sender === "ALERTOPOZ") {
            // Apply special ALERTOPOZ UI layout
            wrap.innerHTML = `
                <div style="display: flex; gap: 10px; align-items: flex-start; max-width: 90%;">
                    <div style="display: flex; align-items: center; justify-content: center; width: 40px; height: 40px; background: white; border-radius: 50%; box-shadow: 0 2px 5px rgba(0,0,0,0.1); flex-shrink: 0; color: #1e3a8a; position: relative;">
                        <i class="fa-solid fa-headset" style="font-size: 22px;"></i>
                        <span style="font-size: 9px; font-weight: 900; position: absolute; margin-top: -3px; color: white; background: #e11d48; padding: 0 4px; border-radius: 4px;">SOS</span>
                    </div>
                    <div style="display: flex; flex-direction: column;">
                        <span style="font-weight: 800; font-size: 15px; margin-bottom: 0px; color: #000; letter-spacing: -0.5px;">alertopoz</span>
                        <div class="bubble-content no-padding" style="border-radius: 0 16px 16px 16px; word-break: break-word; min-width: 250px; max-width: 100%;">
                            ${mediaTag}
                            <div class="chat-timestamp" style="font-size: 10px; color: #64748b; text-align: left; margin-top: 5px;">
                                ${formattedTimestamp}
                            </div>
                        </div>
                    </div>
                </div>
            `;
            wrap.className = `chat-message-bubble animate-bubble`; // Remove default bubble padding/styling
            wrap.style.alignSelf = 'flex-start';
            wrap.style.padding = '0';
            wrap.style.background = 'transparent';
            wrap.style.boxShadow = 'none';
        } else {
            const isOutgoing = bubbleClass === "outgoing-bubble";
            const avatarHtml = this.getAvatarHtml(profileImage, gender);
            wrap.innerHTML = isOutgoing ? `
                <div class="bubble-content no-padding" style="margin-right: 8px;">
                    <p style="margin:0">${sender && sender !== 'You' ? `<strong>${sender}:</strong><br>` : ''}</p>
                    ${mediaTag}
                    <div class="chat-timestamp" style="font-size: 10px; color: #94a3b8; text-align: right; margin-top: 5px;">
                        ${formattedTimestamp}
                    </div>
                </div>
            ` : `
                <div style="align-self: flex-end;">${avatarHtml}</div>
                <div class="bubble-content no-padding" style="margin-left: 8px;">
                    <p style="margin:0">${sender && sender !== 'You' ? `<strong>${sender}:</strong><br>` : ''}</p>
                    ${mediaTag}
                    <div class="chat-timestamp" style="font-size: 10px; color: #94a3b8; text-align: right; margin-top: 5px;">
                        ${formattedTimestamp}
                    </div>
                </div>
            `;
        }

        this.dynamicChatFeed.appendChild(wrap);
        this.chatMessagesContainer.scrollTo({ top: this.chatMessagesContainer.scrollHeight, behavior: 'smooth' });
    }

    appendChatMessage(sender, text, bubbleClass, timestampMs = Date.now(), profileImage = null, gender = null) {
        const wrap = document.createElement("div");
        wrap.className = `chat-message-bubble ${bubbleClass} animate-bubble`;

        // Enforce ALERTOPOZ naming rules
        if (sender === "System" || sender === "Command Center" || sender === "Command Center (Auto)" || sender === "Admin" || sender === "Administrator" || sender === "Admin User") {
            sender = "ALERTOPOZ";
        }

        // Format timestamp in Asia/Manila
        const optionsDate = { timeZone: 'Asia/Manila', year: 'numeric', month: 'short', day: '2-digit' };
        const optionsTime = { timeZone: 'Asia/Manila', hour: '2-digit', minute: '2-digit', hour12: true };
        const d = new Date(timestampMs);
        const dateStr = new Intl.DateTimeFormat('en-US', optionsDate).format(d);
        const timeStr = new Intl.DateTimeFormat('en-US', optionsTime).format(d);
        const formattedTimestamp = `${dateStr} • ${timeStr}`;

        if (sender === "ALERTOPOZ") {
            // Apply special ALERTOPOZ UI layout
            wrap.innerHTML = `
                <div style="display: flex; gap: 10px; align-items: flex-start; max-width: 90%;">
                    <div style="display: flex; align-items: center; justify-content: center; width: 40px; height: 40px; background: white; border-radius: 50%; box-shadow: 0 2px 5px rgba(0,0,0,0.1); flex-shrink: 0; color: #1e3a8a; position: relative;">
                        <i class="fa-solid fa-headset" style="font-size: 22px;"></i>
                        <span style="font-size: 9px; font-weight: 900; position: absolute; margin-top: -3px; color: white; background: #e11d48; padding: 0 4px; border-radius: 4px;">SOS</span>
                    </div>
                    <div style="display: flex; flex-direction: column;">
                        <span style="font-weight: 800; font-size: 15px; margin-bottom: 0px; color: #000; letter-spacing: -0.5px;">alertopoz</span>
                        <div class="bubble-content" style="background-color: #a4b9c9; color: #1e293b; border-radius: 0 16px 16px 16px; padding: 12px 16px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); word-break: break-word; min-width: 250px; max-width: 100%;">
                            <p style="margin: 0;">${text}</p>
                            <div class="chat-timestamp" style="font-size: 10px; color: #64748b; text-align: left; margin-top: 5px;">
                                ${formattedTimestamp}
                            </div>
                        </div>
                    </div>
                </div>
            `;
            wrap.className = `chat-message-bubble animate-bubble`; // Remove default bubble padding/styling
            wrap.style.alignSelf = 'flex-start';
            wrap.style.padding = '0';
            wrap.style.background = 'transparent';
            wrap.style.boxShadow = 'none';
        } else {
            const isOutgoing = bubbleClass === "outgoing-bubble";
            const avatarHtml = this.getAvatarHtml(profileImage, gender);
            wrap.innerHTML = isOutgoing ? `
                <div class="bubble-content" style="margin-right: 8px;">
                    <p>${sender && sender !== 'You' ? `<strong>${sender}:</strong><br>` : ''}${text}</p>
                    <div class="chat-timestamp" style="font-size: 10px; color: #94a3b8; text-align: right; margin-top: 5px;">
                        ${formattedTimestamp}
                    </div>
                </div>
            ` : `
                <div style="align-self: flex-end;">${avatarHtml}</div>
                <div class="bubble-content" style="margin-left: 8px;">
                    <p>${sender && sender !== 'You' ? `<strong>${sender}:</strong><br>` : ''}${text}</p>
                    <div class="chat-timestamp" style="font-size: 10px; color: #94a3b8; text-align: right; margin-top: 5px;">
                        ${formattedTimestamp}
                    </div>
                </div>
            `;
        }

        this.dynamicChatFeed.appendChild(wrap);
        this.chatMessagesContainer.scrollTo({ top: this.chatMessagesContainer.scrollHeight, behavior: 'smooth' });
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
            
            // If command center marked it resolved/cancelled, force close session unless user is manually doing it
            if (this.activeIncident.status === "resolved" || this.activeIncident.status === "cancelled" || this.activeIncident.status === "closed") {
                if (!this._closingIncident) {
                    this._closingIncident = true;
                    this.appendChatMessage("System", `Incident has been marked as ${this.activeIncident.status} by the command center. Session will end shortly.`, "incoming-bubble");
                    setTimeout(() => {
                        this.activeIncident = null;
                        localStorage.removeItem("alerto-active-incident");
                        this._closingIncident = false;
                        this.transitionAppState("homepage");
                    }, 3000);
                }
            }
        } else {
            if (sosGrid) sosGrid.style.display = "";
            if (this.btnTriggerSosAlert) this.btnTriggerSosAlert.style.display = "";
            if (this.btnChatOptClose) this.btnChatOptClose.style.display = "";
            if (this.btnIncidentOptions) this.btnIncidentOptions.style.display = "";
        }

        if (this.activeIncident.status === "enroute") {
            this.reportStatusBadge.style.backgroundColor = "rgba(255, 149, 0, 0.15)";
            this.reportStatusBadge.style.color = "#ff9500";
        } else if (this.activeIncident.status === "resolved") {
            this.reportStatusBadge.style.backgroundColor = "rgba(52, 168, 83, 0.15)";
            this.reportStatusBadge.style.color = "#34a853";
            this.appendChatMessage("System", "Emergency marked as RESOLVED by command center.", "incoming-bubble");
            this.clearResponderTracking();
        } else if (this.activeIncident.status === "cancelled") {
            this.reportStatusBadge.style.backgroundColor = "rgba(239, 68, 68, 0.15)";
            this.reportStatusBadge.style.color = "#ef4444";
            this.appendChatMessage("System", "Emergency marked as CANCELLED.", "incoming-bubble");
            this.clearResponderTracking();
        }
    }

    async closeIncidentFlow() {
        if (!this.activeIncident) return;

        // Prevent closing already cancelled/resolved incidents but allow user to exit to homepage
        if (this.activeIncident.status === "cancelled" || this.activeIncident.status === "resolved" || this.activeIncident.status === "closed") {
            this.activeIncident = null;
            localStorage.removeItem("alerto-active-incident");
            this._closingIncident = false;
            this.transitionAppState("homepage");
            return;
        }

        // Prevent double-click: if already processing, ignore
        if (this._closingIncident) return;
        this._closingIncident = true;

        // CASE A: Draft with no interaction — close immediately without passcode
        if (!this.activeIncident.id || this.activeIncident.id === 'draft' ||
            (this.activeIncident.status === "draft" && !this.activeIncident.has_sent_messages)) {
            this.activeIncident.status = "cancelled";
            this.activeIncident.cancelledAt = Date.now();
            localStorage.removeItem("alerto-active-incident");
            this.appendChatMessage("System", "Incident cancelled.", "incoming-bubble");
            setTimeout(() => {
                this.activeIncident = null;
                this._closingIncident = false;
                this.transitionAppState("homepage");
            }, 1200);
            return;
        }

        // CASE B: Active incident — call backend to determine if passcode needed
        try {
            const res = await fetch(`${SERVER_URL}/api/incidents/${this.activeIncident.id}/cancel`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ userId: this.activeUser.id, phone: this.activeUser.phone })
            });
            const data = await res.json();

            if (res.ok && data.success) {
                // Backend closed it immediately (no passcode required / user has no passcode set)
                this.activeIncident.status = "cancelled";
                this.syncActiveIncidentStatus();
                this.appendChatMessage("System", "✅ Incident Cancelled\nYour incident has been successfully closed.", "incoming-bubble");

                // Hide options button
                if (this.btnIncidentOptions) this.btnIncidentOptions.style.display = "none";

                setTimeout(() => {
                    this.activeIncident = null;
                    localStorage.removeItem("alerto-active-incident");
                    this._closingIncident = false;
                    this.transitionAppState("homepage");
                }, 2500);
            } else if (res.status === 401 && data.passcodeRequired) {
                // Backend requires a passcode to cancel this active incident.
                this._closingIncident = false;
                this.promptPasscodeForClose();
            } else {
                this._closingIncident = false;
                if (res.status === 400 && data.error && data.error.includes("already")) {
                    this.activeIncident = null;
                    localStorage.removeItem("alerto-active-incident");
                    this.transitionAppState("homepage");
                } else {
                    this.appendChatMessage("System", `❌ ${data.error || "Failed to close incident."}`, "incoming-bubble");
                }
            }
        } catch (e) {
            console.error("Error closing incident:", e);
            this._closingIncident = false;
            this.appendChatMessage("System", "❌ Network error. Please try again.", "incoming-bubble");
        }
    }

    promptPasscodeForClose() {
        const modal = document.getElementById("modal-verify-close");
        if (!modal) return;
        modal.classList.remove("hidden");

        const input = document.getElementById("input-verify-close");
        const btnConfirm = document.getElementById("btn-confirm-close");
        const btnCancel = document.getElementById("btn-cancel-close");
        const errorText = document.getElementById("verify-close-error");

        input.value = "";
        errorText.classList.add("hidden");
        btnConfirm.disabled = false;
        btnConfirm.textContent = "Confirm Close Incident";

        // Focus input for quick typing
        setTimeout(() => input.focus(), 100);

        const cleanup = () => {
            modal.classList.add("hidden");
            btnCancel.onclick = null;
            btnConfirm.onclick = null;
            input.onkeydown = null;
        };

        const handleCancel = () => {
            cleanup();
        };

        const handleEnter = (e) => {
            if (e.key === "Enter") handleConfirm();
        };

        const handleConfirm = async () => {
            const pass = input.value.trim();
            if (!pass) {
                errorText.textContent = "Please enter your passcode.";
                errorText.classList.remove("hidden");
                return;
            }

            // Loading state — disable button to prevent double-click
            btnConfirm.disabled = true;
            btnConfirm.textContent = "Verifying...";
            errorText.classList.remove("hidden");

            try {
                const res = await fetch(`${SERVER_URL}/api/incidents/${this.activeIncident.id}/cancel`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ userId: this.activeUser.id, phone: this.activeUser.phone, passcode: pass })
                });
                const data = await res.json();

                if (res.ok && data.success) {
                    cleanup();

                    this.activeIncident.status = "cancelled";
                    this.syncActiveIncidentStatus();

                    // Hide options button
                    if (this.btnIncidentOptions) this.btnIncidentOptions.style.display = "none";

                    this.appendChatMessage("System", "✅ Incident Cancelled\nYour incident has been successfully closed.", "incoming-bubble");

                    // Wait, then go back to homepage
                    setTimeout(() => {
                        this.activeIncident = null;
                        localStorage.removeItem("alerto-active-incident");
                        this._closingIncident = false;
                        this.transitionAppState("homepage");
                    }, 2500);
                } else {
                    if (res.status === 400 && data.error && data.error.includes("already")) {
                        cleanup();
                        this.activeIncident = null;
                        localStorage.removeItem("alerto-active-incident");
                        this.transitionAppState("homepage");
                        return;
                    }
                    // Wrong passcode or other error — stay on modal
                    errorText.textContent = data.error || "Incorrect passcode. Please try again.";
                    errorText.classList.remove("hidden");
                    btnConfirm.disabled = false;
                    btnConfirm.textContent = "Confirm Close Incident";
                    input.value = "";
                    input.focus();
                }
            } catch (e) {
                console.error("Passcode verification error:", e);
                errorText.textContent = "Network error verifying passcode. Please try again.";
                errorText.classList.remove("hidden");
                btnConfirm.disabled = false;
                btnConfirm.textContent = "Confirm Close Incident";
            }
        };

        btnCancel.onclick = handleCancel;
        btnConfirm.onclick = handleConfirm;
        input.onkeydown = handleEnter;
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
            const dateObj = new Date(b.timestamp);
            const time = dateObj.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            const date = dateObj.toLocaleDateString([], { month: 'short', day: 'numeric', year: 'numeric' });
            const dateTime = `${date} • ${time}`;
            const fakeDist = this.getHaversineDistance(this.gps.lat, this.gps.lng, 16.1114, 120.5482) + 2.5;

            html += `
                <div class="broadcast-alert-card-sheet">
                    <div class="alert-thumbnail-box">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                    </div>
                    <div class="alert-content-details">
                        <div class="alert-title-row">
                            <h4>${b.title}</h4>
                            <span class="alert-time-muted">${dateTime}</span>
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
        } catch (e) { }
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
        } catch (e) { }
    }

    async loadHistory() {
        if (!this.activeUser || !this.activeUser.id) return;
        const container = document.getElementById("history-list-container");
        if (!container) return;

        container.innerHTML = '<div style="text-align:center; padding:20px; color:#64748b;"><i class="fa-solid fa-spinner fa-spin"></i> Loading history...</div>';

        try {
            // Fetch using user ID, not phone
            const res = await fetch(`${SERVER_URL}/api/user/history/${this.activeUser.id}`);
            if (!res.ok) throw new Error("Failed to load history.");
            this.historyData = await res.json();
            this.renderHistoryList();
        } catch (e) {
            console.error(e);
            container.innerHTML = '<div style="text-align:center; padding:20px; color:#ef4444;">Failed to load history.</div>';
        }
    }

    renderHistoryList() {
        const container = document.getElementById("history-list-container");
        if (!container) return;

        if (!this.historyData || this.historyData.length === 0) {
            container.innerHTML = `
                <div class="empty-state-container">
                    <i class="fa-solid fa-folder-open"></i>
                    <h3>No Emergency History</h3>
                    <p>You haven't submitted any emergency reports yet.</p>
                </div>
            `;
            return;
        }

        // Get filter values
        const searchInput = document.getElementById("history-search");
        const typeSelect = document.getElementById("history-filter-type");
        const statusSelect = document.getElementById("history-filter-status");

        const q = searchInput ? searchInput.value.toLowerCase() : "";
        const t = typeSelect ? typeSelect.value.toLowerCase() : "all";
        const s = statusSelect ? statusSelect.value.toLowerCase() : "all";

        let filtered = this.historyData.filter(inc => {
            // Type Match
            let typeMatch = (t === "all");
            if (!typeMatch) {
                if (t === "other" && !["fire", "medical", "accident", "crime", "flood", "rescue"].includes(inc.category.toLowerCase())) {
                    typeMatch = true;
                } else if (inc.category.toLowerCase() === t) {
                    typeMatch = true;
                }
            }

            // Status Match
            let statusMatch = (s === "all" || inc.status.toLowerCase() === s);

            // Search Match
            let searchMatch = false;
            if (!q) {
                searchMatch = true;
            } else {
                const searchStr = `${inc.id} ${inc.category} ${inc.location} ${inc.status}`.toLowerCase();
                if (searchStr.includes(q)) searchMatch = true;
            }

            return typeMatch && statusMatch && searchMatch;
        });

        if (filtered.length === 0) {
            container.innerHTML = `
                <div class="empty-state-container">
                    <i class="fa-solid fa-filter"></i>
                    <h3>No matching emergencies found</h3>
                    <p>Try changing your search or filters.</p>
                </div>
            `;
            return;
        }

        let html = '';
        filtered.forEach(inc => {
            const dt = new Date(inc.createdAt || inc.networkReceivedAt);
            const optionsDate = { timeZone: 'Asia/Manila', year: 'numeric', month: 'short', day: '2-digit' };
            const optionsTime = { timeZone: 'Asia/Manila', hour: '2-digit', minute: '2-digit', hour12: true };
            const dateStr = new Intl.DateTimeFormat('en-US', optionsDate).format(dt);
            const timeStr = new Intl.DateTimeFormat('en-US', optionsTime).format(dt);

            const cat = inc.category.toUpperCase();

            let agency = "Unknown Agency";
            let vehicle = "Unknown Vehicle";
            if (inc.category.toLowerCase() === 'fire') { agency = "BFP"; vehicle = "Fire Truck"; }
            else if (inc.category.toLowerCase() === 'medical') { agency = "Medical/EMS"; vehicle = "Ambulance"; }
            else if (inc.category.toLowerCase() === 'crime') { agency = "PNP"; vehicle = "Police Patrol"; }
            else if (inc.category.toLowerCase() === 'flood' || inc.category.toLowerCase() === 'rescue') { agency = "MDRRMO"; vehicle = "Rescue Vehicle"; }

            // Check if there's an explicit assignedUnit
            if (inc.assignedUnit) vehicle = inc.assignedUnit;

            html += `
                <div class="history-card">
                    <div class="history-card-header">
                        <div class="history-card-title">
                            ${inc.category.toLowerCase() === 'fire' ? '🔥' : (inc.category.toLowerCase() === 'medical' ? '🚑' : '🚨')} ${cat} EMERGENCY
                        </div>
                        <span class="history-status-badge history-badge-${inc.status.toLowerCase().replace(" ", "")}">${inc.status}</span>
                    </div>
                    <div class="history-card-body">
                        <div><strong>Emergency ID:</strong> ALR-${dt.getFullYear()}-${String(inc.id).padStart(4, '0')}</div>
                        <div><strong>Location:</strong> ${inc.location || "N/A"}</div>
                        <div><strong>Reported:</strong> ${dateStr} - ${timeStr}</div>
                        <div><strong>Agency:</strong> ${agency}</div>
                        <div><strong>Vehicle:</strong> ${vehicle}</div>
                    </div>
                    <button class="history-view-details-btn" onclick="mobileClient.renderHistoryDetails('${inc.id}')">View Details &rarr;</button>
                </div>
            `;
        });

        container.innerHTML = html;
    }

    renderHistoryDetails(incidentId) {
        if (!this.historyData) return;
        const inc = this.historyData.find(i => String(i.id) === String(incidentId));
        if (!inc) return;

        const dt = new Date(inc.createdAt || inc.networkReceivedAt);
        const optionsDate = { timeZone: 'Asia/Manila', year: 'numeric', month: 'short', day: '2-digit' };
        const optionsTime = { timeZone: 'Asia/Manila', hour: '2-digit', minute: '2-digit', hour12: true };
        const dateStr = new Intl.DateTimeFormat('en-US', optionsDate).format(dt);
        const timeStr = new Intl.DateTimeFormat('en-US', optionsTime).format(dt);

        let agency = "Pending";
        let vehicle = "Pending";
        let responders = "Pending";

        if (['verified', 'dispatching', 'enroute', 'onscene', 'inprogress', 'resolved', 'closed'].includes(inc.status.toLowerCase())) {
            if (inc.category.toLowerCase() === 'fire') { agency = "BFP"; vehicle = inc.assignedUnit || "Fire Truck"; responders = "Fire Responders"; }
            else if (inc.category.toLowerCase() === 'medical') { agency = "Medical/EMS"; vehicle = inc.assignedUnit || "Ambulance"; responders = "Medical Responders"; }
            else if (inc.category.toLowerCase() === 'crime') { agency = "PNP"; vehicle = inc.assignedUnit || "Police Patrol"; responders = "Police Responders"; }
            else if (inc.category.toLowerCase() === 'flood' || inc.category.toLowerCase() === 'rescue') { agency = "MDRRMO"; vehicle = inc.assignedUnit || "Rescue Vehicle"; responders = "Rescue Team"; }
        }

        let eventsHtml = '';
        if (inc.events && inc.events.length > 0) {
            inc.events.forEach(ev => {
                eventsHtml += `
                    <div class="timeline-item">
                        <div class="timeline-dot"></div>
                        <div class="timeline-time">${ev.date_str} - ${ev.time_str}</div>
                        <div class="timeline-content">${ev.event_status}</div>
                    </div>
                `;
            });
        } else {
            // Default initial event
            eventsHtml = `
                <div class="timeline-item">
                    <div class="timeline-dot"></div>
                    <div class="timeline-time">${dateStr} - ${timeStr}</div>
                    <div class="timeline-content">Emergency Submitted</div>
                </div>
            `;
        }

        const modalDetails = document.getElementById("modal-history-details");
        const contentArea = document.getElementById("history-details-content");

        let draftActions = '';
        if (inc.status.toLowerCase() === 'draft') {
            draftActions = `
                <div style="margin-top: 15px; display: flex; gap: 10px;">
                    <button onclick="mobileClient.continueDraftById('${inc.id}')" style="flex:1; padding: 10px; background: #3b82f6; color: white; border: none; border-radius: 6px; font-weight: 600;">Continue Report</button>
                    <button onclick="mobileClient.cancelDraft('${inc.id}')" style="flex:1; padding: 10px; background: #ef4444; color: white; border: none; border-radius: 6px; font-weight: 600;">Cancel Draft</button>
                </div>
            `;
        }

        let resolutionData = '';
        if (inc.status.toLowerCase() === 'resolved') {
            resolutionData = `
                <div style="margin-top: 20px; background: #dcfce7; border: 1px solid #bbf7d0; padding: 15px; border-radius: 8px;">
                    <h3 style="margin: 0 0 10px 0; color: #166534; font-size: 14px;"><i class="fa-solid fa-circle-check"></i> Resolution Information</h3>
                    <div class="history-details">
                        <div><strong>Resolved By:</strong> ${agency} (${responders})</div>
                        <div><strong>Remarks:</strong> Emergency successfully resolved by the assigned response team.</div>
                    </div>
                </div>
            `;
        }

        contentArea.innerHTML = `
            <div style="background: white; border: 1px solid #e2e8f0; border-radius: 8px; padding: 15px; margin-bottom: 20px;">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px;">
                    <h3 style="margin: 0; font-size: 15px; color: #1e293b;">ALR-${dt.getFullYear()}-${String(inc.id).padStart(4, '0')}</h3>
                    <span class="history-status-badge history-badge-${inc.status.toLowerCase().replace(" ", "")}">${inc.status}</span>
                </div>
                <div class="history-details">
                    <div><strong>Type:</strong> <span style="text-transform: uppercase">${inc.category}</span></div>
                    <div><strong>Location:</strong> ${inc.location || "N/A"}</div>
                    <div><strong>Date/Time:</strong> ${dateStr} - ${timeStr}</div>
                </div>
                ${draftActions}
            </div>
            
            ${inc.status.toLowerCase() !== 'draft' && inc.status.toLowerCase() !== 'cancelled' ? `
            <div style="background: white; border: 1px solid #e2e8f0; border-radius: 8px; padding: 15px; margin-bottom: 20px;">
                <h3 style="margin: 0 0 10px 0; font-size: 14px; color: #1e293b;">Response Information</h3>
                <div class="history-details">
                    <div><strong>Assigned Agency:</strong> ${agency}</div>
                    <div><strong>Responders:</strong> ${responders}</div>
                    <div><strong>Rescue Vehicle:</strong> ${vehicle}</div>
                </div>
            </div>
            ` : ''}

            <h3 style="margin: 0 0 10px 0; font-size: 14px; color: #1e293b;">Emergency Timeline</h3>
            <div class="timeline-container">
                ${eventsHtml}
            </div>
            
            ${resolutionData}
        `;

        if (modalDetails) modalDetails.classList.remove("hidden");
    }

    continueDraftById(incidentId) {
        if (!this.historyData) return;
        const inc = this.historyData.find(i => String(i.id) === String(incidentId));
        if (inc) {
            document.getElementById("modal-history-details").classList.add("hidden");
            this.continueDraft(inc);
        }
    }

    continueDraft(incident) {
        this.activeIncident = incident;

        this.transitionAppState("chat");

        // Clear dynamic chat feed
        if (this.dynamicChatFeed) this.dynamicChatFeed.innerHTML = "";

        // Restore category UI selection
        this.selectedCategory = this.activeIncident.category || null;
        const categoryButtons = document.querySelectorAll(".chat-category-btn");
        categoryButtons.forEach(b => {
            b.classList.remove("active");
            if (this.selectedCategory && b.getAttribute("data-cat") === this.selectedCategory) {
                b.classList.add("active");
            }
        });


        this.chatDetailsInput.disabled = false;
        this.chatSendBtn.disabled = false;
        this.btnAttachMedia.disabled = false;

        // Restore ticket UI
        this.chatIncidentId.textContent = this.activeIncident.id;
        const dt = new Date(this.activeIncident.createdAt || Date.now());
        const timeString = new Date(dt).toLocaleString('en-US', {
            month: 'short', day: 'numeric', year: 'numeric',
            hour: 'numeric', minute: 'numeric', hour12: true
        });
        this.chatIncidentTime.textContent = timeString;
        this.reportStatusBadge.textContent = "Draft";
        this.reportStatusBadge.style.backgroundColor = "rgba(142, 142, 147, 0.15)";
        this.reportStatusBadge.style.color = "var(--text-secondary)";

        localStorage.setItem("alerto-active-incident", JSON.stringify(this.activeIncident));

        this.restoreChatHistory();
    }

    async restoreChatHistory() {
        if (!this.activeIncident) return;
        
        // Clear chat first to avoid duplication
        this.dynamicChatFeed.innerHTML = "";
        
        // Re-append selected category if it exists and isn't just a draft
        if (this.selectedCategory && (this.activeIncident.has_sent_messages || this.activeIncident.status !== 'draft')) {
             this.appendChatMessage("You", `Selected Category: ${this.selectedCategory.toUpperCase()}`, "outgoing-bubble", this.activeIncident.createdAt, this.activeUser?.profile_image, this.activeUser?.gender);
        }
        
        let hasNewMessages = false;
        
        // 1. Fetch new messages from the database
        if (this.activeIncident.id && !String(this.activeIncident.id).startsWith("DRAFT-")) {
            try {
                const response = await fetch(`${SERVER_URL}/api/incidents/${this.activeIncident.id}/messages`);
                if (response.ok) {
                    const data = await response.json();
                    if (data.success && data.messages && data.messages.length > 0) {
                        hasNewMessages = true;
                        data.messages.forEach(msg => {
                            const senderName = msg.sender_role === 'Citizen App' ? (String(msg.sender_id) === String(this.activeUser.id) ? 'You' : 'Citizen') : 'Command Center';
                            const bubbleClass = String(msg.sender_id) === String(this.activeUser.id) ? 'outgoing-bubble' : 'incoming-bubble';
                            
                            if (msg.message_type === 'text' && msg.message_content) {
                                this.appendChatMessage(senderName, msg.message_content, bubbleClass, msg.timestamp, msg.sender_profile_image, msg.sender_gender);
                            } else if ((msg.message_type === 'image' || msg.message_type === 'video') && msg.media_url) {
                                const attObj = {
                                    type: msg.message_type,
                                    data: `${SERVER_URL}${msg.media_url}`
                                };
                                this.appendMediaMessageBubble(attObj, senderName, bubbleClass, msg.timestamp, msg.sender_profile_image, msg.sender_gender);
                            }
                        });
                    }
                }
            } catch (e) {
                console.error("Failed to restore message history", e);
            }
        }

        // 2. Reconstruct legacy chat history from details ONLY if no new messages exist
        if (!hasNewMessages && this.activeIncident.details) {
            const parts = this.activeIncident.details.split(" | ");
            parts.forEach(part => {
                const trimmed = part.trim();
                if (trimmed.startsWith("Notes: ")) {
                    this.appendChatMessage("You", trimmed.replace("Notes: ", "").trim(), "outgoing-bubble", this.activeIncident.createdAt, this.activeUser?.profile_image, this.activeUser?.gender);
                } else if (trimmed.startsWith("Dispatcher: ")) {
                    this.appendChatMessage("Command Center", trimmed.replace("Dispatcher: ", "").trim(), "incoming-bubble", this.activeIncident.createdAt);
                } else if (trimmed) {
                    // Fallback
                    this.appendChatMessage("System", trimmed, "incoming-bubble", this.activeIncident.createdAt);
                }
            });
        }

        // 3. Ensure status updates from events are also logged if available
        if (this.activeIncident.events && Array.isArray(this.activeIncident.events)) {
            // Sort by timestamp
            const sortedEvents = this.activeIncident.events.sort((a, b) => a.timestamp - b.timestamp);
            sortedEvents.forEach(event => {
                if (event.event_status === 'SOS alert activated') {
                    // We only want to print non-chat events if they are meaningful status changes
                } else if (event.event_status !== 'chat_message' && event.event_status !== 'Emergency Details Updated') {
                    this.appendChatMessage("System", `Status Updated: ${event.event_status}`, "incoming-bubble", event.timestamp);
                }
            });
        }
    }

    async cancelDraft(incidentId) {
        if (this.isCancelingDraft) return;
        this.isCancelingDraft = true;
        if (!confirm("Are you sure you want to cancel this draft emergency? This action cannot be undone.")) {
            this.isCancelingDraft = false;
            return;
        }

        try {
            let res;
            if (incidentId && incidentId.startsWith('DRAFT-')) {
                const userId = this.activeUser?.id || incidentId.replace('DRAFT-', '');
                res = await fetch(`${SERVER_URL}/api/incidents/draft/${userId}`, {
                    method: 'DELETE'
                });
            } else {
                res = await fetch(`${SERVER_URL}/api/incidents/${incidentId}`, {
                    method: 'PUT',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ status: 'cancelled' })
                });
            }

            if (res.ok) {
                alert("Draft cancelled successfully.");
                const histDetails = document.getElementById("modal-history-details");
                if (histDetails) histDetails.classList.add("hidden");

                // Clear active incident if it matches
                if (this.activeIncident && this.activeIncident.id === incidentId) {
                    this.activeIncident = null;
                    localStorage.removeItem("alerto-active-incident");
                }

                if (this.modalDraftConflict) this.modalDraftConflict.classList.add("hidden");
                this.fetchHistory();
            } else {
                alert("Failed to cancel draft. Please try again.");
            }
        } catch (err) {
            alert("Network error: Could not cancel draft.");
            console.error(err);
        } finally {
            this.isCancelingDraft = false;
        }
    }

    setupMapSettings() {
        const btnMapSettings = document.getElementById("btn-map-settings");
        const panel = document.getElementById("map-settings-panel");
        const btnClose = document.getElementById("close-map-settings");
        const options = document.querySelectorAll(".map-type-option");

        if (!btnMapSettings || !panel) return;

        // Toggle panel
        btnMapSettings.addEventListener("click", () => {
            panel.classList.toggle("show");
        });

        // Close panel
        if (btnClose) {
            btnClose.addEventListener("click", () => {
                panel.classList.remove("show");
            });
        }

        // Close panel when clicking outside
        document.addEventListener("click", (e) => {
            if (!panel.contains(e.target) && !btnMapSettings.contains(e.target) && panel.classList.contains("show")) {
                panel.classList.remove("show");
            }
        });

        const tileLayers = {
            'default': 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            'satellite': 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
            'terrain': 'https://mt1.google.com/vt/lyrs=p&x={x}&y={y}&z={z}'
        };

        // Handle layer change
        options.forEach(opt => {
            opt.addEventListener("click", () => {
                if (!this.homeMap) return;

                // Update UI
                options.forEach(o => o.classList.remove("active"));
                opt.classList.add("active");

                // Update Map Layer
                const type = opt.dataset.type;
                if (tileLayers[type]) {
                    if (this.homeTileLayer) {
                        this.homeMap.removeLayer(this.homeTileLayer);
                    }
                    this.homeTileLayer = L.tileLayer(tileLayers[type]);
                    this.homeTileLayer.addTo(this.homeMap);
                    
                    localStorage.setItem("alerto_user_map_type", type);
                }

                // Close panel after selection on mobile
                if (window.innerWidth <= 768) {
                    panel.classList.remove("show");
                }
            });
        });
    }

    syncProfileUI() {
        if (!this.activeUser) return;

        const nameEl = document.getElementById("profile-display-name");
        if (nameEl) nameEl.textContent = this.activeUser.name || "";

        const emailEl = document.getElementById("profile-display-email");
        if (emailEl) emailEl.textContent = this.activeUser.email || this.activeUser.phone || "";

        const imgEl = document.getElementById("profile-avatar-img");
        const placeholderEl = document.getElementById("profile-avatar-placeholder");

        if (this.activeUser.profile_image && imgEl && placeholderEl) {
            let imgUrl = this.activeUser.profile_image;
            if (imgUrl.startsWith('/')) {
                imgUrl = SERVER_URL + imgUrl;
            }
            // Add cache-busting timestamp just in case
            if (!imgUrl.includes('?')) {
                imgUrl += "?t=" + new Date().getTime();
            }

            imgEl.onload = () => {
                imgEl.classList.remove("hidden");
                placeholderEl.classList.add("hidden");
            };
            imgEl.onerror = () => {
                imgEl.classList.add("hidden");
                placeholderEl.classList.remove("hidden");
            };
            imgEl.src = imgUrl;
        } else if (imgEl && placeholderEl) {
            imgEl.classList.add("hidden");
            placeholderEl.classList.remove("hidden");
        }
    }
}

let mobileClient;
document.addEventListener("DOMContentLoaded", () => {
    mobileClient = new CitizenMobileClient();
    window.mobileClient = mobileClient;
});

// Global Lightbox Logic (User Side)
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

    if (e.target.tagName === "IMG" && e.target.closest(".chat-message-bubble")) {
        const img = document.createElement("img");
        img.src = e.target.src;
        lightboxContainer.innerHTML = "";
        lightboxContainer.appendChild(img);
        lightbox.classList.remove("hidden");
    } else if (e.target.tagName === "VIDEO" && e.target.closest(".chat-message-bubble")) {
        const video = document.createElement("video");
        video.src = e.target.src;
        video.controls = true;
        video.autoplay = true;
        lightboxContainer.innerHTML = "";
        lightboxContainer.appendChild(video);
        lightbox.classList.remove("hidden");
    }
});



