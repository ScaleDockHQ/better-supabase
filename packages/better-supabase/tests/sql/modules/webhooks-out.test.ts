import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { ADOPTED_FORMAT_ERROR } from "../../../src/sql/modules/webhooks-out.ts";
import {
  customContracts,
  moduleBody,
  renderBlocks,
} from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";
import { moduleProvider } from "../../fixtures/authorization-provider.ts";

const body = (modules: AnyBlocksConfig = {}) =>
  moduleBody("webhooks-out", { modules })!;

const CENTRAKIT: AnyBlocksConfig = {
  "webhooks-out": {
    mode: "adopt",
    schema: "public",
    idType: "uuid",
    columns: {
      endpoints: { failingSince: null, disabledAt: null, disabledReason: null },
      secrets: { expiresAt: null, vaultId: null },
      deliveries: { run: "workflow_run_id" },
    },
    options: {
      secretStorage: "column",
      eventIdType: "uuid",
      runIdType: "uuid",
      defaultFormat: "standard",
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
    expect(sql).toContain('"event_types" && patterns');
    expect(sql).toContain("webhook_endpoints_types_idx");
    expect(sql).toContain(
      `"status" in ('succeeded', 'canceled')\n          or (purge_webhook_deliveries.include_dead and v."status" = 'dead')`,
    );
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
    const plain = renderBlocks(["webhooks-out"]).at(-1)!.contents;
    expect(plain).not.toContain("better_supabase.can(");
    expect(plain).not.toContain("tenant_ids_with(");

    const sql = renderBlocks(["permissions", "outbox", "webhooks-out"]).find(
      (file) => file.path.includes("webhooks_out"),
    )!.contents;

    expect(sql).toContain("better_supabase.can('tenant', ");
    expect(sql).toContain(
      `using (("organization_id" in (select better_supabase.tenant_ids_with('webhooks.manage'))) and (select better_supabase.actor_may_write()))`,
    );
    expect(sql).toContain("webhook_deliveries_tenant_created_idx");
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
    const custom: AnyBlocksConfig = { "webhooks-out": { mode: "custom" } };
    expect(moduleBody("webhooks-out", { modules: custom })).toBeUndefined();
    const [contract] = customContracts(["webhooks-out"], { modules: custom });
    expect(contract!.functions.map((fn) => fn.name)).toEqual([
      "publish_webhook_event",
      "publish_webhook_events",
      "dispatch_webhook",
      "claim_webhook_deliveries",
      "complete_webhook_delivery",
      "redeliver_webhook",
      "purge_webhook_deliveries",
      "rotate_webhook_secret",
      "webhook_secrets",
    ]);
  });

  describe("fan-out read check", () => {
    const publish = (sql: string) =>
      sql.slice(
        sql.indexOf('function "better_supabase"."publish_webhook_event"'),
        sql.indexOf("-- Sends one event to one endpoint"),
      );

    it("checks the endpoint owner with can_user and service endpoints with their declared permissions", () => {
      const sql = renderBlocks(["permissions", "outbox", "webhooks-out"]).find(
        (file) => file.contents.includes("publish_webhook_event"),
      )!.contents;

      const fn = publish(sql);
      expect(fn).toContain(
        "subject text default null, read_permission text default null",
      );
      expect(fn).toContain(
        "v_permission text := coalesce(nullif(publish_webhook_event.read_permission, ''), 'webhooks.read');",
      );
      expect(fn).toContain(
        `when d."created_by" is not null then coalesce(better_supabase.can_user(d."created_by", 'tenant', d."organization_id", v_permission), false)`,
      );
      expect(fn).toContain(
        `(publish_webhook_event.read_permission is null or coalesce(d."permissions" && v_held, false))`,
      );
      expect(fn).toContain('"subject")\n  select');
      expect(sql).toContain(
        'drop function if exists "better_supabase"."publish_webhook_event"(text, jsonb, uuid, text);',
      );
      expect(sql).toContain(
        `'subject', c."subject", 'owner', d."created_by", 'permissions', d."permissions", 'batch', d."batch"`,
      );
    });

    it("asks the authorization provider's idsWithFor when it has one", () => {
      const fn = publish(
        moduleBody("webhooks-out", {
          accessProvider: moduleProvider,
          modules: { permissions: { model: "provider" } },
        })!,
      );

      expect(fn).toContain(
        `d."organization_id"::text in (select t.id::text from authz.ids_organization_for(d."created_by", v_permission) as t(id))`,
      );
      expect(fn).not.toContain("can_user");
    });

    it("fails closed for user endpoints without the access module or a tenant", () => {
      expect(publish(body())).toContain(
        `when d."created_by" is not null then false else`,
      );

      const untenanted = publish(
        body({
          "webhooks-out": {
            mode: "adopt",
            columns: {
              endpoints: { tenant: null, permissions: null, batch: null },
              deliveries: { tenant: null, subject: null },
              secrets: { tenant: null },
            },
            options: { defaultFormat: "standard" },
          },
        }),
      );

      expect(untenanted).toContain(
        `when d."created_by" is not null then publish_webhook_event.read_permission is null else publish_webhook_event.read_permission is null end`,
      );

      const ownerless = publish(
        body({
          "webhooks-out": {
            mode: "adopt",
            columns: {
              endpoints: { createdBy: null, permissions: "held_permissions" },
            },
            options: { defaultFormat: "standard" },
          },
        }),
      );

      expect(ownerless).toContain(
        `and (publish_webhook_event.read_permission is null or coalesce(d."held_permissions" && v_held, false))`,
      );
      expect(
        publish(
          body({
            "webhooks-out": {
              mode: "adopt",
              options: { defaultFormat: "cloudevents" },
            },
          }),
        ),
      ).toContain("else publish_webhook_event.read_permission is null end");
    });

    it("leaves the new columns out of an adopted table unless they are mapped", () => {
      const sql = body(CENTRAKIT);
      expect(sql).not.toContain('"permissions"');
      expect(sql).not.toContain("add column if not exists");
      expect(sql).not.toContain("'subject', c.");
    });
  });

  describe("format", () => {
    const upgrade = (modules: AnyBlocksConfig = {}) =>
      upgradePlan([{ module: "webhooks-out", version: 2 }], { modules })[0]!
        .steps.map((step) => step.sql)
        .join("\n");

    it("defaults new endpoints to defaultFormat and keeps old ones on standard", () => {
      expect(body()).toContain(
        `"format" text not null default 'cloudevents' check ("format" ~ '^[a-z][a-z0-9-]{0,39}$')`,
      );
      expect(body()).toContain(
        `alter table "better_supabase"."webhook_endpoints" alter column "format" set default 'cloudevents';`,
      );

      const standard = body({
        "webhooks-out": { options: { defaultFormat: "standard" } },
      });

      expect(standard).toContain(
        `alter column "format" set default 'standard';`,
      );

      expect(upgrade()).toContain(
        `alter table "better_supabase"."webhook_endpoints" add column if not exists "format" text not null default 'standard'`,
      );
    });

    it("sets the default on a mapped adopted column only, and refuses a bad format", () => {
      expect(body(CENTRAKIT)).not.toContain("set default");
      expect(upgrade(CENTRAKIT)).not.toContain("format");

      const mapped = body({
        "webhooks-out": {
          ...CENTRAKIT["webhooks-out"],
          columns: {
            ...CENTRAKIT["webhooks-out"]!.columns,
            endpoints: {
              ...CENTRAKIT["webhooks-out"]!.columns!["endpoints"],
              format: "body_format",
            },
          },
        },
      });

      expect(mapped).toContain(
        `alter table "public"."webhook_endpoints" alter column "body_format" set default 'standard';`,
      );

      expect(() =>
        body({ "webhooks-out": { options: { defaultFormat: "x'; drop" } } }),
      ).toThrow(/defaultFormat "x'; drop" must match/);
    });

    it("requires defaultFormat for an adopted table that maps no format column", () => {
      const { defaultFormat: _, ...options } =
        CENTRAKIT["webhooks-out"]!.options!;

      expect(() =>
        body({ "webhooks-out": { ...CENTRAKIT["webhooks-out"], options } }),
      ).toThrow(ADOPTED_FORMAT_ERROR);
      expect(() =>
        body({
          "webhooks-out": {
            ...CENTRAKIT["webhooks-out"],
            options,
            columns: { endpoints: { format: "body_format" } },
          },
        }),
      ).not.toThrow();
      expect(() => body()).not.toThrow();
    });
  });
});

