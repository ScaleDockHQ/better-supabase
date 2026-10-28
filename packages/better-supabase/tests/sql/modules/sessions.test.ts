import { describe, expect, it } from "vitest";

import type { BlockConfig } from "../../../src/config/blocks.ts";

import { moduleBody } from "../../../src/sql/render.ts";

const sessions = (config: BlockConfig = {}) =>
  moduleBody("sessions", { modules: { sessions: config } })!;

describe("sessions bootstrap wrappers", () => {
  it("renders nothing without the option", () => {
    expect(sessions()).not.toContain("bootstrap_");
  });

  it("renders one wrapper per entry that checks the session first", async () => {
    const sql = sessions({
      options: { bootstrap: { home: "app.home_data", inbox: "app.inbox" } },
    });

    expect(sql).toContain(
      "create or replace function better_supabase.bootstrap_home(args jsonb default '{}'::jsonb)",
    );
    expect(sql).toContain("'data', to_jsonb(app.home_data(args))");
    expect(sql).toContain("'data', to_jsonb(app.inbox(args))");
    expect(sql).toContain(
      "if not (select better_supabase.session_active()) then",
    );
    expect(sql).toContain("security invoker");
    expect(sql).toContain(
      "revoke execute on function better_supabase.bootstrap_home(jsonb) from public, anon;",
    );
    await expect(
      sql.slice(sql.indexOf("-- blocks['sessions'].options.bootstrap")),
    ).toMatchFileSnapshot("../__golden__/sessions-bootstrap.sql");
  });

  it("rejects a name or a function it can't render safely", () => {
    expect(() => sessions({ options: { bootstrap: ["app.home"] } })).toThrow(
      /must map names to functions/,
    );
    expect(() =>
      sessions({ options: { bootstrap: { Home: "app.home_data" } } }),
    ).toThrow(/lowercase name/);
    expect(() =>
      sessions({ options: { bootstrap: { home: "home_data(); drop" } } }),
    ).toThrow(/schema\.function/);
  });
});

describe("sessions authorization versions", () => {
  it("renders nothing without the option", () => {
    expect(sessions()).not.toContain("user_authz_versions");
  });

  it("renders the table, the bump trigger and both broadcasts", async () => {
    const sql = sessions({ options: { authzVersions: true } });

    expect(sql).toContain(
      "create table if not exists better_supabase.user_authz_versions (",
    );
    expect(sql).toContain("'better_supabase:authz'");
    expect(sql).toContain("'authz:' || new.user_id::text");
    expect(sql).toContain(
      "(select realtime.topic()) = 'authz:' || (select auth.uid())::text",
    );
    expect(sql).toContain(
      "revoke all on better_supabase.user_authz_versions from public, anon, authenticated;",
    );
    await expect(
      sql.slice(sql.indexOf("-- blocks['sessions'].options.authzVersions")),
    ).toMatchFileSnapshot("../__golden__/sessions-authz-versions.sql");
  });
});
