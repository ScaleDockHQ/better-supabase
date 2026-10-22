import { describe, expect, it } from "vitest";

import type { BlockConfig } from "../../../src/config/blocks.ts";

import { moduleContext } from "../../../src/sql/module-context.ts";
import { resolveBlocks } from "../../../src/sql/registry.ts";
import { moduleBody, renderBlocks } from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";

const audit = (config: BlockConfig = {}) =>
  moduleBody("audit", { modules: { audit: config } })!;

/**
 * CentraKit's audit tables: uuid ids, no row snapshots, restricted details
 * apart.
 */
const CENTRAKIT: BlockConfig = {
  mode: "adopt",
  tables: {
    log: "public.audit_logs",
    restricted: "public.audit_log_restricted_details",
  },
  columns: {
    log: {
      table: null,
      record: "target_id",
      op: null,
      old: null,
      new: null,
      changed: null,
      actorRole: null,
      tenant: "organization_id",
      occurredAt: "occurred_at",
      impersonatedBy: null,
      impersonationReason: null,
      supportSession: null,
      metadata: "safe_metadata",
    },
    restricted: {
      entry: "event_id",
      old: null,
      new: null,
      metadata: "restricted_metadata",
    },
  },
  options: { eventSource: "saas" },
};

describe("audit module", () => {
  it("keeps the managed defaults and adds event naming", () => {
    const sql = audit();
    expect(sql).toContain(
      'create table if not exists "better_supabase"."audit_events" (',
    );
    expect(sql).toContain(
      "coalesce(entry.event_prefix, tg_table_name) || '.' || case tg_op",
    );
    expect(sql).toContain(
      "create or replace function better_supabase.audit_event(",
    );
    expect(sql).toContain("coalesce(source, 'app')");
    expect(sql).toContain('drop trigger if exists "bsb_audit_append_only"');
    expect(sql).toContain(
      'drop policy if exists bsb_audit_read on "better_supabase"."audit_events";',
    );
    expect(sql).not.toContain("audit_events_restricted");
    expect(sql).toContain(
      "execute function better_supabase.audit_row_change(%L)",
    );
    expect(sql).toContain("settings := tg_argv[0]::jsonb;");
    expect(sql).not.toMatch(/insert into better_supabase\.audited_tables/);
    expect(sql).toContain(
      "raise exception 'audit_event got restricted details, and the audit module has no restricted table'",
    );
    expect(sql).toContain(
      "hint = 'Set blocks.audit.options.restricted to true.'",
    );
    const [file] = renderBlocks(["audit"]);
    expect(file!.contents).not.toContain("audit_log;");
  });

  it("maps onto adopted tables without creating them", () => {
    const sql = audit(CENTRAKIT);
    expect(sql).not.toContain("create table if not exists public");
    expect(sql).not.toContain('create table if not exists "public"');
    expect(sql).toContain(
      'insert into "public"."audit_logs" ("target_id", "actor_id", "organization_id", "event_type"',
    );
    expect(sql).toContain('entry_id "public"."audit_logs"."id"%type;');
    expect(sql).toContain(
      'insert into "public"."audit_log_restricted_details" ("event_id", "ip_address", "user_agent", "restricted_metadata")',
    );
    expect(sql).toContain("coalesce(source, 'saas')");
    expect(sql).not.toContain("audit_event got restricted details");
    expect(sql).not.toContain("old_record");
    expect(sql).not.toContain("drop policy if exists bsb_audit_read");
  });

  it("guards, scopes and splits entries by option", () => {
    const sql = audit({
      options: {
        appendOnly: true,
        readPolicy: true,
        impersonators: "hide",
        restricted: true,
        eventRoles: ["service_role", "authenticated"],
      },
      permissions: { view: "audit.read", viewAll: "platform.audit.read" },
    });

    expect(sql).toContain(
      'create trigger "bsb_audit_append_only" before update or delete',
    );
    expect(sql).toContain("better_supabase.tenant_ids_with('audit.read')");
    expect(sql).toContain("better_supabase.is_platform('platform.audit.read')");
    expect(sql).toMatch(/grant select \([^)]*"actor_id"[^)]*\) on/);
    expect(sql).not.toMatch(/grant select \([^)]*"impersonated_by"/);
    expect(sql).toContain(
      'create table if not exists "better_supabase"."audit_events_restricted"',
    );
    expect(sql).toContain('to "service_role", "authenticated";');
  });

  it("calls the retention hook the app names", () => {
    const sql = audit({
      hooks: {
        schema: "app",
        functions: { audit_retention: "plan_audit_days" },
      },
    });

    expect(sql).toContain(`to_regprocedure('"app"."plan_audit_days"(uuid)')`);
    expect(sql).toContain(
      `to_regprocedure('"app"."plan_audit_days"(uuid)')::oid::regproc)\n        into v_older using v_tenant;`,
    );
    expect(sql).toContain("limit batch - purged");
    expect(sql).not.toMatch(/"app"\."plan_audit_days"\(l\./);
  });

  it("needs the access module only for the read policy", () => {
    const names = (config: BlockConfig) =>
      resolveBlocks(["audit"], { modules: { audit: config } }).map(
        (module) => module.name,
      );

    expect(names({})).toEqual(["audit"]);
    expect(names({ options: { readPolicy: true } })).toContain("permissions");
  });

  it("rejects an unknown impersonators option", () => {
    expect(() =>
      audit({ options: { readPolicy: true, impersonators: "blur" } }),
    ).toThrow(/impersonators/);
  });

  it("takes an event's restricted details from service callers' arguments only", () => {
    const sql = audit({ options: { restricted: true } });
    expect(sql).toContain("    ip := better_supabase.request_ip();");
    expect(sql).toContain(
      "if coalesce(restricted, '{}') <> '{}' or ip is not null or nullif(user_agent, '') is not null or nullif(session_id, '') is not null then",
    );
    expect(sql).not.toContain("coalesce(ip, better_supabase.request_ip())");
    expect(audit()).toContain("    ip := null;");
  });

  it("reveals a page of entries for an export, with one audit.revealed per tenant", () => {
    const sql = audit({ options: { restricted: true, readPolicy: true } });
    expect(sql).toContain(
      `create or replace function "better_supabase"."reveal_audit_entries"(entries text[])`,
    );
    expect(sql).toContain(
      "metadata => jsonb_build_object('entries', revealed.ids)",
    );
    expect(audit({ options: { restricted: true } })).not.toContain(
      "reveal_audit_entries",
    );
  });

  it("reads the request and correlation ids from settings, then headers", () => {
    const sql = audit();
    expect(sql).toContain(
      "create or replace function better_supabase.request_id_or_null(value text)",
    );
    expect(sql).toContain(
      "select case when value ~ '^[A-Za-z0-9._:;,@/+=-]{1,128}$' then value end;",
    );
    expect(sql).toContain(
      "coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-request-id')))",
    );
    expect(sql).toContain(
      "coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-correlation-id')))",
    );
    expect(sql).toContain(
      "coalesce(better_supabase.request_id_or_null(request_id), coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null(better_supabase.request_header('x-request-id'))))",
    );
    expect(sql).toContain(
      "coalesce(better_supabase.request_id_or_null(correlation_id), coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null(better_supabase.request_header('x-correlation-id'))))",
    );
    expect(sql).toContain(
      'create index if not exists audit_events_correlation_idx on "better_supabase"."audit_events" ("correlation_id") where "correlation_id" is not null;',
    );
  });

  it("takes the request and correlation header names from the options", () => {
    const sql = audit({
      options: {
        requestIdHeader: "X-Amzn-Trace-Id",
        correlationIdHeader: "x-action-id",
      },
    });

    expect(sql).toContain("(v_headers ->> 'x-amzn-trace-id')");
    expect(sql).toContain("(v_headers ->> 'x-action-id')");
    expect(sql).toContain("better_supabase.request_header('x-action-id')");
    expect(sql).not.toContain("'x-request-id'");
    expect(sql).not.toContain("'x-correlation-id'");
  });

  it("records the ids on an adopted log that maps them, and indexes only managed logs", () => {
    const sql = audit({
      ...CENTRAKIT,
      columns: {
        ...CENTRAKIT.columns,
        log: { ...CENTRAKIT.columns!["log"], correlationId: "trace_group" },
      },
    });

    expect(sql).toMatch(
      /insert into "public"\."audit_logs" \([^)]*"trace_group"/,
    );
    expect(sql).not.toContain("audit_events_correlation_idx");
  });

  it("upgrades from versions 5 to 8 without SQL of their own", () => {
    const [plan] = upgradePlan([{ module: "audit", version: 5 }]);
    expect(plan!.steps.map((step) => step.sql)).toEqual(["", "", "", ""]);
  });

  it("chains entries and lists the chain functions only with options.chain", () => {
    const sql = audit({ options: { chain: true } });
    expect(sql).toContain(
      'alter table "better_supabase"."audit_events" add column if not exists row_hash bytea;',
    );
    expect(sql).toContain(
      'create trigger "bsb_audit_chain" before insert on "better_supabase"."audit_events"',
    );
    expect(sql).toContain(
      "create or replace function better_supabase.verify_audit_chain(",
    );
    expect(sql).toContain(
      "create table if not exists better_supabase.audit_checkpoints (",
    );
    expect(audit()).toContain(
      'drop trigger if exists "bsb_audit_chain" on "better_supabase"."audit_events";',
    );
    expect(audit()).not.toContain("verify_audit_chain");
    expect(audit({ ...CENTRAKIT, options: { chain: true } })).not.toContain(
      "audit_chain",
    );

    const contract = (config: BlockConfig) =>
      resolveBlocks(["audit"]).find((module) => module.name === "audit")!
        .contract!(moduleContext("audit", { modules: { audit: config } })).map(
        (fn) => fn.name,
      );

    expect(contract({ options: { chain: true } })).toContain(
      "verify_audit_chain",
    );
    expect(contract({})).not.toContain("verify_audit_chain");
  });

  it("partitions a new managed log by month and drops expired months in the purge", () => {
    const sql = audit({ options: { partitioned: true, restricted: true } });
    expect(sql).toContain(') partition by range ("occurred_at");');
    expect(sql).toContain('primary key ("id", "occurred_at")');
    expect(sql).not.toContain(
      "create unique index if not exists audit_events_idempotency_idx",
    );
    expect(sql).toContain('"entry_id" bigint primary key,');
    expect(sql).toContain(
      `better_supabase.expired_partitions('"better_supabase"."audit_events"'::regclass, now() - older_than)`,
    );
    expect(sql).toContain(
      'delete from "better_supabase"."audit_events_restricted" r using %s p',
    );
    expect(sql).toContain(
      `select better_supabase.ensure_partitions('"better_supabase"."audit_events"'::regclass, 3);`,
    );
    expect(audit({ options: { partitioned: true } })).not.toContain(
      "using %s p",
    );
    expect(audit()).not.toContain("expired_partitions");
  });

  it("keeps entries for the data-lifecycle policies and holds", () => {
    const sql = renderBlocks(["audit", "data-lifecycle"], {
      modules: { audit: { options: { partitioned: true } } },
    })
      .filter((file) => file.module === "audit")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(
      `"better_supabase"."retention_cutoff"('audit', older_than)) p`,
    );
    expect(sql).toContain(
      `"better_supabase"."is_held"('audit', (v_tenant)::text)`,
    );
    expect(sql).toContain(
      `"better_supabase"."retention_for"('audit', (l."organization_id")::text), older_than)`,
    );
  });

  it("drops the old signatures when upgrading from version 1", () => {
    const [plan] = upgradePlan([{ module: "audit", version: 1 }]);
    expect(plan!.steps[0]!.sql).toContain(
      "drop function if exists better_supabase.audit(regclass, text[], boolean);",
    );
  });
});