describe("webhooks-out batches and partitions", () => {
  it("publishes a batch of events for the service role", () => {
    const sql = body();
    expect(sql).toContain(
      'create or replace function "better_supabase"."publish_webhook_events"(events jsonb)',
    );
    expect(sql).toContain("hint = 'WEBHOOK_BATCH_TOO_LARGE'");
    expect(sql).toContain("jsonb_array_length(events) > 1000");
    expect(sql).toContain(
      'grant execute on function "better_supabase"."publish_webhook_events"(jsonb) to service_role;',
    );
  });

  it("partitions deliveries by month with an advisory lock per event", () => {
    const sql = body({ "webhooks-out": { options: { partitioned: true } } });
    expect(sql).toContain('primary key ("id", "created_at")');
    expect(sql).toContain(') partition by range ("created_at");');
    expect(sql).toContain(
      'create table if not exists "better_supabase"."webhook_deliveries_default" partition of "better_supabase"."webhook_deliveries" default;',
    );
    expect(sql).toContain(
      "pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('better_supabase.webhook_deliveries')",
    );
    expect(sql).not.toContain('where "event" is not null do nothing');
    expect(sql).toContain(
      `better_supabase.expired_partitions('"better_supabase"."webhook_deliveries"'::regclass`,
    );
    expect(body()).not.toContain("partition by range");
  });
});
