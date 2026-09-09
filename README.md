# Alerto-POZ

**Alerto-POZ** is a mobile and web-based emergency notification and community reporting platform designed specifically for the Municipality of Pozorrubio, Pangasinan. The system provides real-time alerts, incident reporting, and emergency communication to improve disaster preparedness, public safety, and response coordination within the municipality.

---

## 📖 Overview

Alerto-POZ is a localized emergency management system that helps residents, barangay officials, and municipal emergency responders stay informed during emergencies such as floods, fires, typhoons, road accidents, earthquakes, and other public safety incidents. The platform enables faster communication between the community and local authorities, allowing emergency responders to act quickly and efficiently.

Accessible through both a mobile application and a web-based dashboard, Alerto-POZ supports the municipality's disaster risk reduction and management efforts by providing reliable, real-time information for decision-making and emergency response.

---

## 🌟 Key Features

### Real-Time Emergency Alerts
Residents receive instant notifications about emergencies, weather advisories, road closures, and disaster-related announcements occurring within Pozorrubio, Pangasinan.

### Conversational Incident Reporting
Users can report emergencies (such as fires, floods, accidents, fallen trees, or other hazards) through an interactive chat interface. Support is included for selecting incident categories, writing comments, and attaching media logs (photos/videos).

### Dynamic Location redirectional Router
Opening the root URL (`http://localhost:3000/`) automatically identifies the client device:
*   **Mobile Phones/Tablets** are redirected directly to the mobile citizen portal at `/mobile`.
*   **PCs/Desktops/Laptops** are redirected directly to the command center management dashboard at `/dashboard`.

### Web-Based Monitoring Dashboard
Municipal Disaster Risk Reduction and Management Office (MDRRMO) personnel and authorized administrators can monitor reported incidents, verify reports, manage alerts, and track emergency activities through a centralized web dashboard.

### Interactive Map & Dispatch Routing
The system displays reported incidents and check-ins on an interactive map. When a responder vehicle is dispatched, its location animates in real time on both the dispatcher map and the citizen console.

### Bidirectional Calling Simulation
Integrated calling modules allow citizens to initiate voice or video streams directly from the SOS chat. Incoming calls trigger high-priority alerts on the command dashboard allowing dispatchers to Accept or Decline calls with synchronized timers.

### Push Notifications & Advisory Broadcasts
MDRRMO administrators can push severe hazard warnings or evacuations. Citizens receive immediate visual banner warnings accompanied by audible sirens.

### Offline Queue Buffer
If network coverage drops, citizen reports are cached in the device storage and automatically transmitted upon reconnection.

---

## 🎁 Benefits for the Municipality of Pozorrubio
*   Improves communication between residents and emergency responders.
*   Enables faster reporting and response during emergencies.
*   Enhances disaster preparedness through timely notifications.
*   Assists the Municipal Disaster Risk Reduction and Management Office (MDRRMO) in monitoring incidents.
*   Supports informed decision-making using real-time community-generated reports.
*   Promotes public safety and community participation in disaster risk reduction.
*   Contributes to a more resilient and disaster-ready municipality.

---

## 👥 Target Users
*   Residents of Pozorrubio, Pangasinan
*   Barangay Officials
*   Municipal Disaster Risk Reduction and Management Office (MDRRMO)
*   Municipal Government Officials
*   Police, Fire, and Emergency Response Personnel

---

## 📱 System Availability

### Mobile Application
*   **Android devices**: Supported natively (compiled via Capacitor/Android Studio workspace) and as a mobile web application.
*   **iOS devices**: Supported via mobile-responsive web layouts (native iOS project is a future enhancement).

### Web Platform
*   Accessible through any modern web browser for municipal administrators, MDRRMO dispatchers, and authorized personnel.

---

## 🏗️ Technical Architecture & Developer Setup

### 📂 Directory & File Map
*   **`client/`**
    *   **`mobile/`**: Citizen app layouts, styles, and Javascript code for maps, alerts, call simulation, and geolocation.
    *   **`dashboard/`**: Authority command center displaying log feeds, maps, warning broadcast inputs, and analytics bars.
*   **`server/`**
    *   **`server.js`**: Core Express server and Socket.io WebSocket hub.
    *   **`schema.sql`**: seeds database structures under citizen **Carlo Nimer**.
*   **`android/`**: Capacitor native Android Studio project source files.
*   **`capacitor.config.json`**: Capacitor build pathways targeting `client/mobile` assets.

### ⚙️ Installation & Running Locally

1. Navigate to the server directory:
   ```bash
   cd server
   ```
2. Install npm packages:
   ```bash
   npm install
   ```
3. Start the Node.js server:
   ```bash
   npm start
   ```
The backend server will run on port `3000`. Open `http://localhost:3000` in your web browser. Device-responsive redirection will automatically guide you to the correct interface.

---

## 🧪 Interactive Walkthrough Demo Guide

For the best demonstration experience, open `http://localhost:3000` in two side-by-side browser windows (one simulating a desktop dashboard, the other in mobile device simulation mode):

1.  **Citizen Login**: On the mobile view, log in with phone `09123456789` and PIN `1234` (Carlo Nimer).
2.  **Drafting an SOS**: Click the floating SOS button on the mobile map. The chat window opens in a drafting state.
3.  **Categories & Comments**: Tap `BARANGAY` in the category grid, type "Bued River overflowing near Cablong dike" in the comments bar, and attach a sample file. Previews display instantly in the chat.
4.  **Simulating Calls**:
    *   Click the **Phone** icon in the chat header.
    *   Watch the dispatcher dashboard immediately overlay an incoming call notice: **"Incoming Emergency Call from Carlo Nimer..."**.
    *   Click **Accept** on the dashboard. Timers will sync and start ticking on both screens.
    *   Click **Hang Up** to end the simulation.
5.  **Transmitting the Alert**: Click **SEND SOS ALERT** in the mobile category grid. Watch the 5-second progress ring countdown complete. The incident is instantly logged in the dispatcher's alerts panel.
6.  **Responder Dispatch**: Click **Manage** next to the incident on the dashboard, select an ambulance or patrol patrol vehicle, and click **Dispatch**. The vehicle marker will move along the route on both the dispatcher's map and the citizen's console.
