/**
 * Shared Webcam UI Overlay for Alerto-poz (Desktop/Browser)
 * Avoids duplicating camera logic between the Admin Dashboard and Citizen Web App.
 */

let webcamStream = null;
let currentFacingMode = 'user'; // Default to front camera

function createWebcamUI() {
    if (document.getElementById('webcam-overlay')) return;

    const overlay = document.createElement('div');
    overlay.id = 'webcam-overlay';
    overlay.style.cssText = 'position: fixed; top: 0; left: 0; width: 100vw; height: 100vh; background: rgba(0,0,0,0.85); z-index: 99999; display: none; flex-direction: column; align-items: center; justify-content: center; font-family: "Outfit", sans-serif;';
    
    overlay.innerHTML = `
        <div style="background: #1e293b; padding: 20px; border-radius: 12px; box-shadow: 0 10px 25px rgba(0,0,0,0.5); text-align: center; max-width: 95vw; position: relative;">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px;">
                <h3 style="color: #fff; margin: 0;">Capture Photo</h3>
                <button id="webcam-btn-switch" style="padding: 8px 12px; background: #6366f1; color: white; border: none; border-radius: 6px; cursor: pointer; font-weight: bold; display: flex; align-items: center; gap: 6px; font-size: 13px;">
                    <i class="fa-solid fa-camera-rotate"></i> Switch Camera
                </button>
            </div>
            
            <div style="position: relative; background: #000; border-radius: 8px; overflow: hidden; margin-bottom: 15px;">
                <video id="webcam-video" autoplay playsinline style="width: 100%; max-width: 600px; max-height: 60vh; display: block;"></video>
                <canvas id="webcam-canvas" style="width: 100%; max-width: 600px; max-height: 60vh; display: none;"></canvas>
            </div>

            <div style="display: flex; gap: 10px; justify-content: center; flex-wrap: wrap;">
                <button id="webcam-btn-capture" style="padding: 10px 20px; background: #3b82f6; color: #fff; border: none; border-radius: 6px; cursor: pointer; font-weight: 600;">Capture</button>
                <button id="webcam-btn-retake" style="padding: 10px 20px; background: #f59e0b; color: #fff; border: none; border-radius: 6px; cursor: pointer; font-weight: 600; display: none;">Retake</button>
                <button id="webcam-btn-confirm" style="padding: 10px 20px; background: #10b981; color: #fff; border: none; border-radius: 6px; cursor: pointer; font-weight: 600; display: none;">Confirm</button>
                <button id="webcam-btn-cancel" style="padding: 10px 20px; background: #ef4444; color: #fff; border: none; border-radius: 6px; cursor: pointer; font-weight: 600;">Cancel</button>
            </div>
        </div>
    `;
    
    document.body.appendChild(overlay);
}

function stopWebcam() {
    if (webcamStream) {
        webcamStream.getTracks().forEach(track => track.stop());
        webcamStream = null;
    }
    const overlay = document.getElementById('webcam-overlay');
    if (overlay) overlay.style.display = 'none';
}

function startCameraStream(videoElement) {
    if (webcamStream) {
        webcamStream.getTracks().forEach(track => track.stop());
    }
    
    navigator.mediaDevices.getUserMedia({ video: { facingMode: currentFacingMode }, audio: false })
        .then(stream => {
            webcamStream = stream;
            videoElement.srcObject = stream;
        })
        .catch(err => {
            console.error("Camera access denied or unavailable", err);
            alert("Could not access webcam. Please allow camera permissions.");
            stopWebcam();
        });
}

/**
 * Attempts to open the custom desktop webcam overlay.
 * If the user is on mobile, returns false immediately so the caller can fallback to native capture.
 * @param {Function} onConfirmCallback - function(file) called when user confirms the capture.
 * @returns {boolean} - true if desktop UI opened, false if mobile.
 */
function openWebcamUI(onConfirmCallback) {
    createWebcamUI();
    const overlay = document.getElementById('webcam-overlay');
    const video = document.getElementById('webcam-video');
    const canvas = document.getElementById('webcam-canvas');
    const btnCapture = document.getElementById('webcam-btn-capture');
    const btnRetake = document.getElementById('webcam-btn-retake');
    const btnConfirm = document.getElementById('webcam-btn-confirm');
    const btnCancel = document.getElementById('webcam-btn-cancel');
    const btnSwitch = document.getElementById('webcam-btn-switch');

    // Reset UI state
    video.style.display = 'block';
    canvas.style.display = 'none';
    btnCapture.style.display = 'block';
    btnRetake.style.display = 'none';
    btnConfirm.style.display = 'none';
    overlay.style.display = 'flex';

    // Check if camera API is supported
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
        console.warn("Camera API not supported or blocked by insecure context. Falling back to native.");
        alert("Camera blocked! Ensure you are using 'localhost' or HTTPS to access the webcam. Falling back to native camera/gallery.");
        stopWebcam();
        return false; // Tells the app to use native capture="environment" instead
    }

    // Request Camera Access
    startCameraStream(video);

    // Switch Camera Logic
    btnSwitch.onclick = () => {
        currentFacingMode = currentFacingMode === 'user' ? 'environment' : 'user';
        startCameraStream(video);
    };

    // Capture Button Logic
    btnCapture.onclick = () => {
        canvas.width = video.videoWidth;
        canvas.height = video.videoHeight;
        canvas.getContext('2d').drawImage(video, 0, 0, canvas.width, canvas.height);
        
        video.style.display = 'none';
        canvas.style.display = 'block';
        
        btnCapture.style.display = 'none';
        btnRetake.style.display = 'block';
        btnConfirm.style.display = 'block';
    };

    // Retake Button Logic
    btnRetake.onclick = () => {
        canvas.style.display = 'none';
        video.style.display = 'block';
        
        btnRetake.style.display = 'none';
        btnConfirm.style.display = 'none';
        btnCapture.style.display = 'block';
    };

    // Confirm Button Logic
    btnConfirm.onclick = () => {
        canvas.toBlob((blob) => {
            if (!blob) return;
            const file = new File([blob], "webcam-capture-" + Date.now() + ".jpg", { type: "image/jpeg" });
            stopWebcam();
            if (onConfirmCallback) onConfirmCallback(file);
        }, 'image/jpeg', 0.9);
    };

    // Cancel Button Logic
    btnCancel.onclick = () => {
        stopWebcam();
    };

    return true;
}
