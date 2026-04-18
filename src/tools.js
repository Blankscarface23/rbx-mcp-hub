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
      "Insert a model from the Creator Store into the target Studio session's workspace. Provide either `query` (free-form marketplace search via InsertService:GetFreeModels; top match is inserted) or `assetId` (direct Creator Store id). Model roots are pivoted to the point under the Studio camera's viewport center so the model lands where the user is looking.",
    inputSchema: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description:
            "Free-form marketplace search query. The top InsertService:GetFreeModels result is inserted. Mutually exclusive with assetId.",
        },
        assetId: {
          type: ["string", "number"],
          description:
            "Creator Store asset id. Mutually exclusive with query.",
        },
      },
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
      "Start Play mode, run the provided script, capture results, then stop. One-shot test runner.",
    inputSchema: {
      type: "object",
      properties: {
        code: { type: "string", description: "Luau to execute during playtest." },
        side: {
          type: "string",
          enum: ["client", "server"],
          default: "server",
        },
        timeoutSeconds: { type: "number", default: 10 },
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
