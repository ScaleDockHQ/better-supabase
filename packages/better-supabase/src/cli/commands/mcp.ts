import { createInterface } from "node:readline";

import type { AnyCommand } from "../core/command.ts";

import { defineCliCommand } from "../core/command.ts";
import { commandMeta } from "../core/manifest.ts";
import { run } from "../core/run.ts";
import { PROCESS_ENV } from "../env.ts";
import { createDevMcp, serveLines } from "../mcp/server.ts";

const MCP_ARGS = {
  "allow-writes": {
    type: "boolean",
    description:
      "Add the tools that write files (gen, sql_sync, apply, add); each call still needs the user's consent token",
  },
} as const;

export const mcpCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("mcp"),
  args: MCP_ARGS,
  runsWithInvalidConfig: true,
  run: async (args, { cwd, configFile, config, env, io, log }) => {
    const server = createDevMcp({
      run,
      cwd,
      env: env[PROCESS_ENV] ?? {},
      allowWrites: args["allow-writes"] === true,
      globals: [
        ...(configFile ? ["--config", configFile] : []),
        ...(config.environment ? ["--env", config.environment] : []),
      ],
    });

    log.info(
      `better-supabase MCP server on stdio for ${cwd}${args["allow-writes"] === true ? " (writes allowed with consent)" : " (read-only)"}`,
    );

    const lines = createInterface({
      input: process.stdin,
      crlfDelay: Infinity,
    });

    await serveLines(lines, server, io.stdout);

    return { code: 0, streamed: true };
  },
});
