import { Pool } from "pg";
import { afterAll, afterEach, beforeEach, describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";
import type { TestUser } from "./block-session.ts";

import { createOrganizations } from "../../src/blocks/organizations/index.ts";
import { createTags } from "../../src/blocks/tags/index.ts";
import { wrapTransport } from "../../src/core/block-hooks.ts";
import { blockNames } from "../../src/core/block-names.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

// Each app renders its blocks into its own schema inside a transaction that
// is rolled back, so the fixture's tenant-scoped blocks stay as they are.
const userApp = (scope: "user" | "none"): BlockSqlLayout => ({
  scope,
  modules: {
    tags: { schema: "scope_it" },
    timeline: { schema: "scope_it" },
    notifications: { schema: "scope_it" },
  },
});

describe.skipIf(!live)("blocks without organizations", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  let s: BlockSession;
  let ann: TestUser;
  let bob: TestUser;

  beforeEach(async () => {
    s = await BlockSession.open(pool);
    ann = await s.user("ann");
    bob = await s.user("bob");
  });

  afterEach(async () => {
    await s.close();
  });

  afterAll(async () => {
    await pool.end();
  });

  describe("per user", () => {
    beforeEach(async () => {
      await s.install(["tags", "activity", "notifications"], userApp("user"));
    });

    it("installs no tenant module or access contract", async () => {
      const modules = await s.rows<{ name: string }>(
        "select name from better_supabase.blocks where name in ('tags', 'activity', 'notifications') order by name",
      );

      expect(modules.map((row) => row.name)).toEqual([
        "activity",
        "notifications",
        "tags",
      ]);

      const nullable = await s.rows<{ table_name: string }>(
        `select table_name from information_schema.columns
         where table_schema = 'scope_it' and column_name in ('tenant_id', 'organization_id')
           and is_nullable = 'YES' order by table_name`,
      );

      expect(nullable.map((row) => row.table_name)).toEqual(
        expect.arrayContaining(["activity_entries", "tags"]),
      );
    });

    it("keeps each user's tags their own", async () => {
      let tenant = ann.id;

      const tags = createTags({
        transport: sqlTransport(s.sql),
        schema: "scope_it",
        tenant: () => tenant,
      });

      const note = { type: "note", id: "n1" };

      await s.as(ann);
      const urgent = await tags.create("label", "Urgent").orThrow();
      // Ann can't put a tag in Bob's set: the scope id is always the caller.
      tenant = bob.id;
      const other = await tags.create("label", "Later").orThrow();
      expect(
        await s.value<string>(
          "(select tenant_id::text from scope_it.tags where id = $1)",
          [other.id],
        ),
      ).toBe(ann.id);

      await s.as(bob);
      // The same name in Bob's own set is a different tag.
      const bobs = await tags.create("label", "Urgent").orThrow();
      expect(bobs.id).not.toBe(urgent.id);
      expect((await tags.update(urgent.id, "Mine")).ok).toBe(false);
      expect((await tags.tag(note, urgent.id)).ok).toBe(false);
      expect(await tags.tag(note, bobs.id).orThrow()).toBe(true);
      // Reads also stay in the caller's own set.
      expect((await tags.list("label").orThrow()).map((tag) => tag.id)).toEqual(
        [bobs.id],
      );
      tenant = ann.id;
      expect((await tags.list().orThrow()).map((tag) => tag.id)).toEqual([
        bobs.id,
      ]);
      tenant = bob.id;
      expect(
        (await tags.forSubject(note).orThrow()).map((tag) => tag.name),
      ).toEqual(["Urgent"]);
    });

    it("shows activity only to its own scope", async () => {
      await s.service();
      await s.value("scope_it.record_activity($1)", [
        {
          entries: [
            {
              event_id: "e1",
              organization_id: ann.id,
              type: "note.created",
              subject_type: "note",
              subject_id: "n1",
            },
          ],
        },
      ]);

      await s.asRole(ann);

      const feed = await s.value<{ type: string }[]>(
        "scope_it.list_activity(null, 'note', 'n1')",
      );

      expect(feed.map((entry) => entry.type)).toEqual(["note.created"]);

      await s.asRole(bob);
      expect(
        await s.value("scope_it.list_activity(null, 'note', 'n1')"),
      ).toEqual([]);
    });

    it("sends notifications without a tenant", async () => {
      await s.service();

      const id = await s.value<string | null>("scope_it.notify($1)", [
        {
          type: "note.shared",
          data: { title: "A note for you" },
          recipients: [bob.id],
        },
      ]);

      expect(id).toMatch(/^[0-9a-f-]{36}$/);
      await s.as(bob);

      const list = await s.value<{ type: string; tenant?: unknown }[]>(
        "scope_it.list_notifications()",
      );

      expect(list.map((item) => item.type)).toEqual(["note.shared"]);
      await s.as(ann);
      expect(await s.value("scope_it.list_notifications()")).toEqual([]);
    });
  });

  describe("in one shared space", () => {
    beforeEach(async () => {
      await s.install(["tags", "activity"], userApp("none"));
    });

    it("gives every signed-in user one set of tags and one activity feed", async () => {
      await s.as(ann);

      const tag = await s.value<{ id: string }>(
        "scope_it.create_tag($1, 'label', 'Shared', null, null)",
        [ann.id],
      );

      // The scope id is always null, so Bob's tag of the same name collides.
      await s.as(bob);
      expect(
        await s.hint(
          "select scope_it.create_tag(null, 'label', 'Shared', null, null)",
        ),
      ).toMatch(/duplicate key/);
      expect(
        await s.value<boolean>("scope_it.update_tag($1, 'Everyone')", [tag.id]),
      ).toBe(true);
      expect(
        await s.value<boolean>("scope_it.tag(null, 'note', 'n1', $1)", [
          tag.id,
        ]),
      ).toBe(true);

      await s.service();
      await s.value("scope_it.record_activity($1)", [
        { entries: [{ event_id: "e1", type: "note.created" }] },
      ]);
      await s.asRole(bob);

      const feed = await s.value<{ type: string }[]>(
        "scope_it.list_activity(null)",
      );

      expect(feed.map((entry) => entry.type)).toEqual(["note.created"]);
      await s.asRole("anon");
      expect(await s.hint("select 1 from scope_it.activity_entries")).toMatch(
        /GRANT SELECT ON scope_it.activity_entries TO anon/,
      );
    });
  });
});