describe("audit value mapping", () => {
  const ADOPTED: BlockConfig = {
    mode: "adopt",
    tables: { log: "public.activity_log" },
    columns: {
      log: {
        tenant: "workspace_id",
        actorKind: "actor_type",
        tenantLabel: "workspace_name",
        scope: "scope",
      },
    },
    options: {
      values: {
        scope: { tenant: "workspace", platform: "global" },
        actorKind: { user: "member", service: "api" },
        outcome: { success: "ok", failure: "error" },
        source: { database: "db" },
        category: { data: "record", system: "platform" },
      },
      tenantLabel: "public.workspaces.title",
      tenantLabelKey: "workspace_id",
    },
  };

  it("fills an adopted log's own columns from metadata keys", () => {
    const sql = audit({
      ...ADOPTED,
      options: { metadataColumns: { ticket_id: "ticketId" } },
    });

    expect(sql).toContain(
      "|| case when audit_event.metadata ? 'ticketId' then pg_catalog.jsonb_build_object('ticket_id', audit_event.metadata -> 'ticketId') else '{}'::jsonb end;",
    );
    expect(sql).toContain(
      `execute pg_catalog.format('insert into "public"."activity_log" (%s) select %s from pg_catalog.jsonb_populate_record(null::"public"."activity_log", $1) returning "id"', entry_columns, entry_columns)`,
    );
    expect(sql).toContain(
      "'metadata', coalesce(metadata, '{}') - array['ticketId']::text[],",
    );
    expect(sql).toContain(
      `'columns', jsonb_build_object('ticket_id', l."ticket_id")`,
    );
    expect(
      audit({
        ...ADOPTED,
        options: {
          metadataColumns: { ticket_id: "ticketId" },
          keepMappedMetadata: true,
        },
      }),
    ).toContain("'metadata', coalesce(metadata, '{}'),");
    expect(audit(ADOPTED)).not.toContain("entry_row");
    expect(sql).toContain(
      "request_id text default null,\n  scope text default null",
    );
    expect(() =>
      audit({ options: { metadataColumns: { ticket_id: "ticketId" } } }),
    ).toThrow(/adopted log/);
    expect(() =>
      audit({ ...ADOPTED, options: { metadataColumns: { scope: "scope" } } }),
    ).toThrow(/already fills it/);
    expect(() =>
      audit({ ...ADOPTED, options: { metadataColumns: { ticket_id: 1 } } }),
    ).toThrow(/metadata key/);
  });

  it("writes the adopted log's values and reads them back as the module's", () => {
    const sql = audit(ADOPTED);
    expect(sql).toContain(
      "case (case when row_tenant is null then 'platform' else 'tenant' end) when 'tenant' then 'workspace' when 'platform' then 'global' else",
    );
    expect(sql).toContain(
      "case ('success') when 'success' then 'ok' when 'failure' then 'error' else ('success') end",
    );
    expect(sql).toContain(
      "case ('database') when 'database' then 'db' else ('database') end",
    );
    expect(sql).toContain(
      "case (coalesce(outcome, 'success')) when 'success' then 'ok'",
    );
    expect(sql).toContain(
      "when 'user' then 'member' when 'service' then 'api'",
    );
    expect(sql).toContain(
      `'scope', case l."scope" when 'workspace' then 'tenant' when 'global' then 'platform' else l."scope" end`,
    );
    expect(sql).toContain(
      `'outcome', case l."outcome" when 'ok' then 'success' when 'error' then 'failure' else l."outcome" end`,
    );
    expect(sql).toContain(
      `(select o."title"::text from "public"."workspaces" o where o."workspace_id" = row_tenant)`,
    );
    expect(sql).toContain(
      "case (coalesce(entry.category, 'data')) when 'data' then 'record' when 'system' then 'platform' else (coalesce(entry.category, 'data')) end",
    );
    expect(sql).toContain(
      `'category', case l."category" when 'record' then 'data' when 'platform' then 'system' else l."category" end`,
    );
  });

  it("keeps the module's values without a mapping", () => {
    const sql = audit();
    expect(sql).toContain("'scope', l.\"scope\"");
    expect(sql).not.toContain("case ('success')");
  });

  it("accepts values only in adopt mode and checks their shape", () => {
    expect(() =>
      audit({ options: { values: { outcome: { success: "ok" } } } }),
    ).toThrow(/Only adopt mode accepts it/);
    expect(() =>
      audit({ ...ADOPTED, options: { values: { op: { insert: "i" } } } }),
    ).toThrow(/unknown column "op"/);
    expect(() =>
      audit({
        ...ADOPTED,
        options: { values: { outcome: { success: "ok", failure: "ok" } } },
      }),
    ).toThrow(/two values map to "ok"/);
    expect(() =>
      audit({ ...ADOPTED, options: { values: { outcome: { success: 1 } } } }),
    ).toThrow(/must be a string/);
    expect(() =>
      audit({ ...ADOPTED, options: { tenantLabel: "workspaces" } }),
    ).toThrow(/must be "schema.table.column"/);
    expect(() => audit({ ...ADOPTED, options: { tenantLabel: 5 } })).toThrow(
      /tenantLabel must be a string/,
    );
    expect(() => audit({ ...ADOPTED, options: { values: "ok" } })).toThrow(
      /values must be an object/,
    );
    expect(() =>
      audit({ ...ADOPTED, options: { values: { outcome: "ok" } } }),
    ).toThrow(/must map values to values/);
  });

  it("writes audit_event_trusted for definer functions, granted to trusted roles only", () => {
    const sql = audit({ options: { trustedRoles: ["app_owner"] } });

    const trusted = sql.slice(
      sql.indexOf(
        "create or replace function better_supabase.audit_event_trusted(",
      ),
    );

    const body = trusted.slice(0, trusted.indexOf("$$;"));
    expect(body).toContain("actor_id := coalesce(actor_id, auth.uid());");
    expect(body).not.toContain("actor_kind := null;");
    expect(body).not.toContain("audit_event.");
    expect(body).toContain("audit_event_trusted.idempotency_key");
    expect(sql).toContain(
      "revoke execute on function better_supabase.audit_event_trusted(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text, uuid, uuid, text) from public, anon, authenticated;",
    );
    expect(sql).toContain('to "service_role", "app_owner";');
    const plain = audit();
    expect(plain).toContain("actor_kind := null;");
    expect(plain).toMatch(/audit_event_trusted\([^)]*\) to "service_role";/);
  });

  it("takes the impersonation columns as arguments, with the act claim first for users", () => {
    const sql = audit();
    expect(sql).toContain(
      "  support_session uuid default null,\n  impersonated_by uuid default null,\n  impersonation_reason text default null\n)",
    );
    expect(sql).toContain(
      "coalesce(audit_event.impersonated_by, case when auth.jwt() -> 'act' ->> 'sub'",
    );
    expect(sql).toContain(
      "coalesce(audit_event.impersonation_reason, auth.jwt() -> 'act' ->> 'reason')",
    );
    expect(sql).toContain(
      "coalesce(audit_event.support_session, case when auth.jwt() -> 'act' ->> 'session_id'",
    );
    expect(sql).toContain(
      "coalesce(audit_event_trusted.support_session, case when",
    );

    const plain = sql.slice(
      sql.indexOf("create or replace function better_supabase.audit_event("),
    );

    expect(plain.slice(0, plain.indexOf("$$;"))).toContain(
      "    if (select auth.jwt()) -> 'act' is not null or impersonated_by is distinct from auth.uid() then\n      support_session := null;",
    );
  });

  it("drops the previous signatures of audit_event and audit_event_trusted", () => {
    const sql = audit();

    const previous =
      "text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text)";

    expect(sql).toContain(
      `drop function if exists better_supabase.audit_event(${previous};`,
    );
    expect(sql).toContain(
      `drop function if exists better_supabase.audit_event_trusted(${previous};`,
    );
    expect(sql).toContain(
      "grant execute on function better_supabase.audit_event(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text, uuid, uuid, text) to",
    );
  });
});

