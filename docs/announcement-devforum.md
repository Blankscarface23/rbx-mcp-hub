# [Tool] rbx-mcp-hub — Work on multiple Roblox games at once with Claude Code, Cursor, Codex, and other AI agents

<p align="center">
  <img src="https://raw.githubusercontent.com/Blankscarface23/rbx-mcp-hub/master/assets/rbx-mcp-hub.png" alt="rbx-mcp-hub" width="180">
</p>

Hey devs — I built **rbx-mcp-hub** after getting tired of AI tool calls
from one Claude session landing in the wrong Studio whenever I had two
games open at once. Posting it here in case it saves you the same pain.

**Repo:** https://github.com/Blankscarface23/rbx-mcp-hub
**License:** MIT, free and open source.

---

## The problem

Every existing Roblox Studio MCP server — the (now archived) official
`studio-rust-mcp-server`, the built-in MCP server in Studio, and the
community forks — shares **one command queue** across every Studio
window you have open. If you run two Claude / Cursor / Codex sessions
against two different games, a `run_code` from one can execute against
the wrong place. The built-in server added `list_roblox_studios` and
`set_active_studio` as a mitigation, but you have to switch context
before every tool call and it's still one shared queue under the hood.

If you've ever seen an AI-generated `print("hello from Chess")` end up
in your card game's Output window, you know the feeling.

## The fix

rbx-mcp-hub adds **automatic PlaceId-based routing** on top of the same
HTTP protocol. Each project is permanently wired to its own game:

- Each project's `.mcp.json` stamps `RBX_PLACE_ID` onto every outbound
  tool call.
- The Studio plugin registers with `context = tostring(game.PlaceId)`
  when it loads.
- A localhost hub daemon routes commands by context. One Claude session
  = one Studio = zero races, zero per-call switching.

```
Claude A (Chess project)   ──►  bridge (RBX_PLACE_ID=1234) ──►┐
Claude B (Card Game proj.) ──►  bridge (RBX_PLACE_ID=5678) ──►│
                                                              ▼
                                                    ┌─────────────┐
                                                    │ Hub :44755  │
                                                    └──┬──────┬───┘
                                                       ▼      ▼
                                                 Studio 1234  Studio 5678
```

## Features

- **Works with any MCP-speaking client** — Claude Code, Cursor, Codex,
  Cline, Continue. The bridge is a generic stdio MCP server.
- **PlaceId routing is automatic per project** — set `RBX_PLACE_ID`
  once in `.mcp.json` and never call `set_active_studio` again.
- **Plugin auto-reconnects** when you publish an unpublished place
  (the PlaceId changes 0 → real, and the plugin re-registers without
  a reload).
- **Toolbar button** shows live connection state and click-toggles
  pause/resume.
- **Six v0.1 tools** matching the archived Rust server: `run_code`,
  `insert_model`, `get_console_output`, `get_studio_mode`, plus stubs
  for `start_stop_play` and `run_script_in_play_mode` (Studio doesn't
  expose a public plugin API for Play toggling — tracking for v0.2).

## Install

```bash
npm install -g rbx-mcp-hub
rbx-mcp-hub install-plugin
rbx-mcp-hub start
```

Then, inside each of your game project folders:

```bash
rbx-mcp-hub init
```

Full guide + troubleshooting table in the README.

## How it compares

| Tool | Price | Multi-place? | Notes |
|---|---|---|---|
| **rbx-mcp-hub** | Free, MIT | ✅ per-project auto-routing | Narrow, surgical fix |
| Roblox built-in Studio MCP | Free | ⚠️ manual `set_active_studio` per call | Good for single user, 1–2 Studios |
| studio-rust-mcp-server (official) | Free, MIT | ❌ single queue | Archived Apr 2026 |
| boshyxd/robloxstudio-mcp | Free, MIT | ❌ single queue | 50+ tools, different focus |
| WEPPY Pro | Paid | ✅ (Pro tier only) | Bundles with terrain, audio, bulk ops |

Pick rbx-mcp-hub if you want a free, zero-config-per-call way to run
multiple AI agents against multiple Studios at the same time.

## Feedback welcome

Issues / PRs on GitHub. Feature requests especially welcome — v0.2 is
likely to expand the tool surface and take another crack at the Play
mode tools.

If it saves you time, [GitHub Sponsors](https://github.com/sponsors/Blankscarface23)
is set up. Stays free and MIT either way.
