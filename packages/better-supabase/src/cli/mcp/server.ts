/**
 * The dev-time MCP server behind `better-supabase mcp`: each tool runs one
 * CLI command in process with `--json` and returns its result envelope.
 * Tools that write files exist only with `--allow-writes`, and each call
 * needs a consent token the user agreed to (ADR 0047, ADR 0049).
 */

import * as v from "valibot";

import type { Cli } from "../core/run.ts";

import {
  answerLine,
  type ProtocolServer,
  type ToolInfo,
  type ToolResult,
} from "../../mcp/index.ts";
import { consentToken } from "../core/agent.ts";
import { CliError } from "../core/errors.ts";
import { envelope } from "../core/output.ts";
import { VERSION } from "../version.ts";

export interface DevMcpOptions {
  /** Runs one CLI command; its output is captured, never printed. */
  readonly run: Cli["run"];
  /** The project directory every command runs in. */
  readonly cwd: string;
  readonly env: Readonly<Record<string, string | undefined>>;
  /** Adds the tools that write files: `gen`, `sql_sync`, `apply` and `add`. */
  readonly allowWrites?: boolean;
  /** Global flags passed to every command, such as `--config` or `--env`. */
  readonly globals?: readonly string[];
}

interface DevTool {
  readonly info: ToolInfo;
  readonly writes: boolean;
  readonly argv: (input: Input) => readonly string[];
}

type Json = Readonly<Record<string, unknown>>;

const Input = v.object({
  category: v.optional(v.string()),
  block: v.optional(v.string()),
  blocks: v.optional(v.array(v.string())),
  text: v.optional(v.string()),
  preset: v.optional(v.string()),
  allow_breaking: v.optional(v.boolean()),
  confirm: v.optional(v.string()),
});

type Input = v.InferOutput<typeof Input>;

const string = (description: string): Json => ({
  type: "string",
  description,
});

const CONFIRM = string(
  "The consent token from the last call's error, once the user agreed to the change",
);

const schema = (
  properties: Readonly<Record<string, Json>>,
  required: readonly string[] = [],
): Json => ({
  type: "object",
  properties,
  ...(required.length > 0 ? { required } : {}),
  additionalProperties: false,
});

const read = (
  name: string,
  description: string,
  inputSchema: Json,
  argv: DevTool["argv"],
): DevTool => ({
  info: {
    name,
    description,
    inputSchema,
    annotations: { readOnlyHint: true, openWorldHint: false },
  },
  writes: false,
  argv,
});

const write = (
  name: string,
  description: string,
  properties: Readonly<Record<string, Json>>,
  required: readonly string[],
  argv: DevTool["argv"],
): DevTool => ({
  info: {
    name,
    description: `${description} Writes files: the first call returns a consent token; call again with confirm once the user agrees.`,
    inputSchema: schema({ ...properties, confirm: CONFIRM }, required),
    annotations: {
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    },
  },
  writes: true,
  argv,
});

const PRESET = string("A named preset, a code from /create or a Create URL");

const TOOLS: readonly DevTool[] = [
  read(
    "doctor",
    "Checks RLS, indexes, drift, auth config, env files and migration safety, and lists the findings.",
    schema({}),
    () => ["doctor"],
  ),
  read(
    "blocks_list",
    "Lists the blocks the project can add, optionally in one category.",
    schema({ category: string("One block category") }),
    ({ category }) => [
      "blocks",
      "list",
      ...(category === undefined ? [] : ["--category", category]),
    ],
  ),
  read(
    "blocks_view",
    "Shows a block: its tables, the blocks it requires and its options.",
    schema({ block: string("The block's name") }, ["block"]),
    ({ block }) => ["blocks", "view", block ?? ""],
  ),
  read(
    "blocks_search",
    "Finds blocks by name, description or category.",
    schema({ text: string("Words to find") }, ["text"]),
    ({ text }) => ["blocks", "search", ...(text ?? "").split(/\s+/)],
  ),
  read(
    "config",
    "Prints the resolved config with every option and its default, credentials redacted.",
    schema({}),
    () => ["config"],
  ),
  read(
    "preset_info",
    "Shows the config's preset and how the config differs from it.",
    schema({}),
    () => ["preset", "info"],
  ),
  read(
    "sql_list",
    "Lists the SQL modules and which ones the project has.",
    schema({}),
    () => ["sql", "list"],
  ),
  read(
    "gen_check",
    "Reports the generated files that are out of date, writing nothing.",
    schema({}),
    () => ["gen", "--check"],
  ),
  read(
    "apply_dry_run",
    "Shows the config diff and the design changes a preset or Create URL makes, with their severity, writing nothing.",
    schema({ preset: PRESET }, ["preset"]),
    ({ preset }) => ["apply", "--preset", preset ?? "", "--dry-run"],
  ),
  write(
    "gen",
    "Regenerates the typed client and every other generated file.",
    {},
    [],
    () => ["gen"],
  ),
  write(
    "sql_sync",
    "Writes the SQL module files for the blocks the config lists and removes the others.",
    {},
    [],
    () => ["sql", "sync"],
  ),
  write(
    "apply",
    "Applies a preset or Create URL: edits the config and writes the blocks' modules.",
    {
      preset: PRESET,
      allow_breaking: {
        type: "boolean",
        description: "Write breaking app table changes such as a rename",
      },
    },
    ["preset"],
    ({ preset, allow_breaking: allowBreaking }) => [
      "apply",
      "--preset",
      preset ?? "",
      ...(allowBreaking === true ? ["--allow-breaking"] : []),
    ],
  ),
  write(
    "add",
    "Adds blocks with the blocks they require.",
    { blocks: { type: "array", items: { type: "string" }, minItems: 1 } },
    ["blocks"],
    ({ blocks }) => ["add", ...(blocks ?? [])],
  ),
];

