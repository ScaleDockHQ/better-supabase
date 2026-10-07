import type { Pool } from "pg";

export interface SchemaCacheWait {
  readonly url: string;
  readonly apikey: string;
  /** Tables or views as `schema.name` or `name` (in `public`). */
  readonly tables?: readonly string[];
  /** Functions with arguments that match one of their signatures. */
  readonly functions?: readonly {
    readonly name: string;
    readonly args: Readonly<Record<string, unknown>>;
  }[];
  readonly timeout?: number;
}

const MISSING = new Set(["PGRST202", "PGRST205"]);

function target(name: string): { schema: string; name: string } {
  const [schema, rest] = name.includes(".")
    ? name.split(".", 2)
    : ["public", name];
  return { schema: schema!, name: rest! };
}

async function missing(response: Response): Promise<boolean> {
  if (response.ok) return false;
  const body = (await response.json().catch(() => ({}))) as {
    code?: string;
  };
  return MISSING.has(body.code ?? "");
}

/**
 * Asks PostgREST to reload its schema cache, then waits until every named
 * table and function resolves. A probe that is denied or fails for another
 * reason still counts as found: only "not in the schema cache" waits. The
 * reload is requested again while waiting, because a reload that started
 * before the new objects committed (another test's DDL) never sees them.
 */
export async function reloadSchemaCache(
  pool: Pool,
  wait: SchemaCacheWait,
): Promise<void> {
  const headers = (schema: string): Record<string, string> => ({
    apikey: wait.apikey,
    "accept-profile": schema,
    "content-profile": schema,
    "content-type": "application/json",
  });
  const probes = [
    ...(wait.tables ?? []).map((name) => {
      const table = target(name);
      return () =>
        fetch(`${wait.url}/rest/v1/${table.name}?limit=0`, {
          headers: headers(table.schema),
        });
    }),
    ...(wait.functions ?? []).map((fn) => {
      const callee = target(fn.name);
      return () =>
        fetch(`${wait.url}/rest/v1/rpc/${callee.name}?limit=0`, {
          method: "POST",
          headers: headers(callee.schema),
          body: JSON.stringify(fn.args),
        });
    }),
  ];
  const deadline = Date.now() + (wait.timeout ?? 30_000);
  let pending = probes;
  for (let attempt = 0; ; attempt++) {
    if (attempt % 8 === 0) await pool.query(`notify pgrst, 'reload schema'`);
    const results = await Promise.all(
      pending.map(async (probe) => ({
        probe,
        missing: await missing(await probe()),
      })),
    );
    pending = results
      .filter((entry) => entry.missing)
      .map((entry) => entry.probe);
    if (pending.length === 0) return;
    if (Date.now() > deadline) {
      throw new Error(
        `PostgREST's schema cache still misses ${pending.length} of the objects after ${wait.timeout ?? 30_000} ms`,
      );
    }
    await new Promise((resolve) => {
      setTimeout(resolve, 250);
    });
  }
}
