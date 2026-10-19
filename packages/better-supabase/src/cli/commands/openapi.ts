import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";

import { importExport } from "../config.ts";
import { defineCliCommand } from "../core/command.ts";
import { fileState, staleResult, writeLine } from "../core/files.ts";
import { display } from "../core/io.ts";
import { commandMeta } from "../core/manifest.ts";

const ARGS = {
  action: {
    type: "positional",
    required: false,
    description: "emit",
  },
  check: {
    type: "boolean",
    description: "Fail when the file differs from the document",
  },
  entry: {
    type: "string",
    description:
      "Defaults to openapi.entry. Exports `openapi` or default: a document or a function returning one",
    valueHint: "file",
  },
  out: {
    type: "string",
    description: "Defaults to openapi.output",
    valueHint: "file",
  },
} as const;

export type OpenApiArgs = CliArgs<typeof ARGS>;

export async function runOpenApi(
  config: ResolvedConfig,
  args: OpenApiArgs,
): Promise<CommandResult> {
  const [action] = args._;

  if (action !== "emit") {
    return {
      code: 2,
      error: `${action ? `Unknown openapi action "${action}"` : "Name an action"}. Run \`better-supabase openapi emit\`.`,
    };
  }

  const entry = args.entry ?? config.openapi.entry;
  const out = args.out ?? config.openapi.output;
  const exported = await importExport(resolve(config.root, entry), "openapi");

  // SAFETY: an exported openapi function takes no arguments and returns the document.
  const document: unknown =
    typeof exported === "function"
      ? await (exported as () => unknown)()
      : exported;

  if (
    typeof document !== "object" ||
    document === null ||
    !("openapi" in document)
  ) {
    return {
      code: 1,
      error: `${display(config.root, entry)} must export an OpenAPI document (createOpenApi(...)) as \`openapi\` or default.`,
    };
  }

  const contents = `${JSON.stringify(document, null, 2)}\n`;
  const state = await fileState(config.root, out, contents);

  if (args.check === true) {
    return staleResult(state, "better-supabase openapi emit");
  }

  const { line } = await writeLine(state.path, contents, state.file);

  return { code: 0, output: line };
}

export const openapiCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("openapi"),
  args: ARGS,
  run: (args, { config }) => runOpenApi(config, args),
});
