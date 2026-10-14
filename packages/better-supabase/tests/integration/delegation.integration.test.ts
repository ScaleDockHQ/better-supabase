import { Pool } from "pg";
import * as v from "valibot";
import { afterAll, describe, expect, it } from "vitest";

import type { RequestContext } from "../../src/core/plugin.ts";

import { contextClaims } from "../../src/auth/delegation.ts";
import { createJobs } from "../../src/blocks/jobs/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("delegated jobs under RLS", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  /**
   * A posts table whose update policy asks the access functions for
   * `members.invite`, which only the `posts:write` scope maps to.
   */
  async function postsTable(
    session: BlockSession,
    organization: string,
  ): Promise<string> {
    const table = `delegation_posts_${crypto.randomUUID().slice(0, 8)}`;
    await session.service();
    await session.client.query(`
      create table public.${table} (id int primary key, organization_id uuid not null, title text not null);
      alter table public.${table} enable row level security;
      create policy read on public.${table} for select to authenticated using (true);
      create policy write on public.${table} for update to authenticated
        using (organization_id in (select better_supabase.tenant_ids_with('members.invite')))
        with check (organization_id in (select better_supabase.tenant_ids_with('members.invite')));
      grant select, update on public.${table} to authenticated;
      insert into public.${table} values (1, '${organization}', 'draft');
    `);
    return table;
  }

  /** Enqueues and claims a job through the jobs module, as a worker does. */
  async function roundTrip(
    session: BlockSession,
    context: RequestContext,
  ): Promise<RequestContext> {
    await session.service();
    const queue = `delegation_${crypto.randomUUID().slice(0, 8)}`;
    const jobs = createJobs(session.sql, {
      [queue]: v.object({ id: v.number() }),
    });
    await jobs.enqueue(queue, { id: 1 }, { context }).orThrow();
    const [job] = await jobs.claim(queue).orThrow();
    expect(job?.payload).toEqual({ id: 1 });
    return job!.context;
  }

  async function updateAs(
    session: BlockSession,
    table: string,
    context: RequestContext,
  ): Promise<number | null> {
    const built = contextClaims(context);
    if (!built.ok) throw new Error(built.message);
    const { sub, ...claims } = built.claims;
    await session.asRole({ id: sub, email: "worker@example.test" }, claims);
    const result = await session.client.query(
      `update public.${table} set title = 'published' where id = 1`,
    );
    return result.rowCount;
  }

  it("refuses a job queued with a read scope and runs one with the write scope", async () => {
    const session = await BlockSession.open(pool);
    try {
      await session.install(["actor", "access"], {
        modules: { access: { scopes: { "posts:write": ["members.invite"] } } },
      });
      const author = await session.user("author");
      const table = await postsTable(
        session,
        await session.organization(author),
      );
      const actor = { id: author.id, kind: "user" as const };

      const reader = await roundTrip(session, {
        actor,
        claims: { client_id: "mcp-client", scope: "posts:read" },
      });
      expect(reader.claims).toEqual({
        client_id: "mcp-client",
        scope: "posts:read",
      });
      expect(await updateAs(session, table, reader)).toBe(0);

      const chain = await roundTrip(session, {
        actor,
        claims: {
          act: { sub: "agent-1", act: { sub: "mcp-client" } },
          scope: ["posts:read"],
        },
      });
      expect(await updateAs(session, table, chain)).toBe(0);

      const writer = await roundTrip(session, {
        actor,
        claims: { client_id: "mcp-client", scope: "posts:read posts:write" },
      });
      expect(await updateAs(session, table, writer)).toBe(1);

      const own = await roundTrip(session, { actor, claims: {} });
      expect(own.claims).toBeUndefined();
      expect(await updateAs(session, table, own)).toBe(1);

      const capped = await roundTrip(session, {
        actor,
        claims: { bs_permission_cap: ["audit.read"] },
      });
      expect(capped.claims).toEqual({ bs_permission_cap: ["audit.read"] });
      expect(await updateAs(session, table, capped)).toBe(0);
    } finally {
      await session.close();
    }
  });

  it("answers token_scope_allows from the claims", async () => {
    const session = await BlockSession.open(pool);
    try {
      await session.install(["actor"]);
      const user = { id: crypto.randomUUID(), email: "scope@example.test" };
      const allows = async (claims: object, scope = "posts:write") => {
        await session.as(user, claims);
        return session.value<boolean>(
          "better_supabase.token_scope_allows($1)",
          [scope],
        );
      };
      expect(await allows({})).toBe(true);
      expect(await allows({ act: { kind: "support", sub: "a" } })).toBe(true);
      expect(await allows({ act: { kind: "impersonation", sub: "a" } })).toBe(
        true,
      );
      expect(await allows({ client_id: "c" })).toBe(false);
      expect(await allows({ client_id: "c", scope: "posts:write" })).toBe(true);
      expect(await allows({ client_id: "c", scope: " a  posts:write " })).toBe(
        true,
      );
      expect(await allows({ client_id: "c", scope: "posts:writer" })).toBe(
        false,
      );
      expect(await allows({ client_id: "c", scope: ["posts:write"] })).toBe(
        true,
      );
      expect(await allows({ client_id: "c", scope: [1] })).toBe(false);
      expect(await allows({ client_id: "c", scope: "posts:write" }, "")).toBe(
        false,
      );
      expect(await allows({ act: { sub: "client" } })).toBe(false);
      expect(await allows({ act: "client" })).toBe(false);
      expect(
        await allows({
          client_id: "c",
          act: { kind: "support", sub: "a" },
          scope: "x",
        }),
      ).toBe(false);
      await session.service();
      expect(
        await session.value<boolean>(
          "better_supabase.token_scope_allows('posts:write')",
        ),
      ).toBe(true);
    } finally {
      await session.close();
    }
  });
});
