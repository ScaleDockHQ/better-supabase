import {
  glob,
  mkdtemp,
  readdir,
  readFile,
  rm,
  symlink,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import {
  basename,
  extname,
  isAbsolute,
  join,
  relative,
  resolve,
} from "node:path";

import type { SupabaseConfig, TomlTable } from "../supabase-config.ts";
import type { BaselineContext } from "./stack.ts";

import { CliError } from "../core/errors.ts";
import { tomlGet } from "../supabase-config.ts";
import { runPg } from "./stack.ts";

export interface Bucket {
  readonly name: string;
  /** Absolute folder whose files become the bucket's objects. */
  readonly folder: string;
}

export interface SeedSources {
  /** SQL seed files relative to the project root, in the CLI's run order. */
  readonly sql: readonly string[];
  readonly buckets: readonly Bucket[];
  /** Every file the seed key hashes, relative to the project root. */
  readonly files: readonly string[];
}

function isTable(value: unknown): value is TomlTable {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function strings(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

async function walk(folder: string): Promise<string[]> {
  const entries = await readdir(folder, { withFileTypes: true }).catch(
    () => [],
  );

  const nested = await Promise.all(
    entries.map((entry) =>
      entry.isDirectory()
        ? walk(join(folder, entry.name))
        : Promise.resolve([join(folder, entry.name)]),
    ),
  );

  return nested.flat().toSorted();
}

/**
 * The seed files and bucket folders the stack would load: `[db.seed] sql_paths`
 * (patterns relative to the `supabase` folder, each expanded in sorted order)
 * and each `[storage.buckets.<name>] objects_path`.
 */
export async function seedSources(
  root: string,
  toml: SupabaseConfig | undefined,
): Promise<SeedSources> {
  const dir = join(root, toml?.dir ?? "supabase");
  const document: TomlTable = toml?.document ?? {};
  const patterns = strings(tomlGet(document, ["db", "seed", "sql_paths"]));
  const sql: string[] = [];

  for (const pattern of patterns.length > 0 ? patterns : ["./seed.sql"]) {
    const matches: string[] = [];

    for await (const match of glob(pattern, { cwd: dir })) {
      matches.push(match);
    }

    for (const match of matches.toSorted()) {
      const file = relative(root, resolve(dir, match)).replaceAll("\\", "/");

      if (!sql.includes(file)) {
        sql.push(file);
      }
    }
  }

  const bucketTable = tomlGet(document, ["storage", "buckets"]);
  const buckets: Bucket[] = [];

  if (isTable(bucketTable)) {
    for (const [name, value] of Object.entries(bucketTable)) {
      const objects = isTable(value)
        ? tomlGet(value, ["objects_path"])
        : undefined;

      if (typeof objects === "string" && objects !== "") {
        buckets.push({
          name,
          folder: isAbsolute(objects) ? objects : resolve(dir, objects),
        });
      }
    }
  }

  const objectFiles = (
    await Promise.all(buckets.map((bucket) => walk(bucket.folder)))
  ).flat();

  return {
    sql,
    buckets,
    files: [
      ...sql,
      ...objectFiles.map((file) => relative(root, file).replaceAll("\\", "/")),
    ],
  };
}

/** Runs the seed files in the CLI's order, each as its own script. */
export async function runSeedFiles(
  ctx: BaselineContext,
  url: string,
  sources: SeedSources,
): Promise<void> {
  for (const file of sources.sql) {
    ctx.log(`Seeding ${file}`);

    await runPg(ctx, "psql", [
      "--no-psqlrc",
      "--quiet",
      "-v",
      "ON_ERROR_STOP=1",
      "-f",
      join(ctx.root, file),
      url,
    ]);
  }
}

const MIME: Readonly<Record<string, string>> = {
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
  ".svg": "image/svg+xml",
  ".pdf": "application/pdf",
  ".json": "application/json",
  ".txt": "text/plain",
  ".csv": "text/csv",
  ".md": "text/markdown",
  ".html": "text/html",
  ".xml": "application/xml",
};

export interface UploadTarget {
  readonly apiUrl: string;
  readonly serviceKey: string;
}

const CONCURRENCY = 16;

/**
 * Uploads every file of each bucket folder through the Storage API, 16 at a
 * time.
 */
export async function uploadBuckets(
  buckets: readonly { readonly name: string; readonly folder: string }[],
  target: UploadTarget,
  upload: typeof fetch = fetch,
): Promise<number> {
  const jobs: { bucket: string; path: string; file: string }[] = [];

  for (const bucket of buckets) {
    for (const file of await walk(bucket.folder)) {
      jobs.push({
        bucket: bucket.name,
        path: relative(bucket.folder, file).replaceAll("\\", "/"),
        file,
      });
    }
  }

  let next = 0;

  const worker = async (): Promise<void> => {
    for (;;) {
      const job = jobs[next];
      next += 1;

      if (job === undefined) {
        return;
      }

      const response = await upload(
        `${target.apiUrl}/storage/v1/object/${encodeURIComponent(job.bucket)}/${job.path.split("/").map(encodeURIComponent).join("/")}`,
        {
          method: "POST",
          headers: {
            authorization: `Bearer ${target.serviceKey}`,
            apikey: target.serviceKey,
            "x-upsert": "true",
            "content-type":
              MIME[extname(job.file).toLowerCase()] ??
              "application/octet-stream",
          },
          body: await readFile(job.file),
        },
      );

      if (!response.ok) {
        throw new CliError(
          "request_failed",
          `Uploading ${job.bucket}/${job.path} failed with ${String(response.status)}: ${await response.text()}`,
        );
      }
    }
  };

  await Promise.all(
    Array.from({ length: Math.min(CONCURRENCY, jobs.length) }, worker),
  );

  return jobs.length;
}

/** Packs the bucket folders into one tarball with a folder per bucket. */
export async function packBuckets(
  ctx: BaselineContext,
  buckets: readonly Bucket[],
  out: string,
): Promise<void> {
  const staging = await mkdtemp(join(tmpdir(), "bsb-buckets-"));

  try {
    for (const bucket of buckets) {
      await symlink(bucket.folder, join(staging, bucket.name));
    }

    const result = await ctx.run(
      "tar",
      ["-czhf", out, "-C", staging, ...buckets.map((bucket) => bucket.name)],
      ctx.root,
      ctx.env,
    );

    if (result.code !== 0) {
      throw new CliError("failed", `tar failed: ${result.stderr.trim()}`);
    }
  } finally {
    await rm(staging, { recursive: true, force: true });
  }
}

/** Unpacks a tarball from `packBuckets` and returns its bucket folders. */
export async function unpackBuckets(
  ctx: BaselineContext,
  tarball: string,
): Promise<{
  readonly buckets: readonly Bucket[];
  readonly cleanup: () => Promise<void>;
}> {
  const folder = await mkdtemp(join(tmpdir(), "bsb-objects-"));
  const cleanup = () => rm(folder, { recursive: true, force: true });
  let unpacked = false;

  try {
    const result = await ctx.run(
      "tar",
      ["-xzf", tarball, "-C", folder],
      ctx.root,
      ctx.env,
    );

    if (result.code !== 0) {
      throw new CliError("failed", `tar failed: ${result.stderr.trim()}`);
    }

    const names = (await readdir(folder, { withFileTypes: true }))
      .filter((entry) => entry.isDirectory())
      .map((entry) => basename(entry.name));

    unpacked = true;

    return {
      buckets: names.map((name) => ({ name, folder: join(folder, name) })),
      cleanup,
    };
  } finally {
    if (!unpacked) {
      await cleanup();
    }
  }
}
