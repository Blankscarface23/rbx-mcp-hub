export const TOOL_DEFINITIONS = [
  {
    name: "run_code",
    description:
      "Execute arbitrary Luau code inside the target Roblox Studio session's Edit DataModel. Returns whatever the snippet returns (stringified) or prints.",
    inputSchema: {
      type: "object",
      properties: {
        code: {
          type: "string",
          description: "Luau source to execute. Avoid long-running loops.",
        },
      },
      required: ["code"],
    },
  },
  {
    name: "insert_model",
    description:
      "Insert a model from the Roblox Creator Store into the target Studio session's workspace by asset id.",
    inputSchema: {
      type: "object",
      properties: {
        assetId: {
          type: ["string", "number"],
          description: "Creator Store asset id.",
        },
      },
      required: ["assetId"],
    },
  },
  {
    name: "get_console_output",
    description:
      "Return recent LogService output from the target Studio session. Default last 200 lines.",
    inputSchema: {
      type: "object",
      properties: {
        lines: {
          type: "number",
          description: "How many of the most recent lines to return.",
          default: 200,
        },
      },
    },
  },
  {
    name: "start_stop_play",
    description:
      "Start or stop a play / run-server session in the target Studio window.",
    inputSchema: {
      type: "object",
      properties: {
        mode: {
          type: "string",
          enum: ["play", "run", "stop"],
          description:
            "'play' = Play Solo, 'run' = Run (server only), 'stop' = stop the current session.",
        },
      },
      required: ["mode"],
    },
  },
  {
    name: "run_script_in_play_mode",
    description:
      "Start Play or Run mode, inject the provided Luau as a Script into ServerScriptService, pcall it, capture logs + return value, stop, and return the structured result. One-shot test runner.",
    inputSchema: {
      type: "object",
      properties: {
        code: { type: "string", description: "Luau to execute during the session." },
        mode: {
          type: "string",
          enum: ["play", "run"],
          default: "play",
          description:
            "'play' = StudioTestService:ExecutePlayModeAsync (Play Solo, client + server + character). 'run' = ExecuteRunModeAsync (server-only, no character spawning).",
        },
        side: {
          type: "string",
          enum: ["client", "server"],
          default: "server",
          description: "Only 'server' is implemented; client-side injection is a TODO.",
        },
        timeoutSeconds: {
          type: "number",
          default: 10,
          description:
            "How long the injected runner waits for your code before force-ending the test. Note: the hub's per-command timeout is 60s, so values above ~50s will be cut off by the bridge.",
        },
      },
      required: ["code"],
    },
  },
  {
    name: "get_studio_mode",
    description:
      "Report the current mode of the target Studio session: 'edit', 'play', 'run', or 'stopped'.",
    inputSchema: { type: "object", properties: {} },
  },
];
