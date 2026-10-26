import { describe, expect, it, vi } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";

import { ok } from "../../src/core/result.ts";
import {
  powersyncTeamsTransport,
  teamMembersRoute,
  teamsRoute,
} from "../../src/powersync/index.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { createSqlite } from "../fixtures/sqlite.ts";

const DDL = [
  `create table teams (id text primary key, tenant_id text, name text, slug text, description text,
    status text, created_by text, created_at text, updated_at text)`,
  "create table team_members (id text primary key, team_id text, user_id text, tenant_id text, created_at text)",
];

function setup() {
  const sqlite = createSqlite({ ...schema.meta, tables: {} }, DDL);

  sqlite.sqlite.exec(`
    insert into teams (id, tenant_id, name, slug, status) values ('t1', 'o1', 'Sales', 'sales', 'active'),
      ('t2', 'o1', 'Design', 'design', 'active'), ('t3', 'o2', 'Other', 'other', 'active');
    insert into team_members values ('t1:u1', 't1', 'u1', 'o1', null);
  `);

  const call = vi.fn(async () => "server");
  const server: BlockTransport = { call };

  return {
    sqlite,
    call,
    transport: powersyncTeamsTransport(sqlite.db, { server }),
  };
}

const rows = (sqlite: ReturnType<typeof setup>["sqlite"], sql: string) =>
  sqlite.sqlite.prepare(sql).all();

describe("powersyncTeamsTransport", () => {
  it("lists an organization's synced teams by name", async () => {
    const { transport } = setup();

    await expect(
      transport.call("better_supabase", "list_teams", { tenant: "o1" }),
    ).resolves.toEqual([
      { id: "t2", name: "Design", slug: "design", status: "active" },
      { id: "t1", name: "Sales", slug: "sales", status: "active" },
    ]);
  });

  it("renames, archives and restores a team locally", async () => {
    const { transport, sqlite } = setup();

    await expect(
      transport.call("better_supabase", "update_team", {
        team: "t1",
        name: "Revenue",
        description: null,
        patch: { slug: "revenue" },
      }),
    ).resolves.toEqual({ id: "t1", name: "Revenue", slug: "revenue" });

    await transport.call("better_supabase", "archive_team", { team: "t2" });

    expect(
      rows(sqlite, "select id, slug, status from teams order by id"),
    ).toEqual([
      { id: "t1", slug: "revenue", status: "active" },
      { id: "t2", slug: "design", status: "archived" },
      { id: "t3", slug: "other", status: "active" },
    ]);

    await transport.call("better_supabase", "restore_team", { team: "t2" });

    expect(rows(sqlite, "select status from teams where id = 't2'")).toEqual([
      { status: "active" },
    ]);
  });

  it("adds and removes members with <team>:<user> ids", async () => {
    const { transport, sqlite } = setup();

    await transport.call("better_supabase", "add_team_member", {
      team: "t1",
      member: "u2",
    });
    await transport.call("better_supabase", "remove_team_member", {
      team: "t1",
      member: "u1",
    });

    expect(rows(sqlite, "select id, tenant_id from team_members")).toEqual([
      { id: "t1:u2", tenant_id: "o1" },
    ]);
  });

  it("sends creating a team to the server", async () => {
    const { transport, call } = setup();

    await transport.call("better_supabase", "create_team", {
      tenant: "o1",
      name: "New",
    });

    expect(call).toHaveBeenCalledOnce();
  });
});

describe("teamsRoute and teamMembersRoute", () => {
  const writes = () => ({
    update: vi.fn(async () => ok(true)),
    archive: vi.fn(async () => ok(true)),
    restore: vi.fn(async () => ok(true)),
    delete: vi.fn(async () => ok(true)),
    addMember: vi.fn(async () => ok(true)),
    removeMember: vi.fn(async () => ok(true)),
  });

  it("replays a status change and reads the kept name for a slug change", async () => {
    const { sqlite } = setup();
    const teams = writes();
    const route = teamsRoute(teams, sqlite.db);

    await route({
      op: "PATCH",
      table: "teams",
      id: "t1",
      opData: { status: "archived" },
    });
    await route({
      op: "PATCH",
      table: "teams",
      id: "t1",
      opData: { slug: "revenue" },
    });
    await route({ op: "DELETE", table: "teams", id: "t2" });

    expect(teams.archive).toHaveBeenCalledWith("t1");
    expect(teams.update).toHaveBeenCalledWith(
      "t1",
      "Sales",
      undefined,
      undefined,
      { slug: "revenue" },
    );
    expect(teams.delete).toHaveBeenCalledWith("t2");
  });

  it("refuses creating a team through the queue", async () => {
    const { sqlite } = setup();

    const result = await teamsRoute(
      writes(),
      sqlite.db,
    )({ op: "PUT", table: "teams", id: "t9", opData: { name: "New" } });

    expect(result.ok ? undefined : result.error.kind).toBe("unsupported");
  });

  it("replays member adds and removals", async () => {
    const teams = writes();
    const route = teamMembersRoute(teams);

    await route({ op: "PUT", table: "team_members", id: "t1:u2" });
    await route({ op: "DELETE", table: "team_members", id: "t1:u1" });

    expect(teams.addMember).toHaveBeenCalledWith("t1", "u2");
    expect(teams.removeMember).toHaveBeenCalledWith("t1", "u1");
  });
});
