import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
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
 * Runs the configured generators in order. A `pure` generator's files are
 * cached under `node_modules/.cache/better-supabase/generators` on its key; any
 * other generator runs on every pass. Paths must stay inside the project and
 * stay unique, and two generators may not provide one capability.
 */
export async function runGenerators(
  generators: readonly Generator[],
  input: GeneratorInput,
  options: {
    readonly root: string;
    /** Project-relative paths `gen` already writes, to refuse a clash. */
    readonly taken: ReadonlySet<string>;
  },
): Promise<GeneratorRun> {
  const owners = new Map<string, string>(
    [...options.taken].map((path) => [resolve(options.root, path), "gen"]),
  );

  const capabilities = new Map<GeneratorCapability, string>();
  const files: GeneratorFile[] = [];
  const cached: string[] = [];

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

    let produced = useCache
      ? await readCached(options.root, generator, key)
      : undefined;

    if (produced === undefined) {
      try {
        produced = [...(await generator.generate(input))];
      } catch (cause) {
        throw new CliError(
          "generator_failed",
          `generator "${generator.name}" failed: ${errorText(cause)}`,
          { cause },
        );
      }

      if (useCache) {
        await writeAtomic(
          cacheFile(options.root, generator),
          JSON.stringify({ key, files: produced }),
        ).catch(() => undefined);
      }
    } else {
      cached.push(generator.name);
    }

    for (const file of produced) {
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
