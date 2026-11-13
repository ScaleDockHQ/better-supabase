import { describe, expect, it } from "vitest";

import { modulePermissionKeys } from "../../../src/sql/introspect.ts";
import { resolveBlocks } from "../../../src/sql/registry.ts";
import { moduleBody, renderBlocks } from "../../../src/sql/render.ts";
import { entryOf } from "../../fixtures/block-entry.ts";
import { unnamedChecks } from "../unnamed-checks.ts";

describe("incoming-webhooks module", () => {
  it("stores hashed tokens, hides secrets and checks the access contract", () => {
    const sql = moduleBody("incoming-webhooks", {
      modules: {
        "incoming-webhooks": {
          permissions: { manage: "integrations.manage" },
          options: { maxBodyBytes: 65_536 },
        },
      },
    })!;

    expect(sql).toContain('create table "better_supabase"."incoming_webhooks"');
    expect(sql).toContain("token_hash text not null unique");
    expect(unnamedChecks(sql)).toContain(
      "default 65536 check (max_body_bytes > 0)",
    );
    expect(sql).toContain("'integrations.manage'");
    expect(sql).toContain("tenant_ids_with('webhooks.read')");
    expect(sql).not.toMatch(/grant select \([^)]*\bsecret\b/);
    expect(sql).toContain(
      'grant execute on function "better_supabase"."incoming_webhook_by_token"(text) to service_role;',
    );
  });

  it("keeps signing secrets in Vault unless secretStorage is column", () => {
    const vault = moduleBody("incoming-webhooks")!;
    expect(vault).toContain("vault.create_secret(secret,");
    expect(vault).toContain(
      'left join vault.decrypted_secrets ds on ds.id = e."secret_id"',
    );
    expect(vault).toContain(
      'delete from vault.secrets vs where vs.id in (old."secret_id", old."previous_secret_id");',
    );

    const column = moduleBody("incoming-webhooks", {
      modules: {
        "incoming-webhooks": { options: { secretStorage: "column" } },
      },
    })!;

    expect(column).not.toContain("vault.");
    expect(() =>
      moduleBody("incoming-webhooks", {
        modules: { "incoming-webhooks": { options: { secretStorage: "kms" } } },
      }),
    ).toThrow(/secretStorage/);
  });

  it("installs after access and the webhook inbox and lists its keys", () => {
    expect(resolveBlocks(["incoming-webhooks"]).map((m) => m.name)).toEqual([
      "updated-at",
      "memberships",
      "webhook-inbox",
      "permissions",
      "incoming-webhooks",
      "housekeeping",
    ]);
    expect(
      modulePermissionKeys({}, ["incoming-webhooks"]).filter(
        (entry) => entry.module === "incoming-webhooks",
      ),
    ).toEqual([
      ...["create", "update", "delete"].map((action) => ({
        module: "incoming-webhooks",
        action,
        key: "webhooks.manage",
        scope: "tenant",
      })),
      {
        module: "incoming-webhooks",
        action: "read",
        key: "webhooks.read",
        scope: "tenant",
      },
    ]);
  });

  it("checks create, update and delete keys, with manage as their shorthand", () => {
    const keys = (permissions: Record<string, string>) =>
      modulePermissionKeys({ "incoming-webhooks": { permissions } }, [
        "incoming-webhooks",
      ])
        .filter((entry) => entry.module === "incoming-webhooks")
        .map((entry) => [entry.action, entry.key]);

    expect(keys({ manage: "hooks.admin", delete: "hooks.delete" })).toEqual([
      ["create", "hooks.admin"],
      ["update", "hooks.admin"],
      ["delete", "hooks.delete"],
      ["read", "webhooks.read"],
    ]);

    const sql = moduleBody("incoming-webhooks", {
      modules: {
        "incoming-webhooks": {
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
    const sql = moduleBody("incoming-webhooks", {
      modules: {
        "incoming-webhooks": { permissions: { update: "hooks.update" } },
      },
    })!;

    const update = sql.slice(
      sql.indexOf('function "better_supabase"."update_incoming_webhook"('),
    );

    expect(update).toContain("'hooks.update'");
    expect(update).toContain("hint = 'INCOMING_WEBHOOK_NOT_FOUND'");
    expect(update).toContain("hint = 'INCOMING_WEBHOOK_VERIFY_UNKNOWN'");
    expect(update).toContain(
      'delete from vault.secrets vs where vs.id in (previous."secret_id", previous."previous_secret_id");',
    );
    expect(sql).toContain(
      'grant execute on function "better_supabase"."update_incoming_webhook"(uuid, text, jsonb, text, text) to authenticated, service_role;',
    );
  });

  it("rotates the secret with a grace window and keeps tokens apart", () => {
    const sql = moduleBody("incoming-webhooks")!;

    const rotate = sql.slice(
      sql.indexOf(
        'function "better_supabase"."rotate_incoming_webhook_secret"(',
      ),
    );

    expect(rotate).toContain(
      '"previous_secret_expires_at" = case when v_keep then now() + grace end',
    );
    expect(rotate).toContain("hint = 'INCOMING_WEBHOOK_NO_SECRET'");
    expect(rotate.slice(0, rotate.indexOf("$$;"))).not.toContain("token_hash");
    expect(sql).toContain(
      'case when e."previous_secret_expires_at" > now() then coalesce(dp.decrypted_secret, e."previous_secret") end',
    );
    expect(sql).toContain(
      'delete from vault.secrets vs where vs.id in (old."secret_id", old."previous_secret_id");',
    );

    const column = moduleBody("incoming-webhooks", {
      modules: {
        "incoming-webhooks": { options: { secretStorage: "column" } },
      },
    })!;

    expect(column).toContain(
      'case when e."previous_secret_expires_at" > now() then e."previous_secret" end',
    );
  });

  it("accepts a shared secret header mode with its own default header", () => {
    const sql = moduleBody("incoming-webhooks")!;
    expect(sql).toContain(
      "check (verify in ('none', 'standard-webhooks', 'hmac-sha256', 'shared-secret'))",
    );
    expect(sql).not.toContain("add constraint incoming_webhooks_verify_check");
    expect(sql).toContain(
      "when 'shared-secret' then coalesce(signature_header, null, 'x-webhook-secret')",
    );
    expect(sql).toContain(
      "when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')",
    );
  });

  const overApp = (
    columns: Record<string, string | null> = {},
    options: Record<string, unknown> = {},
  ) =>
    renderBlocks(["incoming-webhooks"], {
      ownTables: { "public.hooks": "app.sql" },
      modules: {
        "incoming-webhooks": {
          tables: { endpoints: "public.hooks" },
          columns: {
            endpoints: {
              tenant: "organization_id",
              tokenHash: "token_digest",
              secret: null,
              previousSecret: null,
              previousSecretId: null,
              previousSecretExpiresAt: null,
              receiveCount: null,
              lastReceivedAt: null,
              lastStatus: null,
              subjectType: null,
              subjectId: null,
              ...columns,
            },
          },
          ...entryOf(options),
        },
      },
    })
      .filter((file) => file.module === "incoming-webhooks")
      .map((file) => file.contents)
      .join("\n");

  it("runs over the app's endpoints table with renamed and missing columns", () => {
    const sql = overApp();
    expect(sql).not.toContain('create table if not exists "public"');
    expect(sql).not.toContain("create policy");
    expect(sql).not.toContain(
      'alter table "public"."hooks" enable row level security',
    );
    expect(sql).toContain('from "public"."hooks" e');
    expect(sql).toContain(
      "where e.\"token_digest\" = encode(extensions.digest(incoming_webhook_by_token.token, 'sha256'), 'hex')",
    );
    expect(sql).toContain('e."organization_id"::text');
    expect(sql).toContain('null::text, e."metadata"');
    expect(sql).toContain("hint = 'WEBHOOK_IN_NO_GRACE'");
    expect(sql).toContain("hint = 'INCOMING_WEBHOOK_SUBJECT_INVALID'");
    expect(sql).not.toContain('"receive_count"');
    expect(sql).toContain("'receive_count', 0");
    expect(sql).toContain(
      'delete from vault.secrets vs where vs.id in (old."secret_id");',
    );
  });

  it("refuses renames of its own table and subjects without subject columns", () => {
    expect(() =>
      moduleBody("incoming-webhooks", {
        modules: {
          "incoming-webhooks": { columns: { endpoints: { tenant: "org_id" } } },
        },
      }),
    ).toThrow(/declare your own table/);
    expect(() =>
      overApp({}, { on: { project: { table: "public.projects" } } }),
    ).toThrow(/subjectType and subjectId/);
    expect(() => overApp({ secretId: null })).toThrow(/secretId/);
    expect(
      overApp(
        { secret: "secret", secretId: null },
        { secretStorage: "column" },
      ),
    ).not.toContain("vault.");
  });
});
