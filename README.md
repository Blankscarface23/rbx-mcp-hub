# rbx-mcp-hub

<p align="center">
  <img src="https://raw.githubusercontent.com/Blankscarface23/rbx-mcp-hub/master/assets/rbx-mcp-hub.png" alt="rbx-mcp-hub" width="180">
</p>

Free, MIT-licensed multi-place MCP hub for Roblox Studio.
Route Claude Code, Cursor, Codex, or any other MCP-speaking AI agent to
the correct Studio window by PlaceId so you can work on multiple Roblox
games at the same time, one agent session per game, with no
command-queue races.

## Why this exists

Roblox's official MCP servers — the (now archived) `studio-rust-mcp-server`
and the built-in Studio MCP server — share a single command queue across
every open Studio window. The built-in server does expose
`list_roblox_studios` + `set_active_studio` tools, but they require the
agent to explicitly "switch" Studios per tool call; you also hit races
when two agents send commands concurrently.

rbx-mcp-hub solves this by adding **PlaceId-based routing** on top of the
same HTTP protocol:

- One **hub daemon** binds `127.0.0.1:44755` (singleton).
- One **MCP bridge** per Claude project; `.mcp.json` stamps its
  `RBX_PLACE_ID` onto every outbound tool call.
- One **Studio plugin** per open place; registers with
  `context = tostring(game.PlaceId)` on load.

The hub matches by context. Every Claude session is permanently wired to
its game's PlaceId — no per-call switching, no races.

## Works with any MCP client

The bridge is a plain stdio MCP server — any client that supports
stdio MCP can use it. That includes Claude Code, Cursor, Codex, Cline,
and Continue. `rbx-mcp-hub init` writes a Claude-Code-flavored
`.mcp.json`; for other clients, point your client's MCP config at
`node <repo>/src/bridge.js` with `RBX_PLACE_ID` (and optionally
`RBX_PLACE_NAME`) in the env.

## Architecture

```
┌───────────────────┐   stdio MCP   ┌──────────────┐
│  Claude Code      │──────────────▶│  MCP Bridge  │
│  (project A)      │               │  (per-proj)  │
└───────────────────┘               └──────┬───────┘
┌───────────────────┐   stdio MCP   ┌──────▼───────┐
│  Claude Code      │──────────────▶│  MCP Bridge  │
│  (project B)      │               │  (per-proj)  │
└───────────────────┘               └──────┬───────┘
                                            │ HTTP (context=PlaceId)
                                            ▼
                                    ┌────────────────┐
                                    │   Hub Daemon   │ :44755
                                    │   (singleton)  │
                                    └───┬──────┬─────┘
                                        │ long-poll per-context
                          ┌─────────────┘      └─────────────┐
                          ▼                                  ▼
                ┌────────────────┐                 ┌────────────────┐
                │ Studio Plugin  │                 │ Studio Plugin  │
                │ PlaceId: 1234  │                 │ PlaceId: 5678  │
                └────────────────┘                 └────────────────┘
```

## Prerequisites

- Node.js 18 or newer (`node -v`)
- Git
- Roblox Studio

No Rust or Rojo toolchain required. The Studio plugin ships prebuilt in
the repo.

## First-time install

```bash
# 1. Install from npm
npm install -g rbx-mcp-hub

# 2. Copy the Studio plugin .rbxm into Roblox's Plugins folder
rbx-mcp-hub install-plugin

# 3. Start the hub daemon (runs in background)
rbx-mcp-hub start
```

Prefer source? `git clone https://github.com/Blankscarface23/rbx-mcp-hub.git && cd rbx-mcp-hub && npm install && npm link` and continue from step 2.

Keep the hub running — it's a long-lived singleton. Re-run
`rbx-mcp-hub start` after reboots, or wire it into your OS's startup
manager.

## Per-project setup

From inside each Roblox game project directory:

```bash
rbx-mcp-hub init
```

You'll be prompted for the game's PlaceId. Use the number from the
Creator Dashboard URL, or run `print(game.PlaceId)` in Studio's command
bar. For unpublished drafts, enter `0`.

The command writes a `.mcp.json` that points at the bridge and sets
`RBX_PLACE_ID`. Open the place in Studio, then open Claude Code in the
project folder — Claude will prompt to authorize the MCP server; accept.

## Verify it's working

1. In each Studio window, look at the Output tab. You should see:
   ```
   [rbx-mcp-hub] 🔌 v0.1.0 · PlaceId=<id> · Name=<place> · hub 127.0.0.1:44755
   [rbx-mcp-hub] 🟢 connected
   ```
   The toolbar button is highlighted when connected. Click it to pause
   or resume the connection.

2. Run `rbx-mcp-hub status` — every Studio should appear:
   ```
   hub on 127.0.0.1:44755
     ✓ placeId=1234 name=MyGame queue=0 lastSeen=2s ago
     ✓ placeId=5678 name=OtherGame queue=0 lastSeen=1s ago
   ```

