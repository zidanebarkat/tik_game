import { TikTokLiveConnection, WebcastEvent } from "tiktok-live-connector";

const MAX_GIFT_BURST = 200;
const RECONNECT_BASE_MS = 5000;
const RECONNECT_MAX_MS = 60000;

let connection = null;
let reconnectAttempt = 0;
let reconnectTimer = null;
let stopped = false;
let emitStatus = () => {};

function log(tag, msg) {
  console.log(`[${new Date().toISOString()}] [${tag}] ${msg}`);
}

function normalizeUser(data) {
  const user = data?.user || {};
  const uniqueId = user.uniqueId || user.nickname || "viewer";
  const userId = String(user.userId ?? user.uniqueId ?? uniqueId);
  const nickname = user.nickname || uniqueId;
  return { uniqueId, userId, nickname };
}

function onChat(broadcast, data) {
  const { uniqueId, userId } = normalizeUser(data);
  const text = String(data.comment ?? "").trim();
  if (!text) return;
  broadcast({ type: "comment", sender: uniqueId, userId, text });
  log("TTK", `comment ${uniqueId}: ${text}`);
}

function onGift(broadcast, data) {
  const { uniqueId, userId } = normalizeUser(data);
  const giftType = data.giftDetails?.giftType;
  const giftName = data.giftDetails?.giftName ?? data.extendedGiftInfo?.name ?? "";
  const giftId = String(data.giftId ?? "");
  const repeatEnd = data.repeatEnd === true;
  const repeatCount = Math.max(1, Number(data.repeatCount ?? 1));

  if (giftType === 1 && !repeatEnd) {
    return;
  }
  const count = Math.min(MAX_GIFT_BURST, Math.max(1, repeatCount));
  const name = giftName || (giftId ? `Gift#${giftId}` : "Gift");
  broadcast({ type: "gift", gift: name, giftId, sender: uniqueId, userId, count });
  log("TTK", `gift ${name} (id ${giftId}) x${count} from ${uniqueId}`);
}

function onShare(broadcast, data) {
  const { uniqueId, userId } = normalizeUser(data);
  broadcast({ type: "gift", gift: "Share", sender: uniqueId, userId, count: 1 });
  log("TTK", `share from ${uniqueId}`);
}

function onMember(broadcast, data) {
  const { uniqueId, userId } = normalizeUser(data);
  broadcast({ type: "member", sender: uniqueId, userId });
  log("TTK", `member joined ${uniqueId}`);
}

function scheduleReconnect() {
  if (stopped) return;
  const delay = Math.min(RECONNECT_MAX_MS, RECONNECT_BASE_MS * 2 ** reconnectAttempt);
  reconnectAttempt += 1;
  log("TTK", `reconnecting in ${Math.round(delay / 1000)}s (attempt ${reconnectAttempt})`);
  emitStatus({ connected: false, message: `reconnecting in ${Math.round(delay / 1000)}s` });
  reconnectTimer = setTimeout(connectNow, delay);
}

async function connectNow() {
  if (stopped) return;
  const cleanName = String(connection?.username || "").replace(/^@/, "").trim();
  if (!cleanName) return;
  await openConnection(cleanName, emitStatus);
}

async function openConnection(cleanName, broadcast) {
  try {
    const conn = new TikTokLiveConnection(cleanName, { enableExtendedGiftInfo: true });
    conn.username = cleanName;
    connection = conn;

    conn.on(WebcastEvent.CHAT, (d) => onChat(broadcast, d));
    conn.on(WebcastEvent.GIFT, (d) => onGift(broadcast, d));
    conn.on(WebcastEvent.SHARE, (d) => onShare(broadcast, d));
    conn.on(WebcastEvent.SOCIAL, (d) => onShare(broadcast, d));
    conn.on(WebcastEvent.MEMBER, (d) => onMember(broadcast, d));
    conn.on(WebcastEvent.STREAM_END, () => {
      log("TTK", "stream ended");
      emitStatus({ connected: false, message: "stream ended" });
      scheduleReconnect();
    });

    await conn.connect();
    reconnectAttempt = 0;
    const roomId = conn.state?.roomId ?? "?";
    log("TTK", `connected to @${cleanName} (roomId ${roomId})`);
    emitStatus({ connected: true, message: `connected to @${cleanName}` });
  } catch (err) {
    const msg = err?.message ?? String(err);
    log("TTK", `connect failed: ${msg}`);
    if (!stopped) scheduleReconnect();
  }
}

export async function connectTikTok(username, broadcast) {
  if (connection) {
    try {
      await connection.disconnect();
    } catch {
      /* ignore */
    }
    connection = null;
  }
  stopped = false;
  reconnectAttempt = 0;

  const cleanName = String(username || "").replace(/^@/, "").trim();
  emitStatus = (status) => broadcast({ type: "tiktok", ...status });
  if (!cleanName) {
    emitStatus({ connected: false, message: "no TIKTOK_USERNAME set" });
    log("TTK", "TIKTOK_USERNAME not set; TikTok live disabled");
    return;
  }

  const holder = { username: cleanName };
  connection = holder;
  await openConnection(cleanName, broadcast);
}

export function disconnectTikTok() {
  stopped = true;
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
  if (connection?.disconnect) {
    try {
      connection.disconnect();
    } catch {
      /* ignore */
    }
  }
  connection = null;
}
