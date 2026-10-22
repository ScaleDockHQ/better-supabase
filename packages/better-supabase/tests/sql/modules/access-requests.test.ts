import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { moduleProvider } from "../../fixtures/authorization-provider.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const sqlOf = (
  modules: readonly string[],
  module: string,
  layout: Layout = {},
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

const withOptions = (options: Record<string, unknown>): Layout => ({
  modules: { "access-requests": { options } },
});

describe("access-requests module", () => {
  it("files the request through approvals with its own policy", () => {
    const sql = sqlOf(["access-requests"], "access-requests");
    expect(sql).toContain(`"better_supabase"."open_approval"(`);
    expect(sql).toContain(
      `'{"steps":[{"approvers":{"permission":"members.update_role"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb`,
    );
    expect(sql).toContain("array['admin', 'member', 'viewer']::text[]");
    expect(sql).toContain("ACCESS_REQUEST_FORBIDDEN");
    expect(sql).toContain(
      `insert into "better_supabase"."memberships" ("organization_id", "user_id", "role")`,
    );
    expect(sql).toContain(
      `revoke execute on function "better_supabase"."grant_access_request"(uuid) from public, anon, authenticated;`,
    );
  });

  it("lets approvals grant the role on the final approval", () => {
    const sql = sqlOf(["access-requests"], "approvals");
    expect(sql).toContain(
      `perform "better_supabase"."grant_access_request"(v_req."subject_id"::uuid);`,
    );
    expect(sqlOf(["approvals"], "approvals")).not.toContain(
      "grant_access_request",
    );
  });

  it("caps the duration, limits roles and lets non-members ask to join", () => {
    const sql = sqlOf(
      ["access-requests"],
      "access-requests",
      withOptions({ maxDuration: "P1D", roles: ["admin"], join: true }),
    );

    expect(sql).toContain(
      "v_duration := coalesce(request_access.duration, 'P1D'::interval);",
    );
    expect(sql).toContain("array['admin']::text[]");
    expect(sql).not.toContain("only members can request a role");
  });

  it("leaves role changes to the provider's adapter", () => {
    const sql = sqlOf(["access-requests"], "access-requests", {
      modules: { permissions: { model: "provider" } },
      accessProvider: moduleProvider,
    });

    expect(sql).not.toContain(`insert into "better_supabase"."memberships"`);
    expect(sql).toContain("adapter grants the role from the event");
  });

  it("rejects bad options", () => {
    expect(() =>
      sqlOf(
        ["access-requests"],
        "access-requests",
        withOptions({ maxDuration: "1 day" }),
      ),
    ).toThrow("ISO 8601");
    expect(() =>
      sqlOf(["access-requests"], "access-requests", withOptions({ roles: [] })),
    ).toThrow("non-empty list");
    expect(() =>
      sqlOf(
        ["access-requests"],
        "access-requests",
        withOptions({
          policy: {
            steps: [{ approvers: { role: "admin" } }],
            run: { queue: "x" },
          },
        }),
      ),
    ).toThrow("policy.run is not allowed");
  });
});
