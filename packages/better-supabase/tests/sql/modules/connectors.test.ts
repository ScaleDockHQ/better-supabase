import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import { moduleBody } from "../../../src/sql/registry.ts";

const body = (modules: ModulesConfig = {}) =>
  moduleBody("connectors", { modules })!;

describe("connectors module", () => {
  it("owns servers, grants, sessions and fingerprints", () => {
    const sql = body();
    for (const table of [
      "connector_servers",
      "connector_grants",
      "connector_sessions",
      "connector_tool_fingerprints",
    ]) {
      expect(sql).toContain(
        `create table if not exists "better_supabase"."${table}" (`,
      );
    }
  });

  it("keeps one active grant per user and server, holding only a credential_ref", () => {
    const sql = body();
    expect(sql).toContain("connector_grants_active_idx");
    expect(sql).toContain('"credential_ref" jsonb not null');
    expect(sql).not.toMatch(/access_token|refresh_token/);
  });

  it("allows plain http only to loopback unless allowHttp", () => {
    expect(body()).toContain("http://(localhost|127[.]0[.]0[.]1)");
    expect(body({ connectors: { options: { allowHttp: true } } })).toContain(
      "'^https?://'",
    );
  });

  it("trusts the first fingerprint unless trustFirstUse is off", () => {
    expect(body()).toContain("then 'pending' else 'approved' end");
    expect(
      body({ connectors: { options: { trustFirstUse: false } } }),
    ).not.toContain("else 'approved' end");
  });

  it("keeps grant writes and renewals to the service role", () => {
    const sql = body();
    for (const name of [
      "record_connector_grant",
      "expiring_connector_grants",
      "renew_connector_grant",
      "purge_connector_sessions",
    ]) {
      expect(sql).toMatch(
        new RegExp(
          `revoke execute on function "better_supabase"."${name}"\\([^)]*\\) from public, anon, authenticated`,
        ),
      );
    }
  });

  it("rejects a bad sessionTtl", () => {
    expect(() =>
      moduleBody("connectors", {
        modules: { connectors: { options: { sessionTtl: "soon" } } },
      }),
    ).toThrow(/sessionTtl/);
  });
});
