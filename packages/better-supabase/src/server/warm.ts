import { recordCold } from "../core/cold-start.ts";

/**
 * A Postgres pool `warm()` runs `select 1` on, typed structurally so the entry
 * imports neither `pg` nor `postgres` (invariant 6). `pg`'s `Pool` and a
 * `postgres` sql tag's `unsafe` both fit.
 */
export type WarmPool =
  | { readonly query: (sql: string) => PromiseLike<unknown> }
  | { readonly unsafe: (sql: string) => PromiseLike<unknown> };

/** A flags client `warm()` initializes, such as an OpenFeature provider. */
export interface WarmFlags {
  readonly initialize: () => unknown;
}

export interface WarmOptions {
  /** Runs `select 1` so the first request finds an open connection. */
  readonly postgres?: WarmPool;
  /** Calls `initialize()` so the first flag read doesn't wait for it. */
  readonly flags?: WarmFlags;
  /** Each step gives up after this many milliseconds. Defaults to 5000. */
  readonly timeoutMs?: number;
}

export type WarmStepName = "jwks" | "postgrest" | "read" | "pool" | "flags";

export interface WarmStep {
  readonly name: WarmStepName;
  readonly ms: number;
  readonly ok: boolean;
  /** The error's message when the step failed or timed out. */
  readonly error?: string;
}

/** What `warm()` resolves to. It never rejects. */
export interface WarmReport {
  /** Wall time of the whole warm-up; the steps run in parallel. */
  readonly ms: number;
  readonly steps: readonly WarmStep[];
}

/** What the server hands `warmUp`: its own fetch, URLs and JWKS loader. */
export interface WarmDeps {
  readonly url: () => string;
  readonly readUrl: () => string | undefined;
  readonly publishableKey: () => string;
  readonly fetch: typeof globalThis.fetch;
  /** Loads the JWKS, or `undefined` when the keys are inline or not remote. */
  readonly jwks: () => Promise<void> | undefined;
}

const DEFAULT_TIMEOUT_MS = 5000;

const roundMs = (ms: number): number => Math.round(ms * 100) / 100;

function messageOf(cause: unknown): string {
  return cause instanceof Error ? cause.message : String(cause);
}

async function timed(
  name: WarmStepName,
  run: () => unknown,
  timeoutMs: number,
): Promise<WarmStep> {
  const started = performance.now();
  let timer: ReturnType<typeof setTimeout> | undefined;

  try {
    await Promise.race([
      Promise.resolve().then(run),
      new Promise((_, reject) => {
        timer = setTimeout(() => {
          reject(new Error(`timed out after ${timeoutMs} ms`));
        }, timeoutMs);
      }),
    ]);

    return { name, ms: roundMs(performance.now() - started), ok: true };
  } catch (cause) {
    return {
      name,
      ms: roundMs(performance.now() - started),
      ok: false,
      error: messageOf(cause),
    };
  } finally {
    clearTimeout(timer);
  }
}

function restRoot(url: string): string {
  return new URL("rest/v1/", url.endsWith("/") ? url : `${url}/`).href;
}

/**
 * Opens the connection to PostgREST with an `OPTIONS` request. A `GET` of the
 * root makes PostgREST build the OpenAPI description of every exposed schema,
 * which is slow and large on a big schema and is exactly what a cold start
 * should not wait for; `OPTIONS` answers from the router alone.
 */
async function ping(deps: WarmDeps, url: string): Promise<void> {
  const response = await deps.fetch(restRoot(url), {
    method: "OPTIONS",
    headers: { apikey: deps.publishableKey() },
  });

  // The body is read so the connection goes back to the pool.
  await response.arrayBuffer();

  if (response.status >= 500) {
    throw new Error(`PostgREST answered ${response.status}`);
  }
}

function selectOne(pool: WarmPool): PromiseLike<unknown> {
  return "query" in pool ? pool.query("select 1") : pool.unsafe("select 1");
}

/**
 * Opens what the first request would otherwise wait for: the JWKS, the
 * connection to PostgREST (and the read replica), a pool connection and the
 * flags client. The steps run in parallel, each with a timeout, and a failed
 * step is reported, never thrown.
 */
export async function warmUp(
  deps: WarmDeps,
  options: WarmOptions = {},
): Promise<WarmReport> {
  const started = performance.now();
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const steps: Promise<WarmStep>[] = [];

  const jwks = (() => {
    try {
      return deps.jwks();
    } catch {
      return;
    }
  })();

  if (jwks) {
    steps.push(timed("jwks", () => jwks, timeoutMs));
  }

  steps.push(timed("postgrest", () => ping(deps, deps.url()), timeoutMs));

  const read = (() => {
    try {
      return deps.readUrl();
    } catch {
      return;
    }
  })();

  if (read) {
    steps.push(timed("read", () => ping(deps, read), timeoutMs));
  }

  const { postgres, flags } = options;

  if (postgres) {
    steps.push(timed("pool", () => selectOne(postgres), timeoutMs));
  }

  if (flags) {
    steps.push(timed("flags", () => flags.initialize(), timeoutMs));
  }

  const done = await Promise.all(steps);

  recordCold("warm", performance.now() - started);

  return { ms: roundMs(performance.now() - started), steps: done };
}