const INSTRUCTIONS =
  "Tools for the better-supabase project in this directory. Each returns the CLI's JSON envelope (status, data, error, next). Read with doctor, config, blocks_* and the dry runs first. Tools that write files ask for consent: show the user the error's detail, and call again with confirm set to its token only after they agree.";

function parsedEnvelope(stdout: string): Json | undefined {
  try {
    const value: unknown = JSON.parse(stdout);

    return v.is(v.record(v.string(), v.unknown()), value) ? value : undefined;
  } catch {
    return undefined;
  }
}

function consentResult(
  name: string,
  detail: string,
  token: string,
): ToolResult {
  const error = new CliError(
    "consent_required",
    `${detail}. Ask the user first, then call ${name} again with confirm "${token}".`,
    {
      token,
      next: [
        {
          command: `${name} ${JSON.stringify({ confirm: token })}`,
          when: "after the user agrees",
        },
      ],
    },
  );

  const body = envelope(error.exitCode, {
    error: error.problem,
    next: error.next,
  });

  return {
    content: [{ type: "text", text: JSON.stringify(body) }],
    structuredContent: { ...body },
    isError: true,
  };
}

/** The dev MCP server for one project directory. */
export function createDevMcp(options: DevMcpOptions): ProtocolServer {
  const tools = TOOLS.filter(
    (tool) => options.allowWrites === true || !tool.writes,
  );

  const byName = new Map(tools.map((tool) => [tool.info.name, tool]));
  const globals = options.globals ?? [];

  const callTool = async (
    name: string,
    args: unknown,
  ): Promise<ToolResult | undefined> => {
    const tool = byName.get(name);

    if (!tool) {
      return undefined;
    }

    const parsed = v.safeParse(Input, args ?? {});

    if (!parsed.success) {
      return {
        content: [
          {
            type: "text",
            text: `Invalid arguments: ${parsed.issues.map((issue) => issue.message).join("; ")}`,
          },
        ],
        isError: true,
      };
    }

    const argv = [...tool.argv(parsed.output), ...globals];

    if (tool.writes) {
      const detail = `${name} writes files in ${options.cwd}`;
      const token = consentToken(argv, { effect: "mcp-write", detail });

      if (parsed.output.confirm !== token) {
        return consentResult(name, detail, token);
      }
    }

    const result = await options.run([...argv, "--json", "--agent", "no"], {
      cwd: options.cwd,
      env: options.env,
    });

    const body = parsedEnvelope(result.stdout);
    const diagnostics = result.stderr.trim();

    return {
      content: [
        { type: "text", text: body ? JSON.stringify(body) : result.stdout },
        ...(diagnostics === ""
          ? []
          : [{ type: "text" as const, text: diagnostics }]),
      ],
      ...(body ? { structuredContent: body } : {}),
      ...(result.code === 0 ? {} : { isError: true }),
    };
  };

  return {
    info: { name: "better-supabase", version: VERSION },
    instructions: INSTRUCTIONS,
    listTools: () => Promise.resolve(tools.map((tool) => tool.info)),
    callTool,
  };
}

/** Answers each newline-delimited JSON-RPC message in turn, writing one line per response. */
export async function serveLines(
  lines: AsyncIterable<string>,
  server: ProtocolServer,
  write: (line: string) => void,
): Promise<void> {
  for await (const line of lines) {
    if (line.trim() === "") {
      continue;
    }

    const response = await answerLine(line, server);

    if (response !== undefined) {
      write(`${JSON.stringify(response)}\n`);
    }
  }
}
