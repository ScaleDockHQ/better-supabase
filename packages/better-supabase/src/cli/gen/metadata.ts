import { readFile } from "node:fs/promises";
import { basename, join, relative, resolve, sep } from "node:path";

import type { Generator, ResolvedConfig } from "../../config/index.ts";
import type { CliIo, CommandResult } from "../core/io.ts";
import type { CliEnv } from "../env.ts";
import type { Snapshot } from "../introspect/types.ts";
import type { Paint } from "../style.ts";

import {
  jsonSchema,
  standardSchema,
  valibot,
  zod,
} from "../../config/index.ts";
import { CliError, errorText } from "../core/errors.ts";
import { readStdin } from "../core/io.ts";
import { fromMetadata } from "../introspect/from-metadata.ts";
import {
  MetadataRejectedError,
  parseMetadataDocument,
} from "../introspect/typegen.ts";
import { metaPaths } from "./emit.ts";
import { generationNotices, UNFORMATTED } from "./notices.ts";
import { type Rendered, render } from "./render.ts";
import { refuseRowConditionedBuckets, runGen } from "./run.ts";

/** The files `gen --metadata` can write to stdout. */
export const EMITS = [
  "schema",
  "types",
  "zod",
  "valibot",
  "json-schema",
  "standard-schema",
] as const;

type Emit = (typeof EMITS)[number];

const isEmit = (value: string): value is Emit =>
  EMITS.some((emit) => emit === value);

/** The configured generator for an `--emit` target, or one with its defaults. */
function emitGenerator(
  config: ResolvedConfig,
  emit: Emit,
): Generator | undefined {
  const configured = config.generators.find(
    (generator) => generator.name === emit,
  );

  switch (emit) {
    case "schema":
    case "types": {
      return undefined;
    }

    case "zod": {
      return configured ?? zod();
    }

    case "valibot": {
      return configured ?? valibot();
    }

    case "json-schema": {
      return configured ?? jsonSchema();
    }

    case "standard-schema": {
      return configured ?? standardSchema();
    }

    default: {
      const unhandled: never = emit;
      throw new Error(`unknown --emit ${String(unhandled)}`);
    }
  }
}

/**
 * The one file `gen --metadata` prints: the `defineSchema` module with its
 * metadata inlined, `database.types.ts`, or one generator's output.
 */
async function renderEmit(
  config: ResolvedConfig,
  snapshot: Snapshot,
  emit: Emit,
): Promise<Rendered & { readonly contents: string }> {
  const generator = emitGenerator(config, emit);

  const { files, warnings } = await render(
    { ...config, generators: generator ? [generator] : [] },
    snapshot,
    { inlineMeta: emit === "schema" },
  );

  const path =
    emit === "schema"
      ? config.output
      : emit === "types"
        ? config.databaseTypesOutput
        : undefined;

  const own = new Set([
    config.databaseTypesOutput,
    config.output,
    ...Object.values(metaPaths(config.output)),
  ]);

  const picked =
    path === undefined
      ? files.filter((file) => !own.has(file.path))
      : files.filter((file) => file.path === path);

  const [file] = picked;

  if (!file || picked.length > 1) {
    throw new CliError(
      "usage",
      `--emit ${emit} expects one file, and the generator wrote ${picked.length}. Pass --out <dir> to write them all.`,
    );
  }

  return { files: picked, warnings, contents: file.contents };
}

/**
 * Reads `--metadata <path|->` (a file relative to `cwd`, or stdin for `-`)
 * into a snapshot. Throws `MetadataRejectedError` for a document that can't
 * be read or that `parseMetadataDocument` refuses.
 */
export async function readMetadataSnapshot(
  source: string,
  cwd: string,
  io: CliIo,
): Promise<Snapshot> {
  if (source === "-") {
    const piped = await readStdin(io, "--metadata -");

    return fromMetadata(await parseMetadataDocument(piped));
  }

  let text: string;

  try {
    text = await readFile(resolve(cwd, source), "utf-8");
  } catch (cause) {
    throw new MetadataRejectedError(
      `Could not read ${source}: ${errorText(cause)}`,
    );
  }

  return fromMetadata(await parseMetadataDocument(text));
}

export interface MetadataGenOptions {
  readonly config: ResolvedConfig;
  readonly env: CliEnv;
  readonly cwd: string;
  readonly io: CliIo;
  /** `--metadata`: a path, or `-` for stdin. */
  readonly metadata: string;
  readonly emit?: string;
  readonly out?: string;
  readonly check: boolean;
  readonly json: boolean;
  readonly paint?: Paint;
}

/** Exit code for a document `gen --metadata` refuses (`EX_DATAERR`), as Dart's `supabase_typegen` uses. */
export const METADATA_REJECTED = 65;

/**
 * `gen --metadata`: the out-of-process generator contract of
 * `@supabase/typegen`. Without `--out` it prints one file on stdout and
 * everything else on stderr; with `--out` it writes the usual files there.
 */
export async function runMetadataGen(
  options: MetadataGenOptions,
): Promise<CommandResult> {
  const { config, io } = options;
  const emit = options.emit ?? "schema";

  if (!isEmit(emit)) {
    return {
      code: 2,
      error: `--emit must be one of ${EMITS.join(", ")}, got "${emit}"`,
    };
  }

  if (options.out !== undefined && options.emit !== undefined) {
    return {
      code: 2,
      error:
        "--emit picks the one file gen prints; --out writes them all. Pass one of them.",
    };
  }

  if (options.out === undefined && options.check) {
    return { code: 2, error: "--check with --metadata needs --out <dir>" };
  }

  if (options.out === undefined && options.json) {
    return {
      code: 2,
      error:
        "--metadata prints the generated code on stdout, so --json has nothing to print. Pass --out <dir> for the JSON summary.",
    };
  }

  let snapshot: Snapshot;

  try {
    snapshot = await readMetadataSnapshot(options.metadata, options.cwd, io);
  } catch (cause) {
    if (cause instanceof MetadataRejectedError) {
      return { code: METADATA_REJECTED, error: cause.message };
    }

    throw cause;
  }

  if (options.out !== undefined) {
    const dir = relative(config.root, resolve(options.cwd, options.out));

    const into = (path: string): string =>
      join(dir, basename(path)).split(sep).join("/");

    return runGen({
      config: {
        ...config,
        output: into(config.output),
        databaseTypesOutput: into(config.databaseTypesOutput),
      },
      env: options.env,
      check: options.check,
      snapshot,
      isolated: true,
      ...(options.paint ? { paint: options.paint } : {}),
    });
  }

  const refused = refuseRowConditionedBuckets(config);

  if (refused) {
    return refused;
  }

  const { contents, warnings } = await renderEmit(config, snapshot, emit);
  io.stdout(contents);
  const notices = await generationNotices(snapshot, warnings);

  const shown =
    emit === "types" ? notices : notices.filter((line) => line !== UNFORMATTED);

  for (const line of shown) {
    io.stderr(`${line}\n`);
  }

  return { code: 0 };
}