describe.skipIf(!live)("a workspace-named app", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  let s: BlockSession;

  // The tenant tables go to their own schema; the tenant helpers and the
  // access contract are written to better_supabase under their new names
  // until the rollback.
  const layout: BlockSqlLayout = {
    modules: {
      memberships: { schema: "ws_it", entities: { organization: "workspace" } },
      permissions: { schema: "ws_it" },
      organizations: { schema: "ws_it" },
      tags: { schema: "ws_it" },
    },
  };

  beforeEach(async () => {
    s = await BlockSession.open(pool);
    await s.install(["organizations", "tags"], layout);
  });

  afterEach(async () => {
    await s.close();
  });

  afterAll(async () => {
    await pool.end();
  });

  it("names the tables, columns and functions after workspaces", async () => {
    const tables = await s.rows<{ table_name: string }>(
      "select table_name from information_schema.tables where table_schema = 'ws_it' and table_name like '%workspace%' order by 1",
    );

    expect(tables.map((row) => row.table_name)).toEqual(["workspaces"]);

    const columns = await s.rows<{ table_name: string }>(
      "select table_name from information_schema.columns where table_schema = 'ws_it' and column_name = 'workspace_id' order by 1",
    );

    expect(columns.map((row) => row.table_name)).toContain("memberships");
    expect(
      await s.rows(
        "select 1 from information_schema.columns where table_schema = 'ws_it' and column_name like '%organization%'",
      ),
    ).toEqual([]);
    expect(
      await s.value<boolean>(
        "to_regprocedure('better_supabase.member_workspace_ids(text[])') is not null",
      ),
    ).toBe(true);
    expect(
      await s.value<boolean>(
        "to_regprocedure('ws_it.create_organization(jsonb)') is null",
      ),
    ).toBe(true);
  });

  it("runs the organizations client through blockNames", async () => {
    const owner = await s.user("owner");

    const transport = wrapTransport(
      sqlTransport(s.sql),
      blockNames({ tenant: "workspace" }),
    );

    const workspaces = createOrganizations({ transport, schema: "ws_it" });
    await s.as(owner);

    const { id } = await workspaces
      .create({ name: "Acme", slug: `acme-${owner.id.slice(0, 8)}` })
      .orThrow();

    expect(
      await s.value<string>(
        "(select role from ws_it.memberships where workspace_id = $1 and user_id = $2)",
        [id, owner.id],
      ),
    ).toBe("owner");
    expect(
      await s.rows<{ user_id: string }>(
        "select user_id from ws_it.list_members($1)",
        [id],
      ),
    ).toEqual([{ user_id: owner.id }]);
    expect(
      await s.value<boolean>(
        "coalesce(better_supabase.can('tenant', $1::uuid, 'tags.manage'), false)",
        [id],
      ),
    ).toBe(true);

    const tags = createTags({ transport, schema: "ws_it", tenant: id });
    const tag = await tags.create("label", "Urgent").orThrow();
    expect(tag.name).toBe("Urgent");
  });
});
