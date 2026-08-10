import { WebSocket } from "ws";

const URL = process.env.BRIDGE_URL || "ws://127.0.0.1:8080";
const INTERVAL_MS = Number(process.env.INTERVAL_MS || 2000);
const GIFT_POOL = [
  { type: "gift", gift: "Rose" },
  { type: "gift", gift: "Dragon" },
  { type: "gift", gift: "Castle" },
  { type: "gift", gift: "Phoenix" },
  { type: "share", gift: "Share" },
  { type: "gift", gift: "Skull" },
  { type: "gift", gift: "Heart" },
  { type: "gift", gift: "Tiger" },
];
// Commander-tier gifts: rare, spawn a whole bannered warband.
const COMMANDER_POOL = [
  { type: "gift", gift: "Galaxy", count: 1 },   // bronze
  { type: "gift", gift: "Rocket", count: 1 },   // silver
  { type: "gift", gift: "Universe", count: 1 }, // gold
];
const COMMANDER_CHANCE = Number(process.env.COMMANDER_CHANCE || 0.35);
const MAX_ACTIVE_COMMANDER_BURST = 4;
let commanderBursts = 0;
const USERS = [
  { id: "u_1001", name: "streamfan", team: "red" },
  { id: "u_1002", name: "tiff", team: "blue" },
  { id: "u_1003", name: "noodle", team: "blue" },
  { id: "u_1004", name: "grimace", team: "red" },
  { id: "u_1005", name: "owo", team: "blue" },
  { id: "u_1006", name: "kitten42", team: "red" },
  { id: "u_1007", name: "alex", team: "red" },
  { id: "u_1008", name: "bibi", team: "blue" },
];

const ws = new WebSocket(URL);

ws.on("open", () => {
  console.log(`connected to ${URL}; simulating a TikTok LIVE chat (unit + commander warband gifts)`);
  console.log("press Ctrl+C to stop");
  // viewers join a team by commenting
  for (const user of USERS) {
    if (user.team) {
      const payload = JSON.stringify({
        type: "comment",
        sender: user.name,
        userId: user.id,
        text: `${user.team} team`,
      });
      ws.send(payload);
      console.log(`sent ${payload}`);
    }
  }
  const tick = () => {
    if (ws.readyState !== WebSocket.OPEN) return;
    const user = USERS[Math.floor(Math.random() * USERS.length)];
    let payload;
    // Occasionally a viewer drops a big commander-tier gift -> whole warband.
    if (commanderBursts < MAX_ACTIVE_COMMANDER_BURST && Math.random() < COMMANDER_CHANCE) {
      const entry = COMMANDER_POOL[Math.floor(Math.random() * COMMANDER_POOL.length)];
      commanderBursts++;
      payload = JSON.stringify({
        type: entry.type,
        gift: entry.gift,
        sender: user.name,
        userId: user.id,
        count: entry.count,
      });
    } else {
      const entry = GIFT_POOL[Math.floor(Math.random() * GIFT_POOL.length)];
      const count = 1 + Math.floor(Math.random() * 5);
      payload = JSON.stringify({
        type: entry.type,
        gift: entry.gift,
        sender: user.name,
        userId: user.id,
        count,
      });
    }
    ws.send(payload);
    console.log(`sent ${payload}`);
  };
  tick();
  setInterval(tick, INTERVAL_MS);
});

ws.on("message", (data) => {
  try {
    const msg = JSON.parse(data.toString());
    if (msg.type === "status") console.log(`bridge: ${msg.message}`);
  } catch {
    /* ignore */
  }
});

ws.on("close", () => {
  console.log("connection closed");
  process.exit(0);
});

ws.on("error", (err) => {
  console.error("error:", err.message);
  console.error(`is the bridge running? start it with: npm start`);
  process.exit(1);
});
