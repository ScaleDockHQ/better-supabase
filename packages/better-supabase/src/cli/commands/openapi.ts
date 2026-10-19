import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";

import { importExport } from "../config.ts";
import { defineCliCommand } from "../core/command.ts";
import { CliError } from "../core/errors.ts";
import {
  applyPlan,
  type FilePlan,
  insideRoot,
  PLAN_ARGS,
  planResult,
} from "../core/files.ts";
import { display } from "../core/io.ts";
import { commandMeta } from "../core/manifest.ts";

const ARGS = {
  action: {
    type: "positional",
    required: false,
    description: "emit",
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

export type OpenApiArgs = CliArgs<
  typeof ARGS & Pick<typeof PLAN_ARGS, "check" | "dry-run">
>;

export async function runOpenApi(
  config: ResolvedConfig,
  args: OpenApiArgs,
): Promise<CommandResult> {
  const [action] = args._;

  if (action !== "emit") {
    throw new CliError(
      "usage",
      `${action ? `Unknown openapi action "${action}"` : "Name an action"}. Run \`better-supabase openapi emit\`.`,
    );
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
      errorCode: "invalid_input",
      error: `${display(config.root, entry)} must export an OpenAPI document (createOpenApi(...)) as \`openapi\` or default.`,
    };
  }

  const contents = `${JSON.stringify(document, null, 2)}\n`;

  const plan: FilePlan = {
    root: config.root,
    regenerate: "better-supabase openapi emit",
    files: [{ path: insideRoot(config.root, out, "--out"), contents }],
  };

  return planResult(plan, await applyPlan(plan, args));
}

export const openapiCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("openapi"),
  args: { ...ARGS, check: PLAN_ARGS.check, "dry-run": PLAN_ARGS["dry-run"] },
  run: (args, { config }) => runOpenApi(config, args),
});
