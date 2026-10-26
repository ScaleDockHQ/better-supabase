import { describe, expect, it, vi } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";

import { ok } from "../../src/core/result.ts";
import {
  powersyncProfilesTransport,
  profilesRoute,
} from "../../src/powersync/index.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { createSqlite } from "../fixtures/sqlite.ts";

const DDL = [
  `create table profiles (id text primary key, email text, full_name text, locale text,
    active_organization_id text, onboarding text, created_at text, updated_at text)`,
];

function setup() {
  const sqlite = createSqlite({ ...schema.meta, tables: {} }, DDL);

  sqlite.sqlite.exec(`
    insert into profiles values ('u1', 'ada@example.com', 'Ada', 'en', 'o1', '{"step":1}',
      '2026-01-01 10:00:00.000000Z', '2026-01-01 10:00:00.000000Z');
  `);

  const server: BlockTransport = { call: vi.fn(async () => "server") };

  return {
    sqlite,
    transport: powersyncProfilesTransport(sqlite.db, { server }),
  };
}

describe("powersyncProfilesTransport", () => {
  it("reads the synced profile with parsed JSON and timestamps", async () => {
    const { transport } = setup();

    await expect(
      transport.call("better_supabase", "my_profile", {}),
    ).resolves.toMatchObject({
      id: "u1",
      full_name: "Ada",
      onboarding: { step: 1 },
      created_at: "2026-01-01T10:00:00+00:00",
    });
  });

  it("updates the columns a user may set and leaves the rest", async () => {
    const { transport, sqlite } = setup();

    await expect(
      transport.call("better_supabase", "update_my_profile", {
        attrs: {
          full_name: "Ada L.",
          onboarding: { step: 2 },
          email: "x@example.com",
          active_organization_id: "o2",
          missing: 1,
        },
      }),
    ).resolves.toBe(true);

    expect(
      sqlite.sqlite
        .prepare(
          "select full_name, onboarding, email, active_organization_id from profiles",
        )
        .all(),
    ).toEqual([
      {
        full_name: "Ada L.",
        onboarding: '{"step":2}',
        email: "ada@example.com",
        active_organization_id: "o1",
      },
    ]);
  });
});

describe("profilesRoute", () => {
  it("replays an edit through updateMine without the server-set columns", async () => {
    const profiles = { updateMine: vi.fn(async () => ok(true)) };

    await profilesRoute(profiles)({
      op: "PATCH",
      table: "profiles",
      id: "u1",
      opData: {
        full_name: "Ada L.",
        onboarding: '{"step":2}',
        updated_at: "x",
      },
    });

    expect(profiles.updateMine).toHaveBeenCalledWith({
      full_name: "Ada L.",
      onboarding: { step: 2 },
    });
  });

  it("refuses an insert or delete", async () => {
    const route = profilesRoute({ updateMine: vi.fn() });
    const result = await route({ op: "DELETE", table: "profiles", id: "u1" });

    expect(result.ok ? undefined : result.error.kind).toBe("unsupported");
  });
});
