import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { LocalStack } from "../../src/testing/as-user.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { tenant } from "../../src/plugins/tenant/index.ts";
import { ConformanceError } from "../../src/testing/conformance.ts";
import { expectTenantIsolation } from "../../src/testing/isolation.ts";
import { schema } from "../fixtures/generated-camel.ts";

const SECRET = "sb_secret_unit";
const stack: LocalStack = {
  url: "http://127.0.0.1:54321",
  publishableKey: "sb_publishable_unit",
  secretKey: SECRET,
  alg: "HS256",
};
const ACME = "00000000-0000-4000-8000-000000000001";
const GLOBEX = "00000000-0000-4000-8000-000000000002";
const USER = "00000000-0000-4000-8000-0000000000ff";
const tenants = [
  { id: ACME, name: "acme", claims: { sub: USER, tenant_id: ACME } },
  { id: GLOBEX, claims: { sub: USER, tenant_id: GLOBEX } },
] as const;
const sb = defineSupabase(schema).use(tenant());
const tags = {
  row: (owner: { id: string }, n: 0 | 1) => ({
    organizationId: owner.id,
    name: `iso-${n}`,
  }),
  update: { color: "red" as const },
};

type Row = Record<string, unknown>;
type Command = "select" | "insert" | "update" | "delete";

interface Logged {
  readonly method: string;
  readonly table: string;
  readonly admin: boolean;
  readonly query: string;
}

/**
 * An in-memory PostgREST with a tenant policy on every table: a user only
 * sees and writes rows whose `organization_id` matches its `tenant_id`
 * claim. `leaks` drops the policy for a command.
 */
function fakePostgrest(
  options: {
    readonly leaks?: readonly Command[];
    readonly insertError?: { status: number; code: string; message: string };
    readonly hideOwn?: boolean;
  } = {},
) {
  const tables = new Map<string, Row[]>();
  const log: Logged[] = [];
  let ids = 0;
  const leaks = new Set(options.leaks);

  const tenantOf = (headers: Headers): string | null | undefined => {
    if (headers.get("apikey") === SECRET) return undefined;
    const token = headers.get("authorization")?.replace(/^Bearer /, "");
    const body = token?.split(".")[1];
    if (!body) return null;
    const claims = JSON.parse(
      atob(body.replaceAll("-", "+").replaceAll("_", "/")),
    ) as Row;
    return typeof claims["tenant_id"] === "string" ? claims["tenant_id"] : null;
  };

  const filtersOf = (params: URLSearchParams): [string, string][] =>
    [...params.entries()]
      .filter(([key]) => !["select", "columns", "limit", "order"].includes(key))
      .map(([key, value]) => [
        key,
        value.replace(/^eq\./, "").replaceAll(/^"|"$/g, ""),
      ]);

  const project = (rows: Row[], select: string | null): Row[] => {
    if (!select || select === "*") return rows.map((row) => ({ ...row }));
    const fields = select.split(",").map((field) => {
      const [alias, column] = field.includes(":")
        ? field.split(":")
        : [field, field];
      return [alias!, column!.replace(/::\w+$/, "")] as const;
    });
    return rows.map((row) =>
      Object.fromEntries(fields.map(([alias, column]) => [alias, row[column]])),
    );
  };

  const respond = (status: number, body?: unknown): Response =>
    new Response(body === undefined ? null : JSON.stringify(body), {
      status,
      headers: { "content-type": "application/json" },
    });

  const fetch = vi.fn(
    async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
      const request = new Request(input, init);
      const url = new URL(request.url);
      const table = url.pathname.replace("/rest/v1/", "");
      const owner = tenantOf(request.headers);
      const admin = owner === undefined;
      const rows = tables.get(table) ?? [];
      tables.set(table, rows);
      log.push({
        method: request.method,
        table,
        admin,
        query: decodeURIComponent(url.search),
      });
      const visible = (command: Command, row: Row) =>
        admin ||
        leaks.has(command) ||
        (row["organization_id"] === owner &&
          !(options.hideOwn && command === "select"));
      const filters = filtersOf(url.searchParams);
      const matching = (command: Command) =>
        rows.filter(
          (row) =>
            visible(command, row) &&
            filters.every(([column, value]) => String(row[column]) === value),
        );
      const wantsRows = request.headers
        .get("prefer")
        ?.includes("return=representation");
      const select = url.searchParams.get("select");

      switch (request.method) {
        case "GET":
        case "HEAD":
          return respond(200, project(matching("select"), select));
        case "POST": {
          const body = (await request.json()) as Row | Row[];
          const incoming = Array.isArray(body) ? body : [body];
          if (!admin && options.insertError) {
            const { status, ...error } = options.insertError;
            return respond(status, error);
          }
          if (incoming.some((row) => !visible("insert", row))) {
            return respond(403, {
              code: "42501",
              message:
                'new row violates row-level security policy for table "tags"',
            });
          }
          const created = incoming.map((row) => ({
            id: `row-${(ids += 1)}`,
            color: "gray",
            ...row,
          }));
          rows.push(...created);
          return wantsRows
            ? respond(201, project(created, select))
            : respond(201);
        }
        case "PATCH": {
          const patch = (await request.json()) as Row;
          const changed = matching("update");
          for (const row of changed) Object.assign(row, patch);
          return wantsRows
            ? respond(200, project(changed, select))
            : respond(204);
        }
        case "DELETE": {
          const removed = matching("delete");
          for (const row of removed) rows.splice(rows.indexOf(row), 1);
          return wantsRows
            ? respond(200, project(removed, select))
            : respond(204);
        }
        default:
          return respond(405, { message: "method not allowed" });
      }
    },
  );
  return { fetch, tables, log };
}

