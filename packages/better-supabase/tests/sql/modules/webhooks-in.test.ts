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

  it("keeps signing secrets in Vault unless secretStorage is column", () => {
    const vault = moduleBody("webhooks-in")!;
    expect(vault).toContain("vault.create_secret(secret,");
    expect(vault).toContain(
      "left join vault.decrypted_secrets ds on ds.id = e.secret_id",
    );
    expect(vault).toContain(
      "delete from vault.secrets vs where vs.id = old.secret_id;",
    );
    const column = moduleBody("webhooks-in", {
      modules: { "webhooks-in": { options: { secretStorage: "column" } } },
    })!;
    expect(column).not.toContain("vault.");
    expect(() =>
      moduleBody("webhooks-in", {
        modules: { "webhooks-in": { options: { secretStorage: "kms" } } },
      }),
    ).toThrow(/secretStorage/);
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
      ...["create", "update", "delete"].map((action) => ({
        module: "webhooks-in",
        action,
        key: "webhooks.manage",
        scope: "tenant",
      })),
      {
        module: "webhooks-in",
        action: "view",
        key: "webhooks.read",
        scope: "tenant",
      },
    ]);
  });

  it("checks create, update and delete keys, with manage as their shorthand", () => {
    const keys = (permissions: Record<string, string>) =>
      modulePermissionKeys({ "webhooks-in": { permissions } }, ["webhooks-in"])
        .filter((entry) => entry.module === "webhooks-in")
        .map((entry) => [entry.action, entry.key]);
    expect(keys({ manage: "hooks.admin", delete: "hooks.delete" })).toEqual([
      ["create", "hooks.admin"],
      ["update", "hooks.admin"],
      ["delete", "hooks.delete"],
      ["view", "webhooks.read"],
    ]);
    const sql = moduleBody("webhooks-in", {
      modules: {
        "webhooks-in": {
          permissions: {
            create: "hooks.create",
            update: "hooks.update",
            delete: "hooks.delete",
          },
        },
      },
    })!;
    const fn = (name: string) =>
      sql
        .slice(sql.indexOf(`function "better_supabase"."${name}"(`))
        .split("\n$$;")[0]!;
    expect(fn("create_incoming_webhook")).toContain("'hooks.create'");
    expect(fn("rotate_incoming_webhook")).toContain("'hooks.update'");
    expect(fn("set_incoming_webhook_enabled")).toContain("'hooks.update'");
    expect(fn("delete_incoming_webhook")).toContain("'hooks.delete'");
    expect(sql).not.toContain("'webhooks.manage'");
  });

  it("updates name, metadata and verification with the update key", () => {
    const sql = moduleBody("webhooks-in", {
      modules: { "webhooks-in": { permissions: { update: "hooks.update" } } },
    })!;
    const update = sql.slice(
      sql.indexOf('function "better_supabase"."update_incoming_webhook"('),
    );
    expect(update).toContain("'hooks.update'");
    expect(update).toContain("hint = 'WEBHOOK_IN_NOT_FOUND'");
    expect(update).toContain("hint = 'WEBHOOK_IN_VERIFY_UNKNOWN'");
    expect(update).toContain(
      "if v_verify <> previous.verify and previous.secret_id is not null then",
    );
    expect(sql).toContain(
      'grant execute on function "better_supabase"."update_incoming_webhook"(uuid, text, jsonb, text, text) to authenticated, service_role;',
    );
  });
});
