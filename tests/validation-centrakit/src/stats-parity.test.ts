import { createClient } from "@supabase/supabase-js";
import { createSupabase, defineSchema, StatsRecorder } from "better-supabase";
import { postgresExecutor } from "better-supabase/postgres";
import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { customerService } from "./services/customers.ts";
import { betterSupabase } from "./services/schema.ts";
import { dbUrl, reachable, ROLES, USERS, withCentraKit } from "./stack.ts";

const live = await reachable();

const claims = { sub: USERS.member, role: "authenticated" };

/**
 * Statements `pg_stat_statements` has counted for the tables this test touches.
 * The extension is global, so the test reads a delta and never resets it. A
 * security-definer helper can add statements the recorder does not count, so
 * the delta is at least the recorder's calls.
 */
async function statementCalls(
  query: (
    text: string,
    params?: readonly unknown[],
  ) => Promise<{ rows: readonly { calls: string }[] }>,
  like: readonly string[],
): Promise<number> {
  const { rows } = await query(
    `select coalesce(sum(calls), 0)::text as calls
     from pg_stat_statements
     where ${like.map((_, index) => `query ilike $${index + 1}`).join(" or ")}`,
    like,
  );

  return Number(rows[0]?.calls ?? 0);
}

/** How often pg_stat_statements has evicted entries since its last reset. */
async function deallocs(pool: Pool): Promise<number> {
  const { rows } = await pool.query<{ dealloc: string }>(
    "select dealloc::text from pg_stat_statements_info",
  );

  return Number(rows[0]?.dealloc ?? 0);
}

describe("request stats against pg_stat_statements", () => {
  const pool = live ? new Pool({ connectionString: dbUrl, max: 4 }) : undefined;

  afterAll(async () => {
    await pool?.end();
  });

  it.skipIf(!live || pool === undefined)(
    "counts one page, one action and one batch on the pool connection",
    async () => {
      if (pool === undefined) {
        return;
      }

      // Quoted identifiers, so the schema install's `centrakit.customers` comments
      // are not counted. Measured after the install, around the calls only.
      const like = [
        '%"centrakit"."customers"%',
        '%"centrakit"."organization_users"%',
        "%parity_read_batch%",
      ];

      await withCentraKit(pool, async (session) => {
        await session.as("service");

        const org = (
          await session.rows<{ id: string }>(
            "insert into centrakit.organizations (name, slug) values ('Parity', $1) returning id",
            [`parity-${crypto.randomUUID().slice(0, 8)}`],
          )
        )[0]!.id;

        await session.client.query(
          "insert into centrakit.organization_users (organization_id, user_id, role_id) values ($1, $2, $3)",
          [org, USERS.member, ROLES.member],
        );
        await session.client.query(
          `create function centrakit.parity_read_batch(calls jsonb)
           returns jsonb language plpgsql stable as $fn$ begin return calls; end $fn$`,
        );

        const request = new StatsRecorder();

        const db = betterSupabase.connect(
          postgresExecutor(session.sql),
          { claims },
          { stats: request },
        );

        const service = customerService(db);

        await session.as("member");

        const before = await statementCalls(
          (text, params) =>
            session.client.query(text, params ? [...params] : []),
          like,
        );

        request.setPhase("render");
        await Promise.all([service.page(org), service.members(org)]);

        const page = request.snapshot();

        expect(page.calls).toBe(2);
        expect(page.waves).toBe(1);
        expect(page.phases?.render).toBe(2);

        request.setPhase("write");
        await db.customers
          .create([
            { organizationId: org, companyName: "Parity Co", status: "active" },
          ])
          .orThrow();

        request.setPhase("render");
        await service.page(org);
        await db
          .$rpc("parity_read_batch", { calls: [] }, { schema: "centrakit" })
          .orThrow();

        const done = request.snapshot();

        expect(done.calls).toBe(5);
        expect(done.phases?.write).toBe(1);
        expect(done.phases?.render).toBe(4);

        const delta =
          (await statementCalls(
            (text, params) =>
              session.client.query(text, params ? [...params] : []),
            like,
          )) - before;

        // One statement per repository call and the batch. RLS helpers stay
        // inside those statements, so the two counts match.
        expect(delta).toBe(done.calls);
      });
    },
  );

  it.skipIf(
    !live ||
      pool === undefined ||
      process.env["SUPABASE_URL"] === undefined ||
      process.env["SUPABASE_SECRET_KEY"] === undefined,
  )("counts a connect() over a supabase-js client", async () => {
    const url = process.env["SUPABASE_URL"];
    const key = process.env["SUPABASE_SECRET_KEY"];

    if (url === undefined || key === undefined || pool === undefined) {
      return;
    }

    interface PublicCustomer {
      id: string;
    }

    type PublicModels = {
      customers: {
        Row: PublicCustomer;
        Insert: Partial<PublicCustomer>;
        Update: Partial<PublicCustomer>;
        Relations: Record<never, never>;
        PrimaryKey: "id";
        UniqueKeys: Record<never, never>;
        Flags: Record<never, never>;
      };
    };

    const listed = createSupabase(
      defineSchema<PublicModels>({
        version: 1,
        casing: "camel",
        tables: {
          customers: {
            key: "customers",
            name: "customers",
            schema: "public",
            kind: "table",
            columns: { id: { db: "id", type: "uuid", hasDefault: true } },
            primaryKey: ["id"],
            uniqueKeys: {},
            relations: {},
            flags: {},
          },
        },
        enums: {},
        functions: {},
      }),
    );

    // The published client is the one an app builds itself. Its calls go
    // through connect(), the same path as connect(postgresExecutor()).
    const client = createClient(url, key, { auth: { persistSession: false } });

    const query = (text: string, params?: readonly unknown[]) =>
      pool.query<{ calls: string }>(text, params ? [...params] : []);

    // Other test files fill pg_stat_statements too. When it passes its max it
    // evicts the least used entries, which can drop counted statements between
    // the two reads; a measurement during an eviction is taken again.
    let calls = 0;
    let delta = 0;

    for (let attempt = 0; attempt < 3; attempt += 1) {
      const evictions = await deallocs(pool);
      const request = new StatsRecorder();
      const db = listed.connect(client, {}, { stats: request });
      const before = await statementCalls(query, ['%"public"."customers"%']);

      await db.customers.list({ limit: 1 });

      calls = request.snapshot().calls;
      delta =
        (await statementCalls(query, ['%"public"."customers"%'])) - before;

      if ((await deallocs(pool)) === evictions) {
        break;
      }
    }

    expect(calls).toBe(1);
    expect(delta).toBe(calls);
  });
});