3. In Claude Code, call `get_studio_mode` from the rbx-mcp-hub MCP
   server. A response that matches the right place confirms end-to-end
   routing.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `hub unreachable at 127.0.0.1:44755` in Claude Code | Hub daemon not running | `rbx-mcp-hub start` |
| `no active plugin for context=<id>` | Studio isn't open on that place, plugin disabled, or `RBX_PLACE_ID` in `.mcp.json` doesn't match `game.PlaceId` | Open the correct place; enable `rbx-mcp-hub` in Plugins → Manage Plugins; double-check `.mcp.json` |
| `🔴 disconnected · ConnectionRefused` in Studio Output | Hub crashed or not started | `rbx-mcp-hub status`, restart if needed |
| Two Studios both route to each other | Both places have `PlaceId = 0` (unpublished) | Only run one unpublished place at a time, or publish both |
| Tool call goes to the wrong Studio anyway | Stale `RBX_PLACE_ID` (you published after `init`) | Edit `.mcp.json` with the real PlaceId and restart Claude Code; the plugin auto-re-registers when `game.PlaceId` changes |
| `start_stop_play` / `run_script_in_play_mode` return "not implemented" | Known v0.1 limitation — Studio's public plugin API can't toggle Play mode | Use F5/F7/F8 manually for now |

## Alternatives

| Tool | Price | Multi-place | Notes |
| --- | --- | --- | --- |
| **rbx-mcp-hub** (this) | Free, MIT | ✅ per-project auto-routing by PlaceId | Narrow tool; no bulk ops |
| Roblox built-in Studio MCP | Free, ships with Studio | ⚠️ via manual `set_active_studio` per call | Recommended for single-user workflows |
| [Roblox/studio-rust-mcp-server](https://github.com/Roblox/studio-rust-mcp-server) | Free, MIT, **archived** | ❌ single queue | Superseded by the built-in |
| [boshyxd/robloxstudio-mcp](https://github.com/boshyxd/robloxstudio-mcp) | Free, MIT | ❌ single queue | Broad tool surface (50+ tools) |
| [hope1026/weppy-roblox-mcp](https://github.com/hope1026/weppy-roblox-mcp) | Free tier + paid Pro | ✅ (Pro only) | Bundles multi-place with terrain, audio, bidirectional sync, etc. |

Pick rbx-mcp-hub if you want a free, minimal, zero-config-per-call way to
run multiple Claude sessions against multiple Studios. Pick the built-in
if you're a single user juggling two Studios and don't mind per-call
switching. Pick WEPPY Pro if you want the full feature bundle.

## Rebuilding the plugin (contributors only)

Plugin source is under `plugin/src/`. Studio's built-in Script Sync
works fine for iterating: open a blank place, enable Script Sync against
`plugin/src/`, then use **Save as Local Plugin** to rebuild the .rbxm.
Rojo also works (`rojo build plugin/default.project.json -o
plugin/build/rbx-mcp-hub.rbxm`) but isn't required for end users.

## Wire protocol

Same HTTP endpoint shape as the Rust server, plus a `context` query
parameter for routing:

| Endpoint | Method | Purpose |
| --- | --- | --- |
| `/request?context=<placeId>` | GET | Plugin long-polls for commands targeted at this PlaceId (up to 15 s). |
| `/response` | POST | Plugin returns a tool result (body `{id, result, error}`). |
| `/proxy` | POST | Bridge submits a tool call (body `{id, context, tool, params}`). Blocks until the plugin responds. |
| `/status` | GET | List connected plugins. |

JSON field names differ from the archived Rust server's
(`{id, tool, params}` vs `{id, args:{<tool>:{...}}}`), so the plugins
are not cross-compatible. Commands carry a UUID so multiple in-flight
calls can't mix up responses.

## Tools (v0.1)

- `run_code` — execute arbitrary Luau in the Edit DataModel
- `insert_model` — insert a Creator Store model into workspace
- `get_console_output` — read recent LogService lines
- `get_studio_mode` — report Edit / Play / Run / Stopped
- `start_stop_play` — **stub**, Studio lacks a public plugin API for Play toggling
- `run_script_in_play_mode` — **stub**, same reason

Later versions will expand toward a 15+ tool surface (tree, get,
editScript, etc.) and real Play-mode support if Studio's plugin API
permits.

## Security

- Hub binds `127.0.0.1` only. Never exposed to LAN.
- `run_code` executes arbitrary Luau with plugin-level privileges. Only
  use with MCP clients you trust.
- No authentication across localhost. Other processes on your machine
  can already read your files, so the threat model is local.

## Support

If this saves you time juggling multiple Studios, consider sponsoring
development on [GitHub Sponsors](https://github.com/sponsors/Blankscarface23).
The project stays free and MIT either way — sponsorship just helps keep
the roadmap moving.

## License

MIT. Derived in part from
[`Roblox/studio-rust-mcp-server`](https://github.com/Roblox/studio-rust-mcp-server)
(MIT) — specifically the HTTP endpoint paths and the initial tool list.
Plugin and multi-place routing are original work.
