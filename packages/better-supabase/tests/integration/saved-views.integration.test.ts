import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../src/sql/module-types.ts";

import { createSavedViews } from "../../src/blocks/saved-views/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import {
  BlockSession,
  dbUrl,
  reachable,
  type TestUser,
} from "./block-session.ts";

const live = await reachable();

const layout: ModuleLayout = {
  modules: { "saved-views": { schema: "sv_it" } },
};

interface View {
  readonly id: string;
  readonly name: string;
  readonly scope: string;
  readonly isDefault: boolean;
}

describe.skipIf(!live)("saved views in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let db: BlockSession;
  let owner: TestUser;
  let member: TestUser;
  let outsider: TestUser;
  let org: string;
  let team: string;

  const save = (
    scope: string,
    name: string,
    extra: { team?: string | null; id?: string | null } = {},
  ): string =>
    `sv_it.save_view('${org}', 'tasks', '${name}', 'table', '${scope}', ${
      extra.team ? `'${extra.team}'` : "null"
    }, '{"query":{"q":"x"}}'::jsonb, ${extra.id ? `'${extra.id}'` : "null"})`;

  const views = async (user: TestUser): Promise<View[]> => {
    await db.asRole(user);
    const list = await db.value<View[]>(`sv_it.list_views('${org}', 'tasks')`);
    await db.service();
    return list;
  };

  beforeAll(async () => {
    db = await BlockSession.open(pool);
    await db.client.query("create schema sv_it");
    await db.install(
      ["organizations", "outbox", "teams", "saved-views"],
      layout,
    );
    owner = await db.user("owner");
    member = await db.user("member");
    outsider = await db.user("outsider");
    org = await db.organization(owner, { member, member2: outsider });
    await db.as(owner);
    team = (
      await db.value<{ id: string }>(
        `better_supabase.create_team('${org}', 'Design', null)`,
      )
    ).id;
    await db.value(
      `better_supabase.add_team_member('${team}', '${member.id}')`,
    );
    await db.value(`better_supabase.add_team_member('${team}', '${owner.id}')`);
  });

  afterAll(async () => {
    await db.close();
    await pool.end();
  });

  it("keeps a personal view to its owner", async () => {
    await db.as(member);
    const saved = await db.value<{ id: string; rank: string }>(
      save("user", "Mine"),
    );
    expect(saved.rank).toBe("V");
    expect((await views(member)).map((v) => v.name)).toEqual(["Mine"]);
    expect(await views(outsider)).toEqual([]);
    await db.as(outsider);
    expect(await db.hint(`sv_it.delete_view('${saved.id}')`)).toBe(
      "SAVED_VIEW_FORBIDDEN",
    );
  });

  it("needs views.share to share with the tenant", async () => {
    await db.as(member);
    expect(await db.hint(save("tenant", "Everyone"))).toBe(
      "SAVED_VIEW_FORBIDDEN",
    );
    await db.as(owner);
    await db.value(save("tenant", "Everyone"));
    expect((await views(outsider)).map((v) => v.name)).toEqual(["Everyone"]);
  });

  it("shows a team view only to the team's members", async () => {
    await db.as(owner);
    await db.value(save("team", "Design board", { team }));
    expect((await views(member)).map((v) => v.name)).toContain("Design board");
    expect((await views(outsider)).map((v) => v.name)).not.toContain(
      "Design board",
    );
    await db.as(owner);
    expect(await db.hint(save("team", "No team"))).toBe("SAVED_VIEW_INVALID");
  });

  it("keeps one default per slot", async () => {
    await db.as(member);
    const a = (await db.value<{ id: string }>(save("user", "A"))).id;
    const b = (await db.value<{ id: string }>(save("user", "B"))).id;
    await db.value(`sv_it.set_default_view('${a}', true)`);
    await db.value(`sv_it.set_default_view('${b}', true)`);
    const defaults = (await views(member)).filter((v) => v.isDefault);
    expect(defaults.map((v) => v.id)).toEqual([b]);
  });

  it("orders by rank key and rejects a bad key", async () => {
    await db.as(member);
    const id = (await db.value<{ id: string }>(save("user", "First"))).id;
    await db.value(`sv_it.rank_view('${id}', '0V')`);
    expect((await views(member))[0]?.name).toBe("First");
    expect(await db.hint(`sv_it.rank_view('${id}', 'bad!')`)).toBe(
      "SAVED_VIEW_RANK_INVALID",
    );
  });

  it("lets a member prefer, hide and pin a shared view they can't edit", async () => {
    await db.as(owner);
    const shared = (await db.value<{ id: string }>(save("tenant", "Shared")))
      .id;
    const other = (await db.value<{ id: string }>(save("tenant", "Other"))).id;
    await db.as(member);
    expect(await db.hint(`sv_it.set_default_view('${shared}', true)`)).toBe(
      "SAVED_VIEW_FORBIDDEN",
    );
    await db.value(`sv_it.set_view_preference('${other}', true, null, null)`);
    const pref = await db.value<Record<string, unknown>>(
      `sv_it.set_view_preference('${shared}', true, null, true)`,
    );
    expect(pref).toEqual({
      viewId: shared,
      isDefault: true,
      hidden: false,
      pinned: true,
    });
    await db.value(`sv_it.set_view_preference('${shared}', null, true, null)`);
    const mine = (await views(member)) as (View & {
      preference: Record<string, boolean>;
    })[];
    expect(mine.find((v) => v.id === shared)?.preference).toEqual({
      isDefault: true,
      hidden: true,
      pinned: true,
    });
    expect(mine.find((v) => v.id === other)?.preference["isDefault"]).toBe(
      false,
    );
    const theirs = (await views(outsider)) as (View & {
      preference: Record<string, boolean>;
    })[];
    expect(theirs.find((v) => v.id === shared)?.preference["isDefault"]).toBe(
      false,
    );
  });

  it("refuses a preference on a view the caller can't see", async () => {
    await db.as(member);
    const own = (await db.value<{ id: string }>(save("user", "Private"))).id;
    await db.as(outsider);
    expect(
      await db.hint(`sv_it.set_view_preference('${own}', true, null, null)`),
    ).toBe("SAVED_VIEW_NOT_FOUND");
    expect(
      await db.hint(`sv_it.duplicate_view('${own}', 'user', 'Stolen', null)`),
    ).toBe("SAVED_VIEW_NOT_FOUND");
  });

  it("duplicates a shared view as the caller's own and checks the new scope", async () => {
    await db.as(owner);
    const source = (await db.value<{ id: string }>(save("tenant", "Source")))
      .id;
    await db.as(member);
    const copy = await db.value<{ id: string }>(
      `sv_it.duplicate_view('${source}', 'user', 'My copy', null)`,
    );
    const mine = await views(member);
    expect(mine.find((v) => v.id === copy.id)).toMatchObject({
      name: "My copy",
      scope: "user",
    });
    await db.as(member);
    expect(
      await db.hint(
        `sv_it.duplicate_view('${source}', 'tenant', 'Again', null)`,
      ),
    ).toBe("SAVED_VIEW_FORBIDDEN");
  });

  it("saves and lists through the client", async () => {
    const client = createSavedViews({
      transport: sqlTransport(db.sql),
      schema: "sv_it",
    });
    await db.asRole(member);
    const saved = await client
      .save({
        organizationId: org,
        list: "deals",
        name: "Board",
        kind: "board",
        state: { grouping: ["stage"], query: { q: "acme" } },
      })
      .orThrow();
    const [view] = await client.list(org, "deals").orThrow();
    expect(view).toMatchObject({
      id: saved.id,
      kind: "board",
      scope: "user",
      ownerId: member.id,
      state: { grouping: ["stage"], query: { q: "acme" } },
    });
    await db.service();
  });

  it("records saved_view.saved", async () => {
    const rows = await db.rows<{ payload: Record<string, unknown> }>(
      "select payload from better_supabase.outbox_events where type = 'saved_view.saved' and organization_id = $1",
      [org],
    );
    expect(rows.length).toBeGreaterThan(0);
    expect(rows[0]?.payload).toMatchObject({
      organizationId: org,
      kind: "table",
    });
  });
});
