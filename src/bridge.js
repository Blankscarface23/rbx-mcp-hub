#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { randomUUID } from "node:crypto";
import { TOOL_DEFINITIONS } from "./tools.js";

const HUB_PORT = Number(process.env.RBX_MCP_HUB_PORT) || 44755;
const HUB_HOST = process.env.RBX_MCP_HUB_HOST || "127.0.0.1";
const PLACE_ID = process.env.RBX_PLACE_ID || "";
const PLACE_NAME = process.env.RBX_PLACE_NAME || "";

function log(...args) {
  process.stderr.write(`[bridge] ${args.join(" ")}\n`);
}

if (!PLACE_ID) {
  log("warning: RBX_PLACE_ID is empty. Tool calls will fail until set.");
  log("run `rbx-mcp-hub init` inside your project to configure .mcp.json");
}

async function forwardToHub(tool, args) {
  const id = randomUUID();
  const body = JSON.stringify({
    id,
    context: PLACE_ID,
    tool,
    params: args ?? {},
  });

  const res = await fetch(`http://${HUB_HOST}:${HUB_PORT}/proxy`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body,
  }).catch((e) => {
    throw new Error(
      `hub unreachable at ${HUB_HOST}:${HUB_PORT} (${e.message}). ` +
      `Start it with: rbx-mcp-hub start`,
    );
  });

  const text = await res.text();
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error(`hub returned non-JSON: ${text.slice(0, 200)}`);
  }
  if (!res.ok) {
    throw new Error(parsed.error || `hub error HTTP ${res.status}`);
  }
  if (parsed.error) {
    throw new Error(parsed.error);
  }
  return parsed.result;
}

const server = new Server(
  {
    name: "rbx-mcp-hub",
    version: "0.1.0",
  },
  {
    capabilities: {
      tools: {},
    },
  },
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: TOOL_DEFINITIONS,
}));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  const { name, arguments: args } = req.params;

  if (!PLACE_ID) {
    return {
      isError: true,
      content: [
        {
          type: "text",
          text:
            "RBX_PLACE_ID is not set for this MCP bridge. " +
            "Run `rbx-mcp-hub init` in the project directory " +
            "or set `env.RBX_PLACE_ID` in its .mcp.json.",
        },
      ],
    };
  }

  try {
    const result = await forwardToHub(name, args);
    const text =
      typeof result === "string"
        ? result
        : JSON.stringify(result, null, 2);
    return {
      content: [{ type: "text", text }],
    };
  } catch (e) {
    return {
      isError: true,
      content: [{ type: "text", text: e.message || String(e) }],
    };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
log(`bridge running (place=${PLACE_ID || "unset"} name=${PLACE_NAME || "-"})`);
