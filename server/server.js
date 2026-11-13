// KartRacer relay server.
//
// Players create or join a room with a 4-letter code. The first player is the
// host: the host's game simulates the AI karts and decides when a race starts.
// The server does no game simulation; it only forwards messages between the
// players in a room. Protocol (JSON text frames):
//
//   client -> server
//     {t:"create", name}            open a new room, become host
//     {t:"join", code, name}        join an open room
//     {t:"start"}                   host only: begin a race (relayed as "start")
//     {t:"lobby"}                   host only: race over, return to the lobby
//     {t:"relay", d}                forward d to everyone else in the room
//     {t:"ping"}                    keep-alive
//   server -> client
//     {t:"joined", code, id, hostId, players}
//     {t:"lobby", hostId, players}  membership changed (back:true = race over,
//                                   everyone returns to the lobby)
//     {t:"start", seed, players}    race begins
//     {t:"msg", from, d}            relayed payload
//     {t:"closed", reason}          room ended (host left)
//     {t:"error", msg}

const http = require("http");
const { WebSocketServer } = require("ws");

const MAX_PLAYERS = 4;
const NAME_MAX = 12;
const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ"; // no I/O to avoid confusion
const MAX_MESSAGE_BYTES = 16 * 1024;

const rooms = new Map(); // code -> {code, hostId, players: [{id, name, ws}], racing}
let nextId = 1;

function makeCode() {
  for (;;) {
    let code = "";
    for (let i = 0; i < 4; i++) code += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
    if (!rooms.has(code)) return code;
  }
}

function cleanName(name, fallback) {
  const s = String(name || "").replace(/[^\x20-\x7E]/g, "").trim().slice(0, NAME_MAX);
  return s || fallback;
}

function send(ws, obj) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj));
}

function roster(room) {
  return room.players.map((p) => ({ id: p.id, name: p.name }));
}

function broadcast(room, obj, exceptId) {
  const text = JSON.stringify(obj);
  for (const p of room.players) {
    if (p.id !== exceptId && p.ws.readyState === p.ws.OPEN) p.ws.send(text);
  }
}

function leave(ws) {
  const room = ws.room;
  if (!room) return;
  ws.room = null;
  room.players = room.players.filter((p) => p.ws !== ws);
  if (ws.playerId === room.hostId || room.players.length === 0) {
    broadcast(room, { t: "closed", reason: "Host left the room" });
    for (const p of room.players) p.ws.room = null;
    rooms.delete(room.code);
    return;
  }
  broadcast(room, { t: "lobby", hostId: room.hostId, players: roster(room) });
}

function handle(ws, msg) {
  switch (msg.t) {
    case "ping":
      send(ws, { t: "pong" });
      return;
    case "create": {
      leave(ws);
      const room = { code: makeCode(), hostId: ws.playerId, players: [], racing: false };
      rooms.set(room.code, room);
      room.players.push({ id: ws.playerId, name: cleanName(msg.name, "Player 1"), ws });
      ws.room = room;
      send(ws, { t: "joined", code: room.code, id: ws.playerId, hostId: room.hostId, players: roster(room) });
      return;
    }
    case "join": {
      const code = String(msg.code || "").toUpperCase().trim();
      const room = rooms.get(code);
      if (!room) return send(ws, { t: "error", msg: "Room " + code + " not found" });
      if (room.racing) return send(ws, { t: "error", msg: "That race has already started" });
      if (room.players.length >= MAX_PLAYERS) return send(ws, { t: "error", msg: "Room is full (4 players)" });
      leave(ws);
      room.players.push({ id: ws.playerId, name: cleanName(msg.name, "Player " + (room.players.length + 1)), ws });
      ws.room = room;
      send(ws, { t: "joined", code: room.code, id: ws.playerId, hostId: room.hostId, players: roster(room) });
      broadcast(room, { t: "lobby", hostId: room.hostId, players: roster(room) }, ws.playerId);
      return;
    }
    case "start": {
      const room = ws.room;
      if (!room || room.hostId !== ws.playerId) return;
      room.racing = true;
      broadcast(room, { t: "start", seed: Math.floor(Math.random() * 1e9), players: roster(room) });
      return;
    }
    case "lobby": {
      // Host returns everyone to the lobby after a race so new players can join.
      const room = ws.room;
      if (!room || room.hostId !== ws.playerId) return;
      room.racing = false;
      broadcast(room, { t: "lobby", hostId: room.hostId, players: roster(room), back: true });
      return;
    }
    case "relay": {
      const room = ws.room;
      if (!room) return;
      broadcast(room, { t: "msg", from: ws.playerId, d: msg.d }, ws.playerId);
      return;
    }
    default:
      send(ws, { t: "error", msg: "Unknown message" });
  }
}

function createServer() {
  const server = http.createServer((req, res) => {
    if (req.url === "/health" || req.url === "/") {
      res.writeHead(200, { "Content-Type": "text/plain", "Access-Control-Allow-Origin": "*" });
      res.end("ok " + rooms.size + " rooms\n");
      return;
    }
    res.writeHead(404);
    res.end();
  });
  const wss = new WebSocketServer({ server, maxPayload: MAX_MESSAGE_BYTES });
  wss.on("connection", (ws) => {
    ws.playerId = nextId++;
    ws.room = null;
    ws.alive = true;
    ws.on("pong", () => (ws.alive = true));
    ws.on("message", (data) => {
      let msg;
      try {
        msg = JSON.parse(data.toString());
      } catch {
        return;
      }
      if (msg && typeof msg.t === "string") handle(ws, msg);
    });
    ws.on("close", () => leave(ws));
  });
  // Drop dead connections so rooms don't linger.
  const timer = setInterval(() => {
    for (const ws of wss.clients) {
      if (!ws.alive) {
        ws.terminate();
        continue;
      }
      ws.alive = false;
      ws.ping();
    }
  }, 15000);
  wss.on("close", () => clearInterval(timer));
  return { server, wss };
}

if (require.main === module) {
  const port = Number(process.env.PORT) || 8080;
  createServer().server.listen(port, () => console.log("KartRacer relay listening on " + port));
}

module.exports = { createServer };