describe("audit revert", () => {
  const sqlOf = (
    config: BlockConfig = {},
    modules = ["permissions", "audit"],
  ) =>
    renderBlocks(modules, { modules: { audit: config } })
      .filter((file) => file.module === "audit")
      .map((file) => file.contents)
      .join("\n");

  it("reverts as the caller with audit.revert and finds the writes for undo", () => {
    const sql = sqlOf();
    expect(sql).toContain(
      `create or replace function "better_supabase"."revert_audit_entries"(entries text[])`,
    );
    expect(sql).toMatch(
      /revert_audit_entries"\(entries text\[\]\)\s+returns jsonb\s+language plpgsql\s+security invoker/,
    );
    expect(sql).toContain("'audit.revert'");
    expect(sql).toContain("ROW_CHANGED_SINCE");
    expect(sql).toContain(`"audit_entries_correlated"(correlation text)`);
  });

  it("needs the access module and the row snapshots", () => {
    expect(sqlOf({}, ["audit"])).not.toContain("revert_audit_entries");
    expect(sqlOf(CENTRAKIT)).not.toContain("revert_audit_entries");
  });
});

describe("audit_event_many", () => {
  it("records a batch through audit_event, each event in its own savepoint", () => {
    const sql = audit();
    expect(sql).toContain(
      "create or replace function better_supabase.audit_event_many(events jsonb)",
    );
    expect(sql).toContain("batch_result := better_supabase.audit_event(");
    expect(sql).toContain(
      "outcome => coalesce(batch_event ->> 'outcome', 'success')",
    );
    expect(sql).toContain("exception when others then");
    expect(sql).toContain("hint = 'AUDIT_BATCH_TOO_LARGE'");
    expect(sql).toContain(
      "revoke execute on function better_supabase.audit_event_many(jsonb) from public, anon, authenticated;",
    );
  });
});
