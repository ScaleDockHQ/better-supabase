import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../src/sql/module-types.ts";

import {
  createSearch,
  searchSink,
  sqlTransport,
} from "../../src/blocks/search/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const layout = (dimensions = 0): ModuleLayout => ({
  subjects: {
    note: {
      table: "search_it.notes",
      title: "title",
      url: "/notes/{id}",
      deletedAt: "deleted_at",
      permissions: { read: "search.read" },
      search: { body: ["body"] },
    },
    tag_like: { table: "search_it.labels", title: "name", tenant: false },
  },
  modules: {
    search: { options: { config: "simple", dimensions } },
    ...(dimensions > 0 ? { "vector-search": {} } : {}),
  },
});

const TABLES = `create schema search_it;
create table search_it.notes (
  id text primary key,
  organization_id uuid not null,
  title text not null,
  body text,
  private boolean not null default false,
  deleted_at timestamptz
);
alter table search_it.notes enable row level security;
create policy notes_read on search_it.notes for select to authenticated
  using (not private and organization_id in (select better_supabase.tenant_ids_with('search.read')));
create table search_it.labels (id text primary key, name text not null);
grant usage on schema search_it to authenticated;
grant select on search_it.notes, search_it.labels to authenticated;`;

interface Hit {
  readonly subjectType: string;
  readonly subjectId: string;
  readonly title: string;
  readonly url: string | null;
  readonly snippet: string | null;
  readonly organizationId: string;
}

