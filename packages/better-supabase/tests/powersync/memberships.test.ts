import { describe, expect, it, vi } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";

import { ok } from "../../src/core/result.ts";
import {
  membershipsRoute,
  powersyncMembershipsTransport,
} from "../../src/powersync/index.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { createSqlite } from "../fixtures/sqlite.ts";

const DDL = [
  "create table memberships (id text primary key, organization_id text, user_id text, role text, created_at text)",
  "create table organizations (id text primary key, name text, slug text, disabled_at text, deleted_at text)",
];

function setup() {
  const sqlite = createSqlite({ ...schema.meta, tables: {} }, DDL);

  sqlite.sqlite.exec(`
    insert into organizations values ('o1', 'Beta', 'beta', null, null), ('o2', 'Acme', 'acme', null, null),
      ('o3', 'Gone', 'gone', null, '2026-01-01T00:00:00Z');
    insert into memberships values ('o1:u1', 'o1', 'u1', 'admin', null), ('o2:u1', 'o2', 'u1', 'member', null),
      ('o3:u1', 'o3', 'u1', 'owner', null);
  `);

  const call = vi.fn(async () => "server");
  const server: BlockTransport = { call };

  return {
    sqlite,
    call,
    transport: powersyncMembershipsTransport(sqlite.db, { server }),
  };
}

describe("powersyncMembershipsTransport", () => {
  it("lists the user's organizations with their role, by name, without deleted ones", async () => {
    const { transport } = setup();

    await expect(
      transport.call("better_supabase", "list_my_organizations", {}),
    ).resolves.toEqual([
      { id: "o2", name: "Acme", slug: "acme", role: "member" },
      { id: "o1", name: "Beta", slug: "beta", role: "admin" },
    ]);
  });

  it("leaves an organization locally", async () => {
    const { transport, sqlite } = setup();

    await transport.call("better_supabase", "leave_organization", {
      organization: "o1",
    });

    expect(
      sqlite.sqlite.prepare("select id from memberships order by id").all(),
    ).toEqual([{ id: "o2:u1" }, { id: "o3:u1" }]);
  });

  it("sends every other function to the server", async () => {
    const { transport, call } = setup();

    await expect(
      transport.call("better_supabase", "switch_organization", {
        organization: "o1",
      }),
    ).resolves.toBe("server");

    expect(call).toHaveBeenCalledWith(
      "better_supabase",
      "switch_organization",
      { organization: "o1" },
    );
  });
});

describe("membershipsRoute", () => {
  const writes = () => ({
    leave: vi.fn(async () => ok(true)),
    updateMemberRole: vi.fn(async () => ok(true)),
  });

  it("replays a delete as leave and a role change as updateMemberRole", async () => {
    const organizations = writes();
    const route = membershipsRoute(organizations);

    await route({ op: "DELETE", table: "memberships", id: "o1:u1" });
    await route({
      op: "PATCH",
      table: "memberships",
      id: "o2:u1",
      opData: { role: "admin" },
    });

    expect(organizations.leave).toHaveBeenCalledWith("o1");
    expect(organizations.updateMemberRole).toHaveBeenCalledWith({
      organizationId: "o2",
      userId: "u1",
      role: "admin",
    });
  });

  it("refuses an insert and an id that isn't <organization>:<user>", async () => {
    const route = membershipsRoute(writes());

    const put = await route({ op: "PUT", table: "memberships", id: "o1:u1" });
    const bad = await route({ op: "DELETE", table: "memberships", id: "o1" });

    expect(put.ok ? undefined : put.error.kind).toBe("unsupported");
    expect(bad.ok ? undefined : bad.error.kind).toBe("unsupported");
  });
});
