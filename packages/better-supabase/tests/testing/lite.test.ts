import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { createServer } from "../../src/server/server.ts";
import { signTestJwt } from "../../src/testing/jwt.ts";
import { liteStack } from "../../src/testing/lite.ts";
import { schema } from "../fixtures/generated-camel.ts";

const ALICE = "11111111-1111-4111-8111-111111111111";
const BOB = "22222222-2222-4222-8222-222222222222";

const CONTACTS = `
create table public.contacts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  email text not null,
  full_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.contacts enable row level security;
grant select, insert, update, delete on public.contacts to authenticated;
create policy own_contacts on public.contacts for all to authenticated
  using (organization_id = auth.uid()) with check (organization_id = auth.uid());
`;

const COUNT_FUNCTION = `
create function public.contact_count() returns bigint
  language sql stable security invoker
  as $$ select count(*) from public.contacts $$;
grant execute on function public.contact_count() to authenticated;
`;

const SEED = `
insert into public.contacts (organization_id, email) values
  ('${ALICE}', 'a1@acme.test'),
  ('${ALICE}', 'a2@acme.test'),
  ('${BOB}', 'b1@globex.test');
`;

const betterSupabase = defineSupabase(schema);

/** Booting Lite on PGlite takes seconds, more under coverage. */
const BOOT = { timeout: 30_000 };

describe.each(["sqlite-postgres", "pglite"] as const)(
  "liteStack (%s)",
  BOOT,
  (driver) => {
    it("applies the schema and seed, and enforces RLS for asUser", async () => {
      await using stack = await liteStack({
        driver,
        schemas: [CONTACTS],
        seed: SEED,
      });

      const alice = await stack.asUser(betterSupabase, { sub: ALICE });

      const rows = await alice.db.contacts
        .list({ select: ["email"], orderBy: { email: "asc" } })
        .orThrow();

      expect(rows.map((row) => row.email)).toEqual([
        "a1@acme.test",
        "a2@acme.test",
      ]);

      const denied = await alice.db.contacts.create({
        organizationId: BOB,
        email: "x@globex.test",
      });

      expect(denied.error?.kind).toBe("forbidden");

      const { data: anon } = await stack.supabase.from("contacts").select("id");
      expect(anon).toEqual([]);

      const { count } = await stack.admin
        .from("contacts")
        .select("id", { count: "exact", head: true });

      expect(count).toBe(3);
    });

    it("verifies Lite's HS256 tokens in createServer with backend lite", async () => {
      await using stack = await liteStack({
        driver,
        schemas: [CONTACTS],
        seed: SEED,
      });

      const server = createServer(betterSupabase, {
        env: stack.env,
        backend: "lite",
        liteDriver: driver,
        fetch: stack.fetch,
      });

      const token = await signTestJwt(stack.jwtSecret, { sub: BOB });

      const ctx = await server.context(
        new Request("https://api.test/", {
          headers: { authorization: `Bearer ${token}` },
        }),
      );

      expect(ctx.auth.kind).toBe("user");
      expect(await ctx.db.contacts.count().orThrow()).toBe(1);

      const forged = await signTestJwt("not-the-lite-secret-0123456789abcdef", {
        sub: BOB,
      });

      const rejected = await server.context(
        new Request("https://api.test/", {
          headers: { authorization: `Bearer ${forged}` },
        }),
      );

      expect(rejected.auth.kind).toBe("invalid");
    });
  },
);

describe("rpc on Supabase Lite", BOOT, () => {
  it("returns unsupported on SQLite without a request", async () => {
    await using stack = await liteStack({ schemas: [CONTACTS] });
    let requests = 0;

    const server = createServer(betterSupabase, {
      env: stack.env,
      backend: "lite",
      fetch: (input, init) => {
        requests += 1;

        return stack.fetch(input, init);
      },
    });

    const token = await signTestJwt(stack.jwtSecret, { sub: ALICE });

    const ctx = await server.context(
      new Request("https://api.test/", {
        headers: { authorization: `Bearer ${token}` },
      }),
    );

    const result = await ctx.db.$rpc("customer_note_counts", {});
    expect(result.error).toMatchObject({
      kind: "unsupported",
      status: 501,
      code: "RPC_UNAVAILABLE",
    });
    expect(result.error?.message).toContain("sqlite-postgres");
    expect(requests).toBe(0);
  });

  it("calls functions on PGlite", async () => {
    await using stack = await liteStack({
      driver: "pglite",
      schemas: [CONTACTS, COUNT_FUNCTION],
      seed: SEED,
    });

    const { data, error } = await stack.admin.rpc("contact_count");
    expect(error).toBeNull();
    expect(Number(data)).toBe(3);
  });
});

describe("createServer backend lite", BOOT, () => {
  it("needs SUPABASE_JWT_SECRET to verify tokens", async () => {
    await using stack = await liteStack();
    const { jwtSecret: _secret, ...env } = stack.env;
    const server = createServer(betterSupabase, { env, backend: "lite" });
    await expect(
      server.context(new Request("https://api.test/")),
    ).rejects.toThrow("SUPABASE_JWT_SECRET");
  });

  it("refuses direct Postgres on a driver without one", () => {
    expect(() =>
      createServer(betterSupabase, {
        backend: "lite",
        liteDriver: "pglite",
        // SAFETY: never used; the server throws before reading it.
        postgres: {} as never,
      }),
    ).toThrow('[db] driver = "postgres"');
  });
});
