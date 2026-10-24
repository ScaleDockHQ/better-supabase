import { createHash } from "node:crypto";
import { existsSync, realpathSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { basename, dirname, join, resolve } from "node:path";

import type { ResolvedConfig } from "../config/index.ts";

import { loadSnapshot } from "../cli/commands/snapshot.ts";
import { discoverConfig, loadConfig } from "../cli/config.ts";
import { schemaStampPath } from "../cli/content-mapper.ts";
import { configEnvironment, parseEnv } from "../cli/env.ts";
import { mapperFilePath, renderTypesModule } from "../cli/gen/render.ts";
import {
  lastTypesModule,
  typesModuleKey,
  writeAtomic,
} from "../cli/introspect/cache.ts";
import { VERSION } from "../cli/version.ts";

/**
 * The BS codes the mapper reports, on the `.bsb` file or on the tsconfig
 * entry's options. The docs list them on the content mapper page.
 */
export const MAPPER_CODES = {
  /** No config, an invalid one, or no schema and no earlier types. */
  noTypes: 603,
  /** The source failed, so the types are the ones the last `gen` rendered. */
  lastTypes: 604,
  /** A `.bsb` file other than the one `gen` writes for the config. */
  otherFile: 605,
  /** An option the tsconfig entry passes that the mapper doesn't read. */
  unknownOption: 606,
} as const;

/** The options the tsconfig entry may pass in `options`. */
const OPTIONS = new Set(["config"]);

export interface FileDiagnostic {
  readonly messageText: string;
  readonly code: number;
}

export interface OptionDiagnostic {
  readonly path: readonly string[];
  readonly messageText: string;
  readonly code: number;
}

/** What `openProject` resolves for one tsconfig. */
export interface LoadedProject {
  /** The module the mapper serves for the project's `schema.bsb`. */
  readonly text: string;
  /** The absolute path of the `schema.bsb` that `gen` writes, when known. */
  readonly file?: string;
  readonly configIdentity: string;
  readonly watchedFiles: readonly string[];
  readonly diagnostics: readonly FileDiagnostic[];
  readonly optionDiagnostics: readonly OptionDiagnostic[];
}

/** A module that declares nothing, served when there are no types to serve. */
export const EMPTY_MODULE = "export {};\n";

const sha256 = (value: unknown): string =>
  createHash("sha256").update(JSON.stringify(value)).digest("hex");

const message = (error: unknown): string =>
  error instanceof Error ? error.message : String(error);

/**
 * `path` with its symlinks resolved, for `watchedFiles`: tsc watches the real
 * path and ignores a change seen through a link (such as macOS's `/tmp`). A
 * file that doesn't exist yet keeps its name under its nearest real parent.
 */
export function realPath(path: string): string {
  try {
    return realpathSync(path);
  } catch {
    const parent = dirname(path);

    return parent === path ? path : join(realPath(parent), basename(path));
  }
}

function optionDiagnostics(
  options: Readonly<Record<string, unknown>>,
): OptionDiagnostic[] {
  const diagnostics: OptionDiagnostic[] = Object.keys(options)
    .filter((key) => !OPTIONS.has(key))
    .map((key) => ({
      path: [key],
      messageText: `better-supabase reads its settings from its config file; the content mapper only takes "config", the path to that file. Remove "${key}".`,
      code: MAPPER_CODES.unknownOption,
    }));

  if (
    options["config"] !== undefined &&
    typeof options["config"] !== "string"
  ) {
    diagnostics.push({
      path: ["config"],
      messageText:
        '"config" is the path to the better-supabase config file, relative to the tsconfig.',
      code: MAPPER_CODES.unknownOption,
    });
  }

  return diagnostics;
}

/**
 * The files whose change makes tsc open the project again: the config, the
 * saved snapshot, `supabase/config.toml` and the stamp `gen` rewrites when the
 * schema types change.
 */
function watched(config: ResolvedConfig, configFile: string): string[] {
  return [
    configFile,
    ...(config.source.snapshot === undefined
      ? []
      : [resolve(config.root, config.source.snapshot)]),
    join(config.root, "supabase/config.toml"),
    schemaStampPath(config.root, config.output),
  ].map((path) => realPath(path));
}

/** Writes the stamp when it's missing, so tsc watches a file that exists. */
async function ensureStamp(config: ResolvedConfig, key: string): Promise<void> {
  const stamp = schemaStampPath(config.root, config.output);

  if (!existsSync(stamp)) {
    await writeAtomic(stamp, key).catch(() => undefined);
  }
}

/**
 * Loads the project a tsconfig opens: its better-supabase config (found from
 * the tsconfig's folder, or at `options.config`), the schema snapshot through
 * the same caches as `gen`, and the module the mapper serves. It never throws:
 * a failure comes back as a diagnostic on the file, because tsc stops calling a
 * mapper that fails five times in a project.
 */
export async function loadProject(
  configFileName: string,
  options: Readonly<Record<string, unknown>>,
  processEnv: Readonly<Record<string, string | undefined>>,
): Promise<LoadedProject> {
  const projectDir = dirname(configFileName);
  const optionIssues = optionDiagnostics(options);

  const explicit =
    typeof options["config"] === "string"
      ? resolve(projectDir, options["config"])
      : undefined;

  const failed = (
    messageText: string,
    watchedFiles: readonly string[] = [],
  ): LoadedProject => ({
    text: EMPTY_MODULE,
    configIdentity: sha256([VERSION, "failed", messageText, options]),
    watchedFiles,
    diagnostics: [{ messageText, code: MAPPER_CODES.noTypes }],
    optionDiagnostics: optionIssues,
  });

  const configFile = discoverConfig(projectDir, explicit);

  if (configFile === undefined) {
    return failed(
      `No better-supabase config found from ${projectDir}. Run \`better-supabase init\`, or set "config" in the tsconfig's contentMappers options.`,
    );
  }

  let config: ResolvedConfig;
  let env: ReturnType<typeof parseEnv>;

  try {
    env = parseEnv(processEnv);
    config = await loadConfig(
      projectDir,
      explicit,
      configEnvironment(undefined, env),
      configFile,
    );
  } catch (error) {
    return failed(message(error), [realPath(configFile)]);
  }

  const watchedFiles = watched(config, configFile);
  const file = realPath(resolve(config.root, mapperFilePath(config)));
  const configText = await readFile(configFile, "utf-8").catch(() => undefined);

  try {
    const snapshot = await loadSnapshot(config, env, { cache: true });
    const key = typesModuleKey(config, configText, snapshot);
    const text = await renderTypesModule(config, snapshot, configText);
    await ensureStamp(config, key);

    return {
      text,
      file,
      configIdentity: sha256([key, options]),
      watchedFiles,
      diagnostics: [],
      optionDiagnostics: optionIssues,
    };
  } catch (error) {
    const last = await lastTypesModule(config.root, config.output);

    if (last === undefined) {
      return failed(
        `The schema types could not be read: ${message(error)}. Run \`better-supabase gen\` once the source is reachable.`,
        watchedFiles,
      );
    }

    return {
      text: last,
      file,
      configIdentity: sha256([VERSION, "last", sha256(last), options]),
      watchedFiles,
      diagnostics: [
        {
          messageText: `The schema could not be read (${message(error)}), so these are the types the last \`better-supabase gen\` rendered.`,
          code: MAPPER_CODES.lastTypes,
        },
      ],
      optionDiagnostics: optionIssues,
    };
  }
}
