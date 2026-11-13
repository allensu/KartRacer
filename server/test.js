// Minimal protocol test: create, join, relay, start, host leave.
const assert = require("assert");
const WebSocket = require("ws");
const { createServer } = require("./server");

function client(url) {
  const ws = new WebSocket(url);
  const queue = [];
  const waiters = [];
  ws.on("message", (m) => {
    const msg = JSON.parse(m.toString());
    const w = waiters.findIndex((x) => x.t === msg.t);
    if (w >= 0) waiters.splice(w, 1)[0].resolve(msg);
    else queue.push(msg);
  });
  return {
    ws,
    open: () => new Promise((r) => ws.on("open", r)),
    send: (o) => ws.send(JSON.stringify(o)),
    next: (t) =>
      new Promise((resolve) => {
        const i = queue.findIndex((x) => x.t === t);
        if (i >= 0) resolve(queue.splice(i, 1)[0]);
        else waiters.push({ t, resolve });
      }),
  };
}

(async () => {
  const { server, wss } = createServer();
  await new Promise((r) => server.listen(0, r));
  const url = "ws://localhost:" + server.address().port;
  const a = client(url), b = client(url);
  await Promise.all([a.open(), b.open()]);

  a.send({ t: "create", name: "Ann" });
  const ja = await a.next("joined");
  assert.strictEqual(ja.code.length, 4);
  b.send({ t: "join", code: ja.code.toLowerCase(), name: "Bob" });
  const jb = await b.next("joined");
  assert.strictEqual(jb.players.length, 2);
  assert.strictEqual((await a.next("lobby")).players.length, 2);

  b.send({ t: "relay", d: { hello: 1 } });
  const relayed = await a.next("msg");
  assert.deepStrictEqual(relayed.d, { hello: 1 });
  assert.strictEqual(relayed.from, jb.id);

  b.send({ t: "start" }); // not host: ignored
  a.send({ t: "start" });
  const sa = await a.next("start"), sb = await b.next("start");
  assert.strictEqual(sa.seed, sb.seed);

  const c = client(url);
  await c.open();
  c.send({ t: "join", code: ja.code, name: "Cat" });
  assert.match((await c.next("error")).msg, /started/);

  a.ws.close();
  assert.strictEqual((await b.next("closed")).t, "closed");

  for (const x of [b, c]) x.ws.close();
  wss.close();
  server.close();
  console.log("relay tests passed");
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
