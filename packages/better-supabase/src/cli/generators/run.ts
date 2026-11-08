import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { availableParallelism } from "node:os";
import { isAbsolute, relative, resolve } from "node:path";

import type {
  GeneratedFile,
  Generator,
  GeneratorCapability,
  GeneratorInput,
} from "../../config/index.ts";

import { cacheEnabled } from "../cache/store.ts";
import { CliError, errorText } from "../core/errors.ts";
import { CACHE_DIR, writeAtomic } from "../introspect/cache.ts";
import { VERSION } from "../version.ts";

const sha256 = (text: string): string =>
  createHash("sha256").update(text).digest("hex");

/** One generated file, with the generator that wrote it. */
export interface GeneratorFile {
  readonly file: GeneratedFile;
  readonly generator: string;
}

export interface GeneratorRun {
  readonly files: readonly GeneratorFile[];
  /** The file of the generator that provides each capability. */
  readonly capabilities: ReadonlyMap<GeneratorCapability, string>;
  /** The generators whose files came from the cache. */
  readonly cached: readonly string[];
}

function isFile(item: unknown): item is GeneratedFile {
  return (
    typeof item === "object" &&
    item !== null &&
    "path" in item &&
    typeof item.path === "string" &&
    "contents" in item &&
    typeof item.contents === "string"
  );
}

function isFiles(value: unknown): value is GeneratedFile[] {
  return Array.isArray(value) && value.every((item: unknown) => isFile(item));
}

/**
 * The cache key of one generator: its name, version and options, the CLI
 * version and the input it reads. Everything the input holds is plain data, so
 * the hash covers every read; a closure in the config file would not be.
 */
export function generatorKey(
  generator: Generator,
  input: GeneratorInput,
): string {
  return sha256(
    JSON.stringify([
      generator.name,
      generator.version,
      generator.options ?? null,
      VERSION,
      sha256(JSON.stringify(input)),
    ]),
  );
}

const cacheFile = (root: string, generator: Generator): string =>
  resolve(
    root,
    CACHE_DIR,
    "generators",
    `${sha256(generator.name).slice(0, 16)}.json`,
  );

async function readCached(
  root: string,
  generator: Generator,
  key: string,
): Promise<GeneratedFile[] | undefined> {
  const entry: unknown = await readFile(cacheFile(root, generator), "utf-8")
    .then((text): unknown => JSON.parse(text))
    .catch(() => undefined);

  return typeof entry === "object" &&
    entry !== null &&
    "key" in entry &&
    entry.key === key &&
    "files" in entry &&
    isFiles(entry.files)
    ? entry.files
    : undefined;
}

/**
 * A generator that can run on a worker thread: it says `workerSafe` and names
 * the module that builds it.
 */
const onWorker = (generator: Generator): boolean =>
  generator.workerSafe === true && generator.module !== undefined;

/**
 * Fewer uncached jobs than this run on the main thread, since starting a worker
 * costs more than one generator saves.
 */
const MIN_WORKER_JOBS = 2;

/**
 * Tables below which every generator runs on the main thread. Measured with the
 * six built-in generators: at 380 tables they take 33 to 49 ms together and a
 * pool of four workers 56 to 85 ms; at 1900 tables 134 ms against 120 ms. The
 * pool only pays for a schema larger than the ones apps have today.
 */
const WORKER_MIN_TABLES = 1500;

/** The most workers a run starts, so a many-core machine stays responsive. */
const MAX_WORKERS = 4;

/** Where the worker module sits next to this one: built, or loaded from source. */
function workerUrl(): URL {
  return import.meta.url.endsWith(".ts")
    ? new URL("worker.ts", import.meta.url)
    : new URL("generator-worker.js", import.meta.url);
}

/** Options of a run, for the pool and for tests. */
export interface RunGeneratorsOptions {
  readonly root: string;
  /** Project-relative paths `gen` already writes, to refuse a clash. */
  readonly taken: ReadonlySet<string>;
  /**
   * Worker threads for the generators that declare `workerSafe` and a `module`:
   * `0` keeps everything on the main thread. Defaults to the machine's cores
   * less one, up to four, once the schema has `workerMinTables` tables.
   */
  readonly workers?: number;
  /**
   * The table count from which workers are used (default 1500). Below it every
   * generator runs on the main thread.
   */
  readonly workerMinTables?: number;
  /** The worker module, for tests that load it from source. */
  readonly workerModule?: URL;
  readonly execArgv?: readonly string[];
}

const defaultWorkers = (): number =>
  Math.min(MAX_WORKERS, Math.max(0, availableParallelism() - 1));

const failure = (generator: Generator, cause: unknown): CliError =>
  new CliError(
    "generator_failed",
    `generator "${generator.name}" failed: ${errorText(cause)}`,
    { cause },
  );

/**
 * Generates the files of `pending` on worker threads, in order. A generator's
 * own error is returned in place; a pool that cannot run (a worker fails to
 * start or dies) returns `undefined`, and the caller generates on the main
 * thread, so a missing worker costs time, never a result.
 */