async function failures(pending: Promise<unknown>): Promise<string[]> {
  const error = await pending.then(
    () => undefined,
    (cause: unknown) => cause,
  );
  expect(error).toBeInstanceOf(ConformanceError);
  return (error as ConformanceError).report.checks
    .filter((check) => !check.ok)
    .map((check) => `${check.name}: ${check.message}`);
}

let api: ReturnType<typeof fakePostgrest>;

beforeEach(() => {
  api = fakePostgrest();
  vi.stubGlobal("fetch", api.fetch);
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
});

describe("expectTenantIsolation", () => {
  it("passes when every command is scoped, and removes every row it seeded", async () => {
    const seed = vi.fn(async () => undefined);
    const report = await expectTenantIsolation(sb, {
      stack,
      tenants,
      tables: { tags },
      seed,
    });
    expect(seed).toHaveBeenCalledOnce();
    expect(report.subject).toBe("Tenant isolation");
    expect(report.checks.map((check) => check.name)).toEqual([
      "tags: acme reads its own row",
      `tags: acme can't select ${GLOBEX}'s rows`,
      `tags: acme can't insert ${GLOBEX}'s rows`,
      `tags: acme can't update ${GLOBEX}'s rows`,
      `tags: ${GLOBEX} reads its own row`,
      `tags: ${GLOBEX} can't select acme's rows`,
      `tags: ${GLOBEX} can't insert acme's rows`,
      `tags: ${GLOBEX} can't update acme's rows`,
      `tags: acme can't delete ${GLOBEX}'s rows`,
      `tags: ${GLOBEX} can't delete acme's rows`,
    ]);
    expect(api.tables.get("tags")).toEqual([]);

    // Seeding and cleanup go through the secret key, the probes through user tokens.
    const seeded = api.log.filter((entry) => entry.method === "POST");
    expect(seeded.map((entry) => entry.admin)).toEqual([
      true,
      true,
      false,
      false,
    ]);
    expect(
      api.log.filter((entry) => entry.method === "DELETE" && entry.admin),
    ).toHaveLength(2);
  });

  it("names each command that leaks and still cleans up", async () => {
    api = fakePostgrest({ leaks: ["select", "update", "delete", "insert"] });
    vi.stubGlobal("fetch", api.fetch);
    expect(
      await failures(
        expectTenantIsolation(sb, { stack, tenants, tables: { tags } }),
      ),
    ).toEqual([
      `tags: acme can't select ${GLOBEX}'s rows: select returned ${GLOBEX}'s row`,
      `tags: acme can't insert ${GLOBEX}'s rows: insert of a row for ${GLOBEX}'s tenant succeeded`,
      `tags: acme can't update ${GLOBEX}'s rows: update changed ${GLOBEX}'s row`,
      `tags: ${GLOBEX} can't select acme's rows: select returned acme's row`,
      `tags: ${GLOBEX} can't insert acme's rows: insert of a row for acme's tenant succeeded`,
      `tags: ${GLOBEX} can't update acme's rows: update changed acme's row`,
      `tags: acme can't delete ${GLOBEX}'s rows: delete removed ${GLOBEX}'s row`,
      `tags: ${GLOBEX} can't delete acme's rows: delete removed acme's row`,
    ]);
    expect(api.tables.get("tags")).toEqual([]);
  });

  it("explains a tenant that can't read its own row", async () => {
    api = fakePostgrest({ hideOwn: true });
    vi.stubGlobal("fetch", api.fetch);
    const failed = await failures(
      expectTenantIsolation(sb, { stack, tenants, tables: { tags } }),
    );
    expect(failed).toEqual([
      "tags: acme reads its own row: acme can't read its own row, so the other checks prove nothing; check its claims and memberships",
      `tags: ${GLOBEX} reads its own row: ${GLOBEX} can't read its own row, so the other checks prove nothing; check its claims and memberships`,
    ]);
  });

  it("flags inserts that fail for a reason other than RLS", async () => {
    api = fakePostgrest({
      insertError: {
        status: 400,
        code: "23502",
        message: 'null value in column "name"',
      },
    });
    vi.stubGlobal("fetch", api.fetch);
    const failed = await failures(
      expectTenantIsolation(sb, { stack, tenants, tables: { tags } }),
    );
    expect(failed).toHaveLength(2);
    expect(failed[0]).toMatch(
      /^tags: acme can't insert .*: insert failed with \w+ \(null value in column "name"\), not an RLS error; check the row factory$/,
    );
  });

  it("requires an update that changes the row", async () => {
    const failed = await failures(
      expectTenantIsolation(sb, {
        stack,
        tenants,
        tables: { tags: { ...tags, update: { color: "gray" } } },
      }),
    );
    expect(failed).toEqual([
      `tags: acme can't update ${GLOBEX}'s rows: update must change the row to detect a leak`,
      `tags: ${GLOBEX} can't update acme's rows: update must change the row to detect a leak`,
    ]);
  });

  it("rejects tables without a primary key, after cleaning up earlier tables", async () => {
    const keyless = defineSupabase({
      ...schema,
      meta: {
        ...schema.meta,
        tables: {
          ...schema.meta.tables,
          tags: { ...schema.meta.tables["tags"], primaryKey: [] },
        },
      },
    } as never);
    await expect(
      expectTenantIsolation(keyless, {
        stack,
        tenants,
        tables: { tags },
      }),
    ).rejects.toThrow(
      'expectTenantIsolation: "tags" is not a table with a primary key',
    );
    await expect(
      expectTenantIsolation(sb, {
        stack,
        tenants,
        tables: { nope: tags } as never,
      }),
    ).rejects.toThrow('"nope" is not a table with a primary key');
  });

  it("surfaces a failed seed write and removes what it created", async () => {
    let posts = 0;
    const inner = api.fetch;
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
        if (init?.method === "POST" && (posts += 1) === 2)
          return new Response(
            JSON.stringify({ code: "23505", message: "duplicate key" }),
            { status: 409, headers: { "content-type": "application/json" } },
          );
        return inner(input, init);
      }),
    );
    await expect(
      expectTenantIsolation(sb, { stack, tenants, tables: { tags } }),
    ).rejects.toThrow("duplicate key");
    expect(api.tables.get("tags")).toEqual([]);
  });

  it("cleans up leaked inserts by their scalar columns in every table", async () => {
    api = fakePostgrest({ leaks: ["insert"] });
    vi.stubGlobal("fetch", api.fetch);
    const locations = {
      row: (owner: { id: string }, n: 0 | 1) => ({
        organizationId: owner.id,
        customerId: "c1",
        label: `loc-${n}`,
        isPrimary: n === 1,
      }),
      update: { label: "moved" },
    };
    const failed = await failures(
      expectTenantIsolation(sb, {
        stack,
        tenants,
        tables: { tags, locations },
      }),
    );
    expect(failed.filter((name) => name.includes("can't insert"))).toHaveLength(
      4,
    );
    expect(api.tables.get("tags")).toEqual([]);
    expect(api.tables.get("locations")).toEqual([]);
    const cleanup = api.log.filter(
      (entry) =>
        entry.method === "DELETE" &&
        entry.table === "locations" &&
        entry.query.includes("is_primary=eq.true"),
    );
    expect(cleanup).toHaveLength(2);
  });

  it("defaults the URL to the local stack", async () => {
    for (const prefix of [
      "",
      "NEXT_PUBLIC_",
      "VITE_",
      "PUBLIC_",
      "EXPO_PUBLIC_",
      "NUXT_PUBLIC_",
    ])
      vi.stubEnv(`${prefix}SUPABASE_URL`, "");
    const { url: _url, ...withoutUrl } = stack;
    await expectTenantIsolation(sb, {
      stack: withoutUrl,
      tenants,
      tables: { tags },
    });
    expect(new Request(api.fetch.mock.calls[0]![0]).url).toMatch(
      /^http:\/\/127\.0\.0\.1:54321\/rest\/v1\/tags/,
    );
  });

  it("reads the stack from the environment and needs a secret key", async () => {
    vi.stubEnv("SUPABASE_URL", "http://127.0.0.1:54321");
    vi.stubEnv("SUPABASE_PUBLISHABLE_KEY", "sb_publishable_unit");
    vi.stubEnv("SUPABASE_SECRET_KEY", "");
    await expect(
      expectTenantIsolation(sb, {
        stack: { alg: "HS256" },
        tenants,
        tables: { tags },
      }),
    ).rejects.toThrow(
      "expectTenantIsolation needs stack.secretKey or $SUPABASE_SECRET_KEY to seed rows.",
    );
    vi.stubEnv("SUPABASE_SECRET_KEY", SECRET);
    const report = await expectTenantIsolation(sb, {
      stack: { alg: "HS256" },
      tenants,
      tables: { tags },
    });
    expect(report.checks.every((check) => check.ok)).toBe(true);
    expect(
      api.fetch.mock.calls.every(([input]) =>
        new Request(input).url.startsWith("http://127.0.0.1:54321/rest/v1/"),
      ),
    ).toBe(true);
  });
});
