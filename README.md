# rbx-mcp-hub

Multi-place MCP hub for Roblox Studio. Work on multiple Roblox games at the same time with Claude Code, Cursor, or any MCP-speaking AI — each AI session routed to the correct Studio window by PlaceId.

## Why this exists

Every Roblox Studio MCP server today (the official archived `studio-rust-mcp-server`, the built-in `StudioMCP.exe`, community forks) binds to a single localhost port and runs a single shared command queue. Open two Studio windows, and a `run_code` from one Claude session can race into the other Studio and execute against the wrong game. Open four, and the MCP becomes unusable.

`rbx-mcp-hub` fixes this by adding **PlaceId-based routing** on top of the Rust server's wire protocol.

- Studio plugin registers with `context = tostring(game.PlaceId)` on connect.
- MCP bridge (one per Claude session) reads `RBX_PLACE_ID` from its env and stamps it onto every outbound tool call.
- Hub daemon routes commands to the matching plugin — no more races.

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

## Quick start

```bash
# 1. Install the Node side
npm install -g rbx-mcp-hub

# 2. Install the Studio plugin (one time — copies the shipped .rbxm to
#    %LocalAppData%\Roblox\Plugins on Windows)
rbx-mcp-hub install-plugin

# 3. In each Roblox project directory, set up the per-project .mcp.json
cd /path/to/my-game
rbx-mcp-hub init

# 4. Start the hub (once, globally — runs until you stop it)
rbx-mcp-hub start

# 5. Open Studio → open your place → plugin auto-connects
# 6. Open Claude Code in that project → bridge auto-connects
# 7. Repeat steps 5-6 for as many projects as you want
```

The plugin binary lives at `plugin/build/rbx-mcp-hub.rbxm` and is committed
to the repo, so you can also skip npm entirely: download the .rbxm, drop it
into your Plugins folder, then run the hub and bridge directly with Node.

## Rebuilding the plugin (contributors only)

Plugin source is under `plugin/src/`. Studio's built-in Script Sync works
fine for iterating: open a blank place, enable Script Sync against
`plugin/src/`, then use **Save as Local Plugin** to rebuild the .rbxm.
Rojo also works if you prefer (`rojo build plugin/default.project.json
-o plugin/build/rbx-mcp-hub.rbxm`) but is not required.

## Wire protocol

The hub speaks the Rust MCP server's HTTP protocol with one added dimension: a `context` query parameter.

| Endpoint | Method | Purpose |
| --- | --- | --- |
| `/request?context=<placeId>` | GET | Plugin long-polls for commands targeted at this PlaceId (up to 15s). |
| `/response` | POST | Plugin returns a tool result (body includes `{id, result, error}`). |
| `/proxy` | POST | Bridge submits a tool call (body includes `{id, context, tool, params}`). Blocks until the plugin responds. |
| `/status` | GET | List connected plugins and their registered PlaceIds. |

Commands carry a UUID so multiple in-flight calls can't mix up responses.

## Tools

v0.1 ships the Rust server's original tool surface:

- `run_code` — execute arbitrary Luau in the Studio DataModel
- `insert_model` — insert a Creator Store model into workspace
- `get_console_output` — read recent output log lines
- `start_stop_play` — toggle play / run server mode
- `run_script_in_play_mode` — run a script during a playtest then exit
- `get_studio_mode` — query current mode

Later versions will expand toward the full 17-tool surface that Vltja/Roblox-MCP exposes (tree, get, editScript, etc.).

## Security

- Hub binds to `127.0.0.1` only. Never exposed to LAN.
- `run_code` and other mutating tools can be disabled per-plugin via the plugin's toolbar UI.
- No authentication across localhost; other local processes could already read your files.

## License

MIT. Derived in part from [`Roblox/studio-rust-mcp-server`](https://github.com/Roblox/studio-rust-mcp-server) (MIT) — specifically the HTTP endpoint shape and the initial tool list. Plugin and multi-place routing are original work.