async function generateOnWorkers(
  pending: readonly Generator[],
  input: GeneratorInput,
  options: RunGeneratorsOptions,
): Promise<readonly (GeneratedFile[] | CliError)[] | undefined> {
  const size = options.workers ?? defaultWorkers();

  if (
    size < 1 ||
    pending.length < MIN_WORKER_JOBS ||
    Object.keys(input.meta.tables).length <
      (options.workerMinTables ?? WORKER_MIN_TABLES)
  ) {
    return undefined;
  }

  // Lazy: only a run with several uncached generators needs the pool, and `node:worker_threads` stays out of the CLI's startup path.
  const { runInWorkers } = await import("./pool.ts");

  try {
    const outcomes = await runInWorkers(
      pending.map((generator, id) => ({
        id,
        name: generator.name,
        version: generator.version,
        // SAFETY: `pending` holds only generators that `onWorker` accepted.
        module: generator.module!,
        options: generator.options,
      })),
      input,
      {
        size,
        worker: options.workerModule ?? workerUrl(),
        ...(options.execArgv === undefined
          ? {}
          : { execArgv: options.execArgv }),
      },
    );

    return outcomes.map((outcome, index) =>
      outcome.ok
        ? outcome.files
        : failure(pending[index]!, new Error(outcome.error)),
    );
  } catch {
    return undefined;
  }
}

/**
 * Runs the configured generators in order. A `pure` generator's files are
 * cached under `node_modules/.cache/better-supabase/generators` on its key; any
 * other generator runs on every pass. The generators that are not cached and
 * declare `workerSafe` and a `module` run on worker threads (two or more of
 * them, for a schema of 1500 tables or more), the rest on the main thread, and
 * the files are merged in config order, so the output is the one a single
 * thread gives. Paths must stay inside the project and stay unique, and two
 * generators may not provide one capability.
 */
export async function runGenerators(
  generators: readonly Generator[],
  input: GeneratorInput,
  options: RunGeneratorsOptions,
): Promise<GeneratorRun> {
  const owners = new Map<string, string>(
    [...options.taken].map((path) => [resolve(options.root, path), "gen"]),
  );

  const capabilities = new Map<GeneratorCapability, string>();
  const files: GeneratorFile[] = [];
  const cached: string[] = [];

  const keys: string[] = [];
  const produced: (GeneratedFile[] | undefined)[] = [];

  for (const generator of generators) {
    for (const capability of generator.provides ?? []) {
      const owner = capabilities.get(capability);

      if (owner !== undefined) {
        throw new CliError(
          "generator_failed",
          `generators "${owner}" and "${generator.name}" both provide "${capability}"; configure one of them`,
        );
      }

      capabilities.set(capability, generator.name);
    }

    const useCache = generator.pure === true && cacheEnabled();
    const key = useCache ? generatorKey(generator, input) : "";
    keys.push(key);

    const hit = useCache
      ? await readCached(options.root, generator, key)
      : undefined;

    produced.push(hit);

    if (hit !== undefined) {
      cached.push(generator.name);
    }
  }

  const missing = produced.flatMap((made, index) =>
    made === undefined ? [index] : [],
  );

  const offloaded = missing.filter((index) => onWorker(generators[index]!));

  const fromWorkers = await generateOnWorkers(
    offloaded.map((index) => generators[index]!),
    input,
    options,
  );

  const errors = new Map<number, CliError>();

  for (const [position, index] of offloaded.entries()) {
    const outcome = fromWorkers?.[position];

    if (outcome instanceof CliError) {
      errors.set(index, outcome);
    } else if (outcome !== undefined) {
      produced[index] = outcome;
    }
  }

  for (const index of missing) {
    const generator = generators[index]!;

    if (produced[index] !== undefined || errors.has(index)) {
      continue;
    }

    try {
      produced[index] = [...(await generator.generate(input))];
    } catch (cause) {
      errors.set(index, failure(generator, cause));
    }
  }

  for (const [index, generator] of generators.entries()) {
    // The first failing generator in config order is the one reported.
    const error = errors.get(index);

    if (error !== undefined) {
      throw error;
    }

    const made = produced[index]!;

    if (missing.includes(index) && generator.pure === true && cacheEnabled()) {
      await writeAtomic(
        cacheFile(options.root, generator),
        JSON.stringify({ key: keys[index], files: made }),
      ).catch(() => undefined);
    }

    for (const file of made) {
      const path = resolve(options.root, file.path);
      const inside = relative(options.root, path);

      if (inside === "" || inside.startsWith("..") || isAbsolute(inside)) {
        throw new CliError(
          "generator_failed",
          `generator "${generator.name}" wrote ${file.path}, which is outside the project root`,
        );
      }

      const owner = owners.get(path);

      if (owner !== undefined) {
        throw new CliError(
          "generator_failed",
          `generator "${generator.name}" wrote ${file.path}, which ${owner === "gen" ? "better-supabase gen writes" : `generator "${owner}" also writes`}`,
        );
      }

      owners.set(path, generator.name);
      files.push({ file, generator: generator.name });
    }
  }

  return { files, capabilities, cached };
}
