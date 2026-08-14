import { WebSocketServer, WebSocket } from "ws";
import { createInterface } from "readline";
import http from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { connectTikTok, disconnectTikTok } from "./tiktok.js";

const PORT = Number(process.env.PORT || 8080);
const HOST = process.env.HOST || "0.0.0.0";
const MAX_GIFT_BURST = 200;
const TIKTOK_USERNAME = (process.env.TIKTOK_USERNAME || "").trim();

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC_DIR = path.resolve(__dirname, "../public");
const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript",
  ".css": "text/css",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".json": "application/json",
};

const server = http.createServer(async (req, res) => {
  let urlPath = decodeURIComponent((req.url || "/").split("?")[0]);
  if (urlPath === "/") urlPath = "/index.html";
  const filePath = path.normalize(path.join(PUBLIC_DIR, urlPath));
  if (!filePath.startsWith(PUBLIC_DIR)) {
    res.writeHead(403);
    res.end("forbidden");
    return;
  }
  try {
    const data = await readFile(filePath);
    res.writeHead(200, { "Content-Type": MIME[path.extname(filePath)] || "application/octet-stream" });
    res.end(data);
  } catch {
    res.writeHead(404, { "Content-Type": "text/plain" });
    res.end("not found");
  }
});

const wss = new WebSocketServer({ server, maxPayload: 4096 });
const clients = new Set();

function broadcast(msg) {
  const payload = typeof msg === "string" ? msg : JSON.stringify(msg);
  let sent = 0;
  for (const client of clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(payload);
      sent++;
    }
  }
  return sent;
}

function broadcastClients() {
  broadcast({ type: "clients", count: clients.size });
}

function log(tag, msg) {
  console.log(`[${new Date().toISOString()}] [${tag}] ${msg}`);
}

function sendGift(giftName, sender, userId, count) {
  const sent = broadcast({ type: "gift", gift: giftName, sender, userId, count });
  log("SEND", `${giftName} x${count} from ${sender} (${userId}) -> ${sent} client(s)`);
}

function sendComment(sender, userId, text) {
  const sent = broadcast({ type: "comment", sender, userId, text });
  log("SEND", `comment from ${sender} (${userId}): ${text} -> ${sent} client(s)`);
}

function handleInbound(data, socket) {
  let msg;
  try {
    msg = JSON.parse(data);
  } catch {
    log("WARN", "ignoring non-JSON message from client");
    return;
  }
  const userId = String(msg?.userId ?? msg?.sender ?? "unknown");
  if (msg?.type === "gift" || msg?.type === "share") {
    const giftName = String(msg.gift ?? "");
    const sender = String(msg.sender ?? "unknown");
    const count = Math.max(1, Math.min(MAX_GIFT_BURST, Number(msg.count) || 1));
    if (!giftName) {
      log("WARN", "gift message missing 'gift' field");
      return;
    }
    sendGift(giftName, sender, userId, count);
  } else if (msg?.type === "comment") {
    const sender = String(msg.sender ?? "unknown");
    const text = String(msg.text ?? "");
    if (!text) {
      log("WARN", "comment message missing 'text' field");
      return;
    }
    sendComment(sender, userId, text);
  } else if (msg?.type === "cmd") {
    const cmd = String(msg.cmd ?? "");
    if (!cmd) {
      log("WARN", "cmd message missing 'cmd' field");
      return;
    }
    const sent = broadcast({ type: "cmd", cmd });
    log("SEND", `cmd ${cmd} -> ${sent} client(s)`);
  } else if (msg?.type === "ping") {
    socket.send(JSON.stringify({ type: "pong" }));
  } else {
    log("WARN", `unhandled message type: ${msg?.type}`);
  }
}

wss.on("connection", (socket) => {
  clients.add(socket);
  log("INFO", `client connected (${clients.size} total)`);
  socket.send(JSON.stringify({ type: "status", connected: true, message: "gift-siege-bridge ready" }));
  broadcastClients();

  socket.on("message", (data) => handleInbound(data.toString(), socket));
  socket.on("close", () => {
    clients.delete(socket);
    log("INFO", `client disconnected (${clients.size} total)`);
    broadcastClients();
  });
  socket.on("error", (err) => {
    log("ERROR", err.message);
    clients.delete(socket);
    broadcastClients();
  });
});

server.on("listening", () => {
  log("INFO", `gift-siege panel http://${HOST}:${PORT}  |  ws://${HOST}:${PORT}`);
  if (TIKTOK_USERNAME) {
    log("INFO", `TikTok LIVE connecting to @${TIKTOK_USERNAME}...`);
    connectTikTok(TIKTOK_USERNAME, broadcast);
  } else {
    log("INFO", "TIKTOK_USERNAME not set - live TikTok disabled (simulation/test panel only)");
  }
});

server.on("error", (err) => {
  log("ERROR", `server error: ${err.message}`);
  process.exit(1);
});

const rl = createInterface({ input: process.stdin, output: process.stdout });
rl.on("line", (line) => {
  const trimmed = line.trim();
  if (!trimmed) return;
  if (trimmed.toLowerCase().startsWith("comment ")) {
    const rest = trimmed.slice("comment ".length).trim();
    const idx = rest.lastIndexOf(" ");
    if (idx === -1) {
      sendComment(rest, rest, rest.includes("blue") ? "blue team" : "red team");
    } else {
      const sender = rest.slice(0, idx).trim();
      const text = rest.slice(idx + 1).trim();
      sendComment(sender, sender, text);
    }
    return;
  }
  if (trimmed.toLowerCase().startsWith("cmd ")) {
    broadcast({ type: "cmd", cmd: trimmed.slice(4).trim() });
    return;
  }
  const parts = trimmed.split(/\s+/);
  const giftName = parts[0];
  const count = parts.length > 1 ? Number(parts[1]) || 1 : 1;
  const sender = parts.length > 2 ? parts[2] : "console";
  sendGift(giftName, sender, sender, count);
});

console.log("Terminal:  <Gift> [count] [sender]   OR   comment <sender> <text>   OR   cmd <name>");

function shutdown() {
  log("INFO", "shutting down...");
  disconnectTikTok();
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 1000).unref();
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

server.listen(PORT, HOST);