describe.skipIf(!live)("search", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("indexes rows through triggers and finds what the caller can read", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.client.query(TABLES);
      await s.install(["organizations", "share-links", "search"], layout());
      const owner = await s.user("owner");
      const member = await s.user("member");
      const tenant = await s.organization(owner, { member });
      const other = await s.organization(await s.user("other"));
      await s.service();
      await s.client.query(
        `insert into search_it.notes (id, organization_id, title, body, private) values
          ('n1', $1, 'Quarterly revenue report', 'Numbers from the café in Zürich', false),
          ('n2', $1, 'Roadmap', 'Revenue goals for next year', false),
          ('n3', $1, 'Salary revenue', null, true),
          ('n4', $2, 'Revenue of another company', null, false)`,
        [tenant, other],
      );
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.search_documents)",
        ),
      ).toBeGreaterThanOrEqual(4);

      const search = async (
        q: string,
        types: string[] | null = null,
      ): Promise<Hit[]> =>
        s.value<Hit[]>("better_supabase.search($1, $2)", [q, types]);

      await s.asRole(member);
      const revenue = await search("revenue");
      expect(revenue.map((hit) => hit.subjectId)).toEqual(["n1", "n2"]);
      expect(revenue[0]).toMatchObject({
        subjectType: "note",
        title: "Quarterly revenue report",
        url: "/notes/n1",
        organizationId: tenant,
      });
      expect((await search("cafe zurich"))[0]?.subjectId).toBe("n1");
      expect((await search("quar")).map((hit) => hit.subjectId)).toEqual([
        "n1",
      ]);
      expect((await search("roadmp"))[0]?.subjectId).toBe("n2");
      expect((await search('"revenue goals"'))[0]?.snippet).toContain(
        "Revenue goals",
      );
      expect(await search("revenue", ["other"])).toEqual([]);
      expect(await search("   ")).toEqual([]);
      expect(
        await s.hint("better_supabase.search($1)", ["x".repeat(300)]),
      ).toBe("SEARCH_QUERY_TOO_LONG");

      await s.service();
      await s.client.query(
        "update search_it.notes set title = 'Annual plan', deleted_at = null where id = 'n2'",
      );
      await s.client.query(
        "update search_it.notes set deleted_at = now() where id = 'n1'",
      );
      await s.asRole(member);
      expect((await search("revenue")).map((hit) => hit.subjectId)).toEqual([
        "n2",
      ]);
      expect((await search("annual"))[0]?.title).toBe("Annual plan");

      await s.service();
      await s.client.query(
        "update search_it.notes set deleted_at = null where id = 'n1'",
      );
      await s.client.query("delete from search_it.notes where id = 'n2'");
      await s.asRole(member);
      expect((await search("revenue")).map((hit) => hit.subjectId)).toEqual([
        "n1",
      ]);

      expect(await s.value("better_supabase.search_touch('note', 'n1')")).toBe(
        true,
      );
      expect(
        await s.value("better_supabase.search_star('note', 'n1', true)"),
      ).toBe(true);
      await s.value("better_supabase.search_touch('note', 'n3')");
      const recents = await s.value<{ subjectId: string; title: string }[]>(
        "better_supabase.search_recents()",
      );
      expect(recents.map((item) => item.subjectId)).toEqual(["n1"]);
      expect(recents[0]?.title).toBe("Quarterly revenue report");
      const favorites = await s.value<{ subjectId: string }[]>(
        "better_supabase.search_favorites()",
      );
      expect(favorites.map((item) => item.subjectId)).toEqual(["n1"]);
      await s.value("better_supabase.search_star('note', 'n1', false)");
      expect(await s.value("better_supabase.search_favorites()")).toEqual([]);

      await s.asRole("anon");
      expect(await s.hint("better_supabase.search($1)", ["revenue"])).toMatch(
        /permission denied/,
      );
      await s.client.query("reset role");
      await s.client.query(
        "select set_config('request.jwt.claims', '{\"role\":\"authenticated\"}', true)",
      );
      expect(await s.hint("better_supabase.search_touch('note', 'n1')")).toBe(
        "SEARCH_SIGNED_OUT",
      );

      const client = createSearch({ transport: sqlTransport(s.sql) });
      await s.asRole(member);
      expect(
        (
          await client.search("revenue", { organizationId: tenant }).orThrow()
        )[0],
      ).toMatchObject({ subjectId: "n1", url: "/notes/n1" });
      expect(
        (await client.favorites().orThrow()).map((item) => item.subjectId),
      ).toEqual([]);
      expect(await client.star("note", "n1").orThrow()).toBe(true);
      expect((await client.favorites().orThrow())[0]?.starredAt).toBeInstanceOf(
        Temporal.Instant,
      );

      await s.service();
      await searchSink(client).send([
        {
          specversion: "1.0",
          id: "e1",
          source: "/test",
          type: "dev.better-supabase.subject.trashed",
          data: { subjectType: "note", subjectId: "n1" },
        },
        {
          specversion: "1.0",
          id: "e2",
          source: "/test",
          type: "dev.better-supabase.subject.restored",
          data: { subjectType: "unknown", subjectId: "x" },
        },
      ]);
      await s.asRole(member);
      expect(await client.search("revenue").orThrow()).toEqual([]);

      await s.service();
      await s.client.query("truncate better_supabase.search_documents");
      expect(await s.value("better_supabase.search_reindex('note')")).toBe(3);
      expect(await client.remove("note", "n1").orThrow()).toBe(true);
      expect(await client.refresh("note", "n1").orThrow()).toBe(true);
    } finally {
      await s.close();
    }
  });

  it("fuses full-text and embedding ranks when the index keeps embeddings", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.client.query(TABLES);
      await s.install(["organizations", "vector-search", "search"], layout(3));
      // The fixture seed indexes its customers into the same table.
      await s.client.query("delete from better_supabase.search_documents");
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);
      await s.service();
      await s.client.query(
        `insert into search_it.notes (id, organization_id, title) values
          ('a', $1, 'Invoice template'), ('b', $1, 'Billing questions')`,
        [tenant],
      );
      const pending = await s.value<
        { subjectId: string; contentHash: string }[]
      >("better_supabase.search_pending_embeddings()");
      expect(pending.map((row) => row.subjectId).toSorted()).toEqual([
        "a",
        "b",
      ]);
      const client = createSearch({ transport: sqlTransport(s.sql) });
      expect(
        await client
          .embedPending(async (texts) =>
            texts.map((text) =>
              text.startsWith("Invoice") ? [1, 0, 0] : [0, 1, 0],
            ),
          )
          .orThrow(),
      ).toBe(pending.length);
      expect(
        await s.value("better_supabase.search_pending_embeddings()"),
      ).toEqual([]);

      await s.asRole(owner);
      const hits = await client
        .search("questions", { embedding: [0.1, 0.9, 0] })
        .orThrow();
      expect(hits.map((hit) => hit.subjectId)).toEqual(["b", "a"]);

      await s.service();
      await s.client.query(
        "update search_it.notes set title = 'Invoice layout' where id = 'a'",
      );
      expect(
        (
          await s.value<{ subjectId: string }[]>(
            "better_supabase.search_pending_embeddings()",
          )
        ).map((row) => row.subjectId),
      ).toEqual(["a"]);
    } finally {
      await s.close();
    }
  });
});
