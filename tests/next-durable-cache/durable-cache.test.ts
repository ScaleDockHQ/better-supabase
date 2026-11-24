import { spawn } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { mkdtemp, readFile, rename, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { parseEnv } from "node:util";
import { describe, expect, it } from "vitest";

const ROOT = resolve(import.meta.dirname, "../..");
const APP = join(ROOT, "apps/examples/nextjs");
const NEXT = join(APP, ".next");
const META = join(APP, "src/lib/supabase/generated.meta.js");
const LIBRARY = join(ROOT, "packages/better-supabase/dist/next/index.js");
const RESULTS = resolve(import.meta.dirname, "results.json");
const ENV_FILE = join(ROOT, ".env.development.local");
const PORT = 3917;
const SECRET = "durable-cache-probe-0123456789abcdef";
const ROUTE = "app/api/probe/durable-cache/route";

/**
 * What the probe route answers; see
 * apps/examples/nextjs/src/lib/durable-probe.ts.
 */
interface Probe {
  readonly process: string;
  readonly public: { readonly filledBy: string };
  readonly remote: { readonly filledBy: string };
}

interface Durability {
  readonly codeHash: string;
  readonly runtimeEnvVarsRead: readonly string[];
}

/** Whether each reader read the entry the previous run filled. */
interface Row {
  readonly scenario: string;
  readonly buildMs: number | null;
  readonly codeHash: string;
  readonly public: boolean;
  readonly remote: boolean;
  readonly probeMs: number;
}

/**
 * The variables better-supabase reads by computed name, and the ones Vercel
 * sets per deployment: none may key an entry unless the app names it.
 */
const NOT_IN_KEY = new Set([
  "SUPABASE_URL",
  "SUPABASE_PUBLISHABLE_KEY",
  "VERCEL_URL",
  "VERCEL_DEPLOYMENT_ID",
  "VERCEL_GIT_COMMIT_SHA",
]);

/**
 * The root env file, with `SUPABASE_JWKS` kept raw: the dotenv parser strips
 * the quotes inside its JSON.
 */
function appEnv(): NodeJS.ProcessEnv {
  const text = readFileSync(ENV_FILE, "utf-8");
  const env: NodeJS.ProcessEnv = { ...parseEnv(text) };
  const jwks = /^SUPABASE_JWKS=(.*)$/m.exec(text)?.[1];

  if (jwks) {
    env["SUPABASE_JWKS"] = jwks;
  }

  return env;
}

function run(args: readonly string[], env: NodeJS.ProcessEnv): Promise<number> {
  const started = performance.now();

  return new Promise((done, fail) => {
    const child = spawn("pnpm", ["exec", "next", ...args], {
      cwd: APP,
      env: { ...process.env, ...env },
      stdio: ["ignore", "ignore", "pipe"],
    });

    let stderr = "";

    child.stderr.on("data", (chunk: Buffer) => {
      stderr += chunk.toString();
    });
    child.on("error", fail);
    child.on("exit", (code) => {
      if (code === 0) {
        done(Math.round(performance.now() - started));
      } else {
        fail(
          new Error(`next ${args.join(" ")} exited ${String(code)}\n${stderr}`),
        );
      }
    });
  });
}

/** Starts the build, probes once and stops it. */
async function probe(
  env: NodeJS.ProcessEnv,
): Promise<{ answer: Probe; ms: number }> {
  const server = spawn("pnpm", ["exec", "next", "start", "-p", String(PORT)], {
    cwd: APP,
    env: { ...process.env, ...env },
    stdio: "ignore",
  });

  try {
    for (let attempt = 0; attempt < 120; attempt += 1) {
      const started = performance.now();

      const response = await fetch(
        `http://localhost:${String(PORT)}/api/probe/durable-cache`,
        { headers: { authorization: `Bearer ${SECRET}` } },
      ).catch(() => undefined);

      if (response?.ok) {
        // SAFETY: the probe route answers this shape.
        const answer = (await response.json()) as Probe;

        return { answer, ms: Math.round(performance.now() - started) };
      }

      await new Promise((wait) => {
        setTimeout(wait, 250);
      });
    }

    throw new Error("next start did not answer the probe");
  } finally {
    server.kill("SIGTERM");
    await new Promise((stopped) => {
      server.once("exit", stopped);
    });
  }
}

async function durability(): Promise<Durability> {
  const manifest: {
    node: Record<
      string,
      { workers: Record<string, { durability?: Durability }> }
    >;
  } = JSON.parse(
    await readFile(
      join(NEXT, "server/server-reference-manifest.json"),
      "utf-8",
    ),
  );

  for (const entry of Object.values(manifest.node)) {
    const found = entry.workers[ROUTE]?.durability;

    if (found) {
      return found;
    }
  }

  throw new Error(`no durability for ${ROUTE}; is the flag on?`);
}

/** Runs `change`, then puts the file back. */
async function withEdit<T>(
  file: string,
  edit: (text: string) => string,
  body: () => Promise<T>,
): Promise<T> {
  const original = await readFile(file, "utf-8");
  const edited = edit(original);

  if (edited === original) {
    throw new Error(`the edit left ${file} unchanged`);
  }

  await writeFile(file, edited);

  try {
    return await body();
  } finally {
    await writeFile(file, original);
  }
}

const enabled = process.env["NEXT_DURABLE_CACHE"] === "1";

describe.skipIf(!enabled || !existsSync(ENV_FILE))(
  "experimental.durableUseCacheEntries on the Next.js example",
  () => {
    it(
      "reads the previous build's entry only while nothing it depends on changed",
      async () => {
        const dir = await mkdtemp(join(tmpdir(), "bsb-durable-"));
        const kept = `${NEXT}-before-durable-cache`;

        const env = {
          ...appEnv(),
          BSB_DURABLE_USE_CACHE: "1",
          BSB_REMOTE_CACHE_DIR: dir,
          BSB_TAG_PROBE_SECRET: SECRET,
        };

        const rows: Row[] = [];
        let previous: string | undefined;
        let envList: readonly string[] = [];

        const step = async (
          scenario: string,
          build: boolean,
          extra: NodeJS.ProcessEnv = {},
        ): Promise<void> => {
          const buildMs = build ? await run(["build"], env) : null;
          const { codeHash, runtimeEnvVarsRead } = await durability();
          const { answer, ms } = await probe({ ...env, ...extra });

          envList = runtimeEnvVarsRead;
          rows.push({
            scenario,
            buildMs,
            codeHash,
            public: answer.public.filledBy === previous,
            remote: answer.remote.filledBy === previous,
            probeMs: ms,
          });
          previous = answer.process;
        };

        if (existsSync(NEXT)) {
          await rename(NEXT, kept);
        }

        try {
          await step("fill", true);
          await step("rebuild, no change", true);
          await withEdit(
            META,
            (text) =>
              text.replace(
                '"note_kind": ["call","meeting","email"]',
                '"note_kind": ["call","meeting","email","visit"]',
              ),
            () => step("migration and gen (a new enum value)", true),
          );
          await withEdit(
            LIBRARY,
            (text) =>
              `${text}\nglobalThis[Symbol.for("bsb.durable-cache.upgrade")] = 1;\n`,
            async () => {
              await step("better-supabase code change", true);
              await step("restart, a listed env var changed", false, {
                PDL_API_KEY: "changed",
              });
              await step("restart, per-deployment Vercel vars changed", false, {
                PDL_API_KEY: "changed",
                VERCEL_URL: "other.vercel.app",
                VERCEL_DEPLOYMENT_ID: "dpl_other",
                VERCEL_GIT_COMMIT_SHA: "0".repeat(40),
              });
            },
          );
        } finally {
          await rm(NEXT, { recursive: true, force: true });

          if (existsSync(kept)) {
            await rename(kept, NEXT);
          }

          await rm(dir, { recursive: true, force: true });
        }

        await writeFile(
          RESULTS,
          `${JSON.stringify({ rows, envVarsInKey: envList.length }, null, 2)}\n`,
        );

        const read = Object.fromEntries(
          rows.map((row) => [row.scenario, [row.public, row.remote]]),
        );

        expect(read).toEqual({
          fill: [false, false],
          "rebuild, no change": [true, true],
          "migration and gen (a new enum value)": [false, false],
          "better-supabase code change": [false, false],
          "restart, a listed env var changed": [false, false],
          "restart, per-deployment Vercel vars changed": [true, true],
        });
        expect(envList.filter((name) => NOT_IN_KEY.has(name))).toEqual([]);
      },
      30 * 60_000,
    );
  },
);
