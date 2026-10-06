import { describe, expect, it } from "vitest";

import {
  moduleBody,
  modulePermissionKeys,
  resolveModules,
} from "../../../src/sql/registry.ts";

describe("webhooks-in module", () => {
  it("stores hashed tokens, hides secrets and checks the access contract", () => {
    const sql = moduleBody("webhooks-in", {
      modules: {
        "webhooks-in": {
          permissions: { manage: "integrations.manage" },
          options: { maxBodyBytes: 65_536 },
        },
      },
    })!;
    expect(sql).toContain(
      'create table if not exists "better_supabase"."incoming_webhooks"',
    );
    expect(sql).toContain("token_hash text not null unique");
    expect(sql).toContain("default 65536 check (max_body_bytes > 0)");
    expect(sql).toContain("'integrations.manage'");
    expect(sql).toContain("tenant_ids_with('webhooks.read')");
    expect(sql).not.toMatch(/grant select \([^)]*\bsecret\b/);
    expect(sql).toContain(
      'grant execute on function "better_supabase"."incoming_webhook_by_token"(text) to service_role;',
    );
  });

  it("installs after access and the webhook inbox and lists its keys", () => {
    expect(resolveModules(["webhooks-in"]).map((m) => m.name)).toEqual([
      "updated-at",
      "tenant",
      "webhook-inbox",
      "access",
      "webhooks-in",
    ]);
    expect(
      modulePermissionKeys({}, ["webhooks-in"]).filter(
        (entry) => entry.module === "webhooks-in",
      ),
    ).toEqual([
      {
        module: "webhooks-in",
        action: "manage",
        key: "webhooks.manage",
        scope: "tenant",
      },
      {
        module: "webhooks-in",
        action: "view",
        key: "webhooks.read",
        scope: "tenant",
      },
    ]);
  });
});
