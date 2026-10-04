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
      destinations: {
        failureCount: null,
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
      'create table if not exists "better_supabase"."webhook_destinations" (',
    );
    expect(sql).toContain('"event_kinds" text[]');
    expect(sql).toContain('"vault_secret_id" uuid');
    expect(sql).toContain(`"url" ~* '^https://'`);
    expect(sql).toContain("webhook_deliveries_destination_event_idx");
    expect(sql).toContain("vault.create_secret(");
    expect(sql).toContain("vault.decrypted_secrets");
    expect(sql).not.toMatch(
      /grant [^;]*"webhook_destination_secrets" to authenticated/,
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
    expect(sql).not.toContain('"consecutive_failures"');
    expect(sql).not.toContain('"expires_at"');
    expect(sql).toContain('"public"."webhook_destination_secrets"');
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
    expect(sql).toContain("'webhooks.view'");
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

  it("never disables a destination with disableAfter 0", () => {
    const sql = body({ "webhooks-out": { options: { disableAfter: 0 } } });
    expect(sql).not.toContain("WEBHOOK_DISABLED_AFTER");
    expect(sql).not.toContain("'disabled'");
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
