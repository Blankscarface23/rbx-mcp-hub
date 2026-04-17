#!/usr/bin/env node
import http from "node:http";
import { URL } from "node:url";

const PORT = Number(process.env.RBX_MCP_HUB_PORT) || 44755;
const HOST = "127.0.0.1";
const LONG_POLL_MS = 15_000;
const COMMAND_TIMEOUT_MS = 60_000;
const PLUGIN_STALE_MS = 45_000;

const plugins = new Map();
const pending = new Map();

function log(...args) {
  process.stderr.write(`[hub] ${new Date().toISOString()} ${args.join(" ")}\n`);
}

function getPlugin(context) {
  let p = plugins.get(context);
  if (!p) {
    p = {
      context,
      name: null,
      queue: [],
      waiters: [],
      lastSeen: Date.now(),
      registeredAt: Date.now(),
    };
    plugins.set(context, p);
    log("plugin registered", context);
  }
  return p;
}

function deliverQueuedCommand(plugin, res) {
  const cmd = plugin.queue.shift();
  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(JSON.stringify(cmd));
}

function parkWaiter(plugin, res) {
  const waiter = { res, timer: null, settled: false };
  waiter.timer = setTimeout(() => {
    if (waiter.settled) return;
    waiter.settled = true;
    const idx = plugin.waiters.indexOf(waiter);
    if (idx >= 0) plugin.waiters.splice(idx, 1);
    res.writeHead(423);
    res.end();
  }, LONG_POLL_MS);
  plugin.waiters.push(waiter);
  res.on("close", () => {
    if (waiter.settled) return;
    waiter.settled = true;
    clearTimeout(waiter.timer);
    const idx = plugin.waiters.indexOf(waiter);
    if (idx >= 0) plugin.waiters.splice(idx, 1);
  });
}

function wakeWaiter(plugin) {
  while (plugin.queue.length > 0 && plugin.waiters.length > 0) {
    const waiter = plugin.waiters.shift();
    if (waiter.settled) continue;
    waiter.settled = true;
    clearTimeout(waiter.timer);
    deliverQueuedCommand(plugin, waiter.res);
  }
}

function parseBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => {
      const raw = Buffer.concat(chunks).toString("utf8");
      if (!raw) return resolve({});
      try {
        resolve(JSON.parse(raw));
      } catch (e) {
        reject(e);
      }
    });
    req.on("error", reject);
  });
}

function sendJson(res, code, obj) {
  res.writeHead(code, { "Content-Type": "application/json" });
  res.end(JSON.stringify(obj));
}

async function handleRequest(req, res, url) {
  const context = url.searchParams.get("context");
  const name = url.searchParams.get("name");
  if (!context) {
    return sendJson(res, 400, { error: "missing context query param" });
  }
  const plugin = getPlugin(context);
  plugin.lastSeen = Date.now();
  if (name && !plugin.name) plugin.name = name;

  if (plugin.queue.length > 0) {
    return deliverQueuedCommand(plugin, res);
  }
  parkWaiter(plugin, res);
}

async function handleResponse(req, res) {
  let body;
  try {
    body = await parseBody(req);
  } catch (e) {
    return sendJson(res, 400, { error: "invalid json" });
  }
  const { id, result, error } = body || {};
  if (!id) return sendJson(res, 400, { error: "missing id" });

  const entry = pending.get(id);
  if (!entry) {
    log("orphan response", id);
    return sendJson(res, 404, { error: "no pending command with that id" });
  }
  pending.delete(id);
  clearTimeout(entry.timer);
  sendJson(entry.res, 200, { id, result: result ?? null, error: error ?? null });
  sendJson(res, 200, { ok: true });
}

async function handleProxy(req, res) {
  let body;
  try {
    body = await parseBody(req);
  } catch (e) {
    return sendJson(res, 400, { error: "invalid json" });
  }
  const { id, context, tool, params } = body || {};
  if (!id || !tool) return sendJson(res, 400, { error: "missing id or tool" });

  const targetContext = context ?? null;
  if (!targetContext) {
    return sendJson(res, 400, {
      error: "missing context — set RBX_PLACE_ID in the bridge env",
    });
  }
  const plugin = plugins.get(targetContext);
  if (!plugin || Date.now() - plugin.lastSeen > PLUGIN_STALE_MS) {
    return sendJson(res, 404, {
      error: `no active plugin for context=${targetContext}. Open Studio on the correct place and verify the plugin is enabled.`,
    });
  }

  const timer = setTimeout(() => {
    if (!pending.has(id)) return;
    pending.delete(id);
    sendJson(res, 504, { error: "tool call timed out" });
  }, COMMAND_TIMEOUT_MS);

  pending.set(id, { res, timer, context: targetContext });
  plugin.queue.push({ id, tool, params: params ?? {} });
  wakeWaiter(plugin);

  res.on("close", () => {
    if (pending.has(id)) {
      clearTimeout(timer);
      pending.delete(id);
    }
  });
}

function handleStatus(req, res) {
  const now = Date.now();
  const list = [...plugins.values()].map((p) => ({
    context: p.context,
    name: p.name,
    connected: now - p.lastSeen <= PLUGIN_STALE_MS,
    queueDepth: p.queue.length,
    waiters: p.waiters.length,
    ageMs: now - p.registeredAt,
    lastSeenMs: now - p.lastSeen,
  }));
  sendJson(res, 200, {
    ok: true,
    port: PORT,
    plugins: list,
    pendingCommands: pending.size,
  });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${HOST}`);
  try {
    if (req.method === "GET" && url.pathname === "/request") {
      return handleRequest(req, res, url);
    }
    if (req.method === "POST" && url.pathname === "/response") {
      return handleResponse(req, res);
    }
    if (req.method === "POST" && url.pathname === "/proxy") {
      return handleProxy(req, res);
    }
    if (req.method === "GET" && url.pathname === "/status") {
      return handleStatus(req, res);
    }
    if (req.method === "GET" && url.pathname === "/") {
      return sendJson(res, 200, { name: "rbx-mcp-hub", port: PORT });
    }
    sendJson(res, 404, { error: "not found" });
  } catch (e) {
    log("handler error", e?.stack || String(e));
    try {
      sendJson(res, 500, { error: String(e?.message || e) });
    } catch {}
  }
});

setInterval(() => {
  const now = Date.now();
  for (const [ctx, p] of plugins) {
    if (now - p.lastSeen > PLUGIN_STALE_MS) {
      log("plugin stale, deregistering", ctx);
      for (const w of p.waiters) {
        if (!w.settled) {
          w.settled = true;
          clearTimeout(w.timer);
          try { w.res.writeHead(410); w.res.end(); } catch {}
        }
      }
      plugins.delete(ctx);
    }
  }
}, 15_000).unref();

server.listen(PORT, HOST, () => {
  log(`listening on http://${HOST}:${PORT}`);
});

server.on("error", (e) => {
  if (e.code === "EADDRINUSE") {
    log(`port ${PORT} already in use — another hub running?`);
    process.exit(2);
  }
  log("server error", e.message);
  process.exit(1);
});

for (const sig of ["SIGINT", "SIGTERM"]) {
  process.on(sig, () => {
    log(`received ${sig}, shutting down`);
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 1000).unref();
  });
}
