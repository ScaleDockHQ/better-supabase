import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("api wrappers", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("keep anon out under default privileges that grant every function", async () => {
    const s = await BlockSession.open(pool);
    try {
      const schema = `bs_api_${crypto.randomUUID().slice(0, 8)}`;
      await s.rows(
        `create schema ${schema};
         alter default privileges in schema ${schema} grant execute on functions to anon, authenticated, service_role;`,
      );
      const modules = ["webhooks-in", "webhooks-out", "settings"] as const;
      await s.install(["organizations", ...modules], {
        modules: Object.fromEntries(
          modules.map((name) => [name, { api: { schema } }]),
        ),
      });
      const rows = await s.rows<{
        name: string;
        wrapper_anon: boolean;
        source_anon: boolean;
        wrapper_authenticated: boolean;
        source_authenticated: boolean;
      }>(
        `select w.proname as name,
           has_function_privilege('anon', w.oid, 'execute') as wrapper_anon,
           has_function_privilege('anon', f.oid, 'execute') as source_anon,
           has_function_privilege('authenticated', w.oid, 'execute') as wrapper_authenticated,
           has_function_privilege('authenticated', f.oid, 'execute') as source_authenticated
         from pg_proc w
         join pg_proc f on f.proname = w.proname
           and f.pronamespace = 'better_supabase'::regnamespace
           and f.proargtypes = w.proargtypes
         where w.pronamespace = $1::regnamespace
         order by w.proname`,
        [schema],
      );
      expect(rows.length).toBeGreaterThan(10);
      expect(rows.filter((row) => !row.wrapper_anon).length).toBeGreaterThan(
        10,
      );
      for (const row of rows) {
        expect({ name: row.name, anon: row.wrapper_anon }).toEqual({
          name: row.name,
          anon: row.source_anon,
        });
        expect({
          name: row.name,
          authenticated: row.wrapper_authenticated,
        }).toEqual({
          name: row.name,
          authenticated: row.source_authenticated,
        });
      }
      await s.asRole("anon");
      expect(
        await s.hint(`${schema}.list_incoming_webhooks(gen_random_uuid())`),
      ).toMatch(/permission denied/);
    } finally {
      await s.close();
    }
  });
});
