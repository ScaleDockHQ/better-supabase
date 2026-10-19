import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { moduleBody, renderModules } from "../../../src/sql/render.ts";

const body = (modules: AnyBlocksConfig = {}) =>
  moduleBody("domains", { modules })!;

const fn = (name: string) => `"better_supabase"."${name}"`;

describe("domains module", () => {
  it("keeps one verified owner per hostname and one primary per organization", () => {
    const sql = body();

    expect(sql).toContain(
      'create table if not exists "better_supabase"."organization_hostnames"',
    );
    expect(sql).toContain(
      'on "better_supabase"."organization_hostnames" ("hostname") where "verified_at" is not null;',
    );
    expect(sql).toContain(
      'on "better_supabase"."organization_hostnames" ("organization_id") where "is_primary";',
    );
    expect(sql).toContain(
      'check (not "is_primary" or "verified_at" is not null)',
    );
    expect(sql).toContain(
      'revoke all on "better_supabase"."organization_hostnames" from anon, authenticated;',
    );
  });

  it("never returns the token outside the TXT record", () => {
    const sql = body();

    expect(sql).toContain("(to_jsonb(v_row) - 'verification_token')");
    expect(sql).toContain(
      "'_better-supabase.' || v_row.\"hostname\", 'value', 'better-supabase-hostname-verification=' || v_row.\"verification_token\"",
    );
  });

  it("verifies only with the service role, and resolves for anon", () => {
    const sql = body();

    expect(sql).toContain(
      `revoke execute on function ${fn("verify_hostname")}(uuid, uuid) from public, anon, authenticated;`,
    );
    expect(sql).toContain(
      `grant execute on function ${fn("verify_hostname")}(uuid, uuid) to service_role;`,
    );
    expect(sql).toContain(
      `grant execute on function ${fn("resolve_hostname")}(text) to anon, authenticated, service_role;`,
    );
    expect(sql).toContain('and x."verified_at" is not null\n$$;');
  });

  it("checks the domains permissions", () => {
    const sql = body();

    expect(sql).toContain("'domains.manage'");
    expect(sql).toContain("'domains.read'");
    expect(sql).toContain(
      "better_supabase.can_user(verify_hostname.actor, 'tenant'",
    );
  });

  it("treats one label below platformDomain as a verified subdomain", () => {
    const sql = body({ domains: { options: { platformDomain: "Acme.App" } } });

    expect(sql).toContain("if v_hostname = 'acme.app' then");
    expect(sql).toContain("if right(v_hostname, 9) = '.acme.app' then");
    expect(sql).toContain("hint = 'HOSTNAME_RESERVED'");
    expect(body()).not.toContain("v_kind := 'subdomain'");
  });

  it("checks reserved slugs for subdomains when that module is installed", () => {
    const sql = renderModules(["domains", "reserved-slugs"], {
      modules: { domains: { options: { platformDomain: "acme.app" } } },
    })
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain("better_supabase.slug_problem(v_label)");
  });

  it("rejects a platformDomain or txtPrefix that isn't valid", () => {
    expect(() =>
      body({ domains: { options: { platformDomain: "not a domain" } } }),
    ).toThrow(/platformDomain/);
    expect(() =>
      body({ domains: { options: { txtPrefix: "verify" } } }),
    ).toThrow(/txtPrefix/);
  });

  it("uses a custom txtPrefix in the record", () => {
    expect(
      body({ domains: { options: { txtPrefix: "_acme-verify" } } }),
    ).toContain("'_acme-verify.' || v_row.\"hostname\"");
  });
});
