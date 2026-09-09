const fs = require('fs');
const jsdom = require("jsdom");
const { JSDOM } = jsdom;

const html = fs.readFileSync('client/mobile/index.html', 'utf8');
const script = fs.readFileSync('client/mobile/app.js', 'utf8');

const dom = new JSDOM(html, { runScripts: "outside-only" });
const window = dom.window;
global.window = window;
global.document = window.document;
global.navigator = window.navigator;

// Mock LocalStorage
global.localStorage = {
  getItem: () => null,
  setItem: () => {},
  removeItem: () => {}
};
global.io = () => ({ on: () => {} });
global.SERVER_URL = "http://localhost:3000";

try {
    window.eval(script);
    console.log("Script executed successfully without throwing during init.");
} catch (e) {
    console.error("Error during script execution:", e);
}
