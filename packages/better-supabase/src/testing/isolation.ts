import { createClient } from "@supabase/supabase-js";

import type { Result } from "../core/result.ts";
import type {
  AnyFunctions,
  AnyModels,
  Insert,
  TableKey,
  TableMeta,
  Update,
} from "../schema/types.ts";
import type { TestJwtClaims } from "./jwt.ts";

import { BetterSupabase } from "../core/define.ts";
import { ENV_VARIABLES } from "../env/index.ts";
import { asUser, type LocalStack } from "./as-user.ts";
import {
  type Check,
  type ConformanceReport,
  conform,
  expect,
} from "./conformance.ts";

export interface IsolationTenant {
  /** Handed to each table's `row`, usually the tenant's id. */
  readonly id: string;
  /** The claims of a user in this tenant, as for `asUser`. */
  readonly claims: TestJwtClaims;
  /** Used in failure messages; defaults to `id`. */
  readonly name?: string;
}

export interface IsolationTable<M extends AnyModels, K extends keyof M> {
  /**
   * A row owned by `tenant`. `n` is 0 for the row seeded through the service
   * role and 1 for the other tenant's insert attempt: put it in unique columns.
   */
  readonly row: (tenant: IsolationTenant, n: 0 | 1) => Insert<M, K>;
  /** A change the other tenant tries to make. It must differ from `row`. */
  readonly update: Update<M, K>;
}

export type IsolationTables<M extends AnyModels> = {
  readonly [K in TableKey<M>]?: IsolationTable<M, K>;
};

export interface TenantIsolationOptions<M extends AnyModels> {
  readonly tenants: readonly [IsolationTenant, IsolationTenant];
  readonly tables: IsolationTables<M>;
  /** Defaults to `$SUPABASE_URL`, `$SUPABASE_PUBLISHABLE_KEY` and `$SUPABASE_SECRET_KEY`. */
  readonly stack?: LocalStack;
  /** Runs before any row is created, e.g. `() => seed.insert(sql)` for the tenants and their memberships. */
  readonly seed?: () => Promise<void>;
}

type Row = Readonly<Record<string, unknown>>;
type Outcome = PromiseLike<Result<unknown>>;
interface Repository {
  create(row: unknown, args?: object): Outcome;
  findMany(args: object): Outcome;
  updateMany(args: object): Outcome;
  deleteMany(args: object): Outcome;
}
type Repositories = Readonly<Record<string, Repository>>;

const scalar = (value: unknown): boolean =>
  typeof value === "string" ||
  typeof value === "number" ||
  typeof value === "boolean";

function keyOf(table: TableMeta, row: Row): Row {
  return Object.fromEntries(
    table.primaryKey.map((column) => [column, row[column]]),
  );
}

async function rowsOf(outcome: Outcome): Promise<Row[]> {
  const result = await outcome;
  if (!result.ok) throw new Error(result.error.message);
  // SAFETY: repository reads and writes return rows of the table, one or many.
  return (Array.isArray(result.data) ? result.data : [result.data]) as Row[];
}

function env(names: readonly string[]): string | undefined {
  if (typeof process === "undefined") return undefined;
  for (const name of names) {
    const value = process.env[name];
    if (value) return value;
  }
  return undefined;
}

/**
 * Checks row-level security between two tenants against a running stack: for
 * each table, a user of one tenant must not select, insert, update or delete
 * the other tenant's rows. Runs without `betterSupabase`'s plugins, so the `tenant()`
 * plugin can't hide a missing policy. Throws a `ConformanceError` naming each
 * table and command that leaks; removes every row it created.
 *
 * ```ts
 * await expectTenantIsolation(betterSupabase, {
 *   tenants: [
 *     { id: ACME, claims: { sub: alice, tenant_id: ACME } },
 *     { id: GLOBEX, claims: { sub: bob, tenant_id: GLOBEX } },
 *   ],
 *   tables: {
 *     tags: {
 *       row: (tenant, n) => ({ organizationId: tenant.id, name: `iso-${n}` }),
 *       update: { name: 'changed' },
 *     },
 *   },
 * });
 * ```
 */
