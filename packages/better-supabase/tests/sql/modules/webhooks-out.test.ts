import { describe, expect, it } from "vitest";

import type { KitsConfig } from "../../../src/config/kits.ts";

import {
  customContracts,
  moduleBody,
  renderKit,
} from "../../../src/sql/kit.ts";

const body = (kits: KitsConfig = {}) => moduleBody("webhooks-out", { kits })!;

const CENTRAKIT: KitsConfig = {
  "webhooks-out": {
    mode: "adopt",
    schema: "public",
    idType: "uuid",
    columns: {
      endpoints: {
        failingSince: null,
        disabledAt: null,
        disabledReason: null,
      },
      secrets: { expiresAt: null, vaultId: null },
      deliveries: { run: "workflow_run_id" },
    },
    options: {
      secretStorage: "column",
      eventIdType: "uuid",
      runIdType: "uuid",
    },
  },
};

describe("webhooks-out module", () => {
  it("owns its tables, keeps secrets in Vault and the secrets table closed to clients", () => {
    const sql = body();
    expect(sql).toContain(
      'create table if not exists "better_supabase"."webhook_endpoints" (',
    );
    expect(sql).toContain('"event_types" text[]');
    expect(sql).toContain('"vault_secret_id" uuid');
    expect(sql).toContain(`"url" ~* '^https://'`);
    expect(sql).toContain("webhook_deliveries_endpoint_event_idx");
    expect(sql).toContain("vault.create_secret(");
    expect(sql).toContain("vault.decrypted_secrets");
    expect(sql).not.toMatch(
      /grant [^;]*"webhook_endpoint_secrets" to authenticated/,
    );
    expect(sql).toMatch(
      /function "better_supabase"\."publish_webhook_event"\(/,
    );
    expect(sql).toContain("starts_with(");
    expect(sql).toContain("security definer");
  });

  it("adopts CentraKit's tables with plain secrets and uuid ids", () => {
    const sql = body(CENTRAKIT);
    expect(sql).not.toContain("create table if not exists");
    expect(sql).not.toContain("vault.");
    expect(sql).not.toContain('"failing_since"');
    expect(sql).not.toContain('"expires_at"');
    expect(sql).toContain('"public"."webhook_endpoint_secrets"');
    expect(sql).toContain('"workflow_run_id"');
    expect(sql).toContain("dispatch_webhook.run_id::uuid");
    expect(sql).toContain("publish_webhook_event.event_id::uuid");
  });

  it("allows http when asked and grants clients access through the access model", () => {
    expect(
      body({ "webhooks-out": { options: { allowHttp: true } } }),
    ).not.toContain(`"url" ~* '^https://'`);
    const plain = renderKit(["webhooks-out"]).at(-1)!.contents;
    expect(plain).not.toContain("better_supabase.can(");
    const sql = renderKit(["access", "outbox", "webhooks-out"]).find((file) =>
      file.path.includes("webhooks_out"),
    )!.contents;
    expect(sql).toContain("better_supabase.can('tenant', ");
    expect(sql).toContain("'webhooks.manage'");
    expect(sql).toContain("'webhooks.read'");
    expect(sql).toContain("emit_event('webhook.disabled'");
  });

  it("rejects options it would splice into SQL or can't honor", () => {
    expect(() =>
      body({ "webhooks-out": { options: { secretStorage: "kms" } } }),
    ).toThrow(/secretStorage/);
    expect(() =>
      body({
        "webhooks-out": { options: { eventIdType: "uuid; drop table x" } },
      }),
    ).toThrow(/eventIdType/);
    expect(() =>
      body({ "webhooks-out": { options: { disableAfter: 1.5 } } }),
    ).toThrow(/disableAfter/);
    expect(() =>
      body({ "webhooks-out": { columns: { secrets: { vaultId: null } } } }),
    ).toThrow(/vaultId/);
  });

  it("disables an endpoint that keeps failing for disableAfter", () => {
    const sql = body({
      "webhooks-out": { options: { disableAfter: "3 days" } },
    });
    expect(sql).toContain('"failing_since" timestamptz');
    expect(sql).toContain("v_since <= now() - '3 days'::interval");
    expect(() =>
      body({ "webhooks-out": { options: { disableAfter: "soon" } } }),
    ).toThrow(/disableAfter/);
    const never = body({
      "webhooks-out": { columns: { endpoints: { failingSince: null } } },
    });
    expect(never).not.toContain("v_result := 'disabled'");
  });

  it("counts the attempt at claim and completes only under the lease", () => {
    const sql = body();
    expect(sql).toContain('"attempt" = v."attempt" + 1');
    expect(sql).toContain("max_attempts integer default 8");
    expect(sql).toContain(
      'drop function if exists "better_supabase"."claim_webhook_deliveries"(integer, interval);',
    );
    expect(sql).toContain('and v."attempt" = v_attempt');
    expect(sql).toContain(`and v."status" = 'delivering'`);
    expect(sql).toContain("return 'stale';");
    expect(sql).toContain("WEBHOOK_ATTEMPT_REQUIRED");
  });

  it("renders nothing in custom mode and lists the contract the app must provide", () => {
    const custom: KitsConfig = { "webhooks-out": { mode: "custom" } };
    expect(moduleBody("webhooks-out", { kits: custom })).toBe(undefined);
    const [contract] = customContracts(["webhooks-out"], { kits: custom });
    expect(contract!.functions.map((fn) => fn.name)).toEqual([
      "publish_webhook_event",
      "dispatch_webhook",
      "claim_webhook_deliveries",
      "complete_webhook_delivery",
      "redeliver_webhook",
      "rotate_webhook_secret",
      "webhook_secrets",
    ]);
  });
});