export async function expectTenantIsolation<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
>(
  betterSupabase: BetterSupabase<M, D, F, E>,
  options: TenantIsolationOptions<M>,
): Promise<ConformanceReport> {
  const stack = options.stack ?? {};
  const bare = new BetterSupabase(betterSupabase.schema);
  const url = stack.url ?? env(ENV_VARIABLES.url) ?? "http://127.0.0.1:54321";
  const secretKey = stack.secretKey ?? env(ENV_VARIABLES.secretKey);
  if (!secretKey) {
    throw new TypeError(
      "expectTenantIsolation needs stack.secretKey or $SUPABASE_SECRET_KEY to seed rows.",
    );
  }
  // SAFETY: repositories are indexed by table name; the harness only uses the
  // tables in options.tables.
  // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- the harness indexes repositories by table name for any schema.
  const admin = bare.connect(
    createClient(url, secretKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    }),
  ) as unknown as Repositories;

  await options.seed?.();
  const tenants = options.tenants;
  // SAFETY: repositories are indexed by table name; the harness only uses the
  // tables in options.tables.
  const users = await Promise.all(
    tenants.map(
      async (tenant) =>
        // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- the harness indexes repositories by table name for any schema.
        (await asUser(bare, tenant.claims, stack))
          .db as unknown as Repositories,
    ),
  );
  const label = (tenant: IsolationTenant): string => tenant.name ?? tenant.id;
  const cleanup: (() => PromiseLike<unknown>)[] = [];
  const reads: Check[] = [];
  const deletes: Check[] = [];

  // SAFETY: options.tables maps table keys of M to IsolationTable, and
  // Object.entries widens it.
  try {
    for (const [key, spec] of Object.entries(options.tables) as [
      string,
      IsolationTable<M, keyof M>,
    ][]) {
      const table = bare.meta.tables[key];
      if (!table || table.primaryKey.length === 0) {
        throw new TypeError(
          `expectTenantIsolation: "${key}" is not a table with a primary key`,
        );
      }
      const seeded: Row[] = [];
      for (const tenant of tenants) {
        const [row] = await rowsOf(admin[key]!.create(spec.row(tenant, 0)));
        const where = keyOf(table, row!);
        cleanup.push(() => admin[key]!.deleteMany({ where }));
        seeded.push(row!);
      }

      for (const [self, other] of [
        [0, 1],
        [1, 0],
      ] as const) {
        const user = users[self]![key]!;
        const who = label(tenants[self]);
        const whose = `${label(tenants[other])}'s`;
        const own = keyOf(table, seeded[self]!);
        const target = keyOf(table, seeded[other]!);
        const current = async (): Promise<Row | undefined> =>
          (await rowsOf(admin[key]!.findMany({ where: target })))[0];

        reads.push(
          [
            `${key}: ${who} reads its own row`,
            async () => {
              const rows = await rowsOf(user.findMany({ where: own }));
              expect(
                rows.length === 1,
                `${who} can't read its own row, so the other checks prove nothing; check its claims and memberships`,
              );
            },
          ],
          [
            `${key}: ${who} can't select ${whose} rows`,
            async () => {
              const rows = await rowsOf(user.findMany({ where: target }));
              expect(rows.length === 0, `select returned ${whose} row`);
            },
          ],
          [
            `${key}: ${who} can't insert ${whose} rows`,
            async () => {
              // SAFETY: spec.row returns an insert row for this table, passed on untyped.
              const row = spec.row(tenants[other], 1) as Row;
              const result = await user.create(row, { returning: false });
              if (result.ok) {
                const where = Object.fromEntries(
                  Object.entries(row).filter(([, value]) => scalar(value)),
                );
                cleanup.push(() => admin[key]!.deleteMany({ where }));
              }
              expect(
                !result.ok,
                `insert of a row for ${whose} tenant succeeded`,
              );
              expect(
                result.error.kind === "forbidden",
                `insert failed with ${result.error.kind} (${result.error.message}), not an RLS error; check the row factory`,
              );
            },
          ],
          [
            `${key}: ${who} can't update ${whose} rows`,
            async () => {
              const before = await current();
              // SAFETY: spec.update is an update patch for this table, passed on untyped.
              const patch = spec.update as Row;
              expect(
                Object.entries(patch).some(
                  ([column, value]) => before?.[column] !== value,
                ),
                "update must change the row to detect a leak",
              );
              await user.updateMany({
                where: target,
                data: patch,
                returning: false,
              });
              const after = await current();
              expect(
                Object.entries(patch).every(
                  ([column]) => after?.[column] === before?.[column],
                ),
                `update changed ${whose} row`,
              );
            },
          ],
        );
        deletes.push([
          `${key}: ${who} can't delete ${whose} rows`,
          async () => {
            await user.deleteMany({ where: target });
            expect(
              (await current()) !== undefined,
              `delete removed ${whose} row`,
            );
          },
        ]);
      }
    }
    return await conform("Tenant isolation", [...reads, ...deletes]);
  } finally {
    for (const remove of cleanup.reverse()) await remove();
  }
}
