import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import {
  customContracts,
  moduleBody,
  renderBlocks,
} from "../../../src/sql/render.ts";
import { moduleProvider } from "../../fixtures/authorization-provider.ts";

const schemaOf = (names: readonly string[]) =>
  renderBlocks(names, {})
    .filter((file) => file.kind === "schema")
    .map((file) => file.contents)
    .join("\n");

describe("workflow-editor module", () => {
  it("installs after workflows and emits alerts only with the outbox", () => {
    const names = renderBlocks(["workflow-editor"], {}).map(
      (file) => file.module,
    );

    expect(names.indexOf("workflows")).toBeLessThan(
      names.indexOf("workflow-editor"),
    );
    const sql = schemaOf(["workflow-editor"]);
    expect(sql).toContain(
      "workflow_definitions_tenant_slug_key unique nulls not distinct",
    );
    expect(sql).toContain("'workflow-run:' || v_run::text");
    expect(sql).not.toContain("'workflow_alert.triggered'");
    expect(schemaOf(["workflow-editor", "outbox"])).toContain(
      "'workflow_alert.triggered'",
    );
  });

  it("checks the step library and the graph shape when a version is published", () => {
    const body = moduleBody("workflow-editor", {})!;
    expect(body).toContain("WORKFLOW_GRAPH_INVALID");
    expect(body).toContain("which is not in the step library");
    expect(body).toContain("extensions.digest");
  });

  it("lets only the service role store a compiled form, and restricts node ids", () => {
    const body = moduleBody("workflow-editor", {})!;

    const publish = body.slice(
      body.indexOf('"publish_workflow_version"(version uuid'),
    );

    expect(publish).toMatch(
      /if compiled is not null and not \(coalesce\(.*'service_role', 'postgres', 'supabase_admin'\)\) then\s+raise exception [^;]+errcode = '42501', hint = 'WORKFLOW_COMPILED_FORBIDDEN'/,
    );
    expect(publish.indexOf("WORKFLOW_COMPILED_FORBIDDEN")).toBeLessThan(
      publish.indexOf("WORKFLOW_GRAPH_INVALID"),
    );
    expect(body).toContain("(v_node ->> 'id') !~ '^[A-Za-z0-9_-]{1,100}$'");
  });

  it("stores the publisher and refuses one who lacks a step's permission", () => {
    const body = moduleBody("workflow-editor", {})!;
    expect(body).toContain(
      'add column if not exists "published_by" uuid references auth.users (id) on delete set null',
    );
    expect(body).toContain(
      `add column if not exists "owner_kind" text check ("owner_kind" in ('user', 'organization'))`,
    );

    const publish = body.slice(
      body.indexOf('"publish_workflow_version"(version uuid'),
    );

    expect(publish).toMatch(
      /v_permissions := "better_supabase"\."workflow_graph_permissions"\(v_row\."graph"\);\s+if not v_service then/,
    );
    expect(publish).toContain(
      "where not coalesce(better_supabase.can('tenant', v_tenant, p), false);",
    );
    expect(publish).toContain("hint = 'WORKFLOW_PUBLISHER_FORBIDDEN'");
    expect(publish).toContain(
      `"owner_kind" = case when v_service then 'organization' else 'user' end`,
    );
    expect(publish.indexOf("WORKFLOW_GRAPH_INVALID")).toBeLessThan(
      publish.indexOf("WORKFLOW_PUBLISHER_FORBIDDEN"),
    );
  });

  it("checks the stored publisher for every step and never answers for a gone one", () => {
    const body = moduleBody("workflow-editor", {})!;

    const principal = body.slice(
      body.indexOf('"workflow_run_principal"(version uuid'),
    );

    expect(principal).toContain(
      "where not coalesce(better_supabase.can_user(v_row.\"published_by\", 'tenant', v_tenant, p), false);",
    );
    expect(principal).toContain(
      `unnest(array_append(v_row."permissions", 'workflow.publish'))`,
    );
    expect(principal).toContain("hint = 'WORKFLOW_PUBLISHER_REVOKED'");
    expect(principal).toContain(
      "The user who published this workflow no longer exists",
    );
    expect(principal).toContain("published before publishers were recorded");
    expect(principal).toMatch(
      /revoke execute on function "better_supabase"\."workflow_run_principal"\(uuid, uuid\) from public, anon, authenticated;/,
    );
    expect(principal).toContain(
      `select case when x."scope" = 'system' then tenant else x."tenant_id" end into v_tenant`,
    );
    expect(body).toContain(
      'drop function if exists "better_supabase"."workflow_run_principal"(uuid);',
    );
  });

  it("binds definitions to subject types and checks the record on a subject start", () => {
    const body = moduleBody("workflow-editor", {})!;
    expect(body).toContain(
      `add column if not exists "subject_types" text[] not null default '{}'`,
    );
    expect(body).toContain(
      'drop function if exists "better_supabase"."save_workflow_definition"(uuid, text, text, text);',
    );
    expect(body).toContain(
      'or workflow_definitions_list.subject_type = any (x."subject_types")',
    );

    const start = (sql: string) => {
      const from = sql.indexOf('"workflow_subject_start_target"(\n');

      return sql.slice(from, sql.indexOf("$$;", from));
    };

    expect(start(body)).toContain("hint = 'WORKFLOW_SUBJECT_TYPE'");
    expect(start(body)).not.toContain("can_subject");
    expect(start(body)).not.toContain("security definer");
    const withSubjects = schemaOf(["workflow-editor", "subjects"]);
    expect(start(withSubjects)).toContain(
      `"better_supabase"."can_subject"(subject_type, subject_id, 'read')`,
    );
  });

  it("scopes system definitions, forks and opt-outs", () => {
    const body = moduleBody("workflow-editor", {})!;
    expect(body).toContain(`"scope" = 'tenant' or "tenant_id" is null`);
    expect(body).toContain(
      `or ("scope" = 'system' and exists (select better_supabase.tenant_ids_with('workflow.read')))`,
    );

    const target = body.slice(
      body.indexOf('"workflow_start_target"(definition uuid'),
    );

    expect(target).toContain("hint = 'WORKFLOW_TENANT_REQUIRED'");
    expect(target).toContain("hint = 'WORKFLOW_OPTED_OUT'");
    expect(body).toContain(
      `"set_workflow_opt_out"(tenant uuid, definition uuid, opted_out boolean default true)`,
    );
    expect(body).toContain(
      `'behind', coalesce(u.version > x."forked_from_version", false)`,
    );
    expect(body).not.toContain('"workflow_event_targets"(type');
  });

  it("checks grants on restricted definitions and skips test runs in alerts", () => {
    const body = moduleBody("workflow-editor", {})!;
    expect(body).toContain(
      `"workflow_definition_grants" gr\n        where gr."definition_id" = definition\n          and gr."action" in ('run', 'edit')`,
    );
    expect(body).not.toContain('"team_members"');
    expect(schemaOf(["workflow-editor", "teams"])).toContain(
      `gr."principal_kind" = 'team' and exists`,
    );
    expect(body).toContain("'A graph has at least one trigger node'");
    expect(body).toContain(
      `if new."mode" = 'test' or new."status" <> 'failed'`,
    );
    expect(body).toContain(`and y."mode" = 'live'`);
    const test = body.slice(body.indexOf('"start_test_run"(\n'));
    expect(test).toContain("hint = 'WORKFLOW_TRIGGER_NODE'");
  });

  it("resolves step permissions from the provider's node operations, then the step's operation, then the renamed module key", () => {
    const permissionsFn = (sql: string) =>
      sql.slice(
        sql.indexOf('"workflow_graph_permissions"(graph jsonb)'),
        sql.indexOf(
          "$$;",
          sql.indexOf('"workflow_graph_permissions"(graph jsonb)'),
        ),
      );

    const plain = permissionsFn(moduleBody("workflow-editor", {})!);
    expect(plain).toContain(`'{}'::jsonb ->> (n.value ->> 'step'),`);
    expect(plain).toContain(
      `(select coalesce('{}'::jsonb ->> s."operation", s."operation")`,
    );
    expect(plain).toContain(`'workflow.run'\n    ) as p`);

    const layout = {
      modules: {
        "workflow-editor": { permissions: { run: "automations.run" } },
      } satisfies AnyBlocksConfig,
      accessProvider: {
        ...moduleProvider,
        operations: {
          "workflow.node.crm.lookup": { permission: "crm.read" },
          "workflow.node.": { permission: "ignored" },
          "workflow.node.email.send": { permission: "" },
          "mcp.tool.search": { permission: "search.run" },
          "invoices.void": { permission: "billing.manage" },
        },
      },
    };

    const sql = permissionsFn(moduleBody("workflow-editor", layout)!);
    expect(sql).toContain(
      `'{"crm.lookup":"crm.read"}'::jsonb ->> (n.value ->> 'step'),`,
    );
    expect(sql).toContain(
      `coalesce('{"invoices.void":"billing.manage"}'::jsonb ->> s."operation", s."operation")`,
    );
    expect(sql).toContain(`'automations.run'\n    ) as p`);
    expect(sql).not.toContain("search.run");
  });

  it("rejects a credential ref outside the credential's tenant", () => {
    expect(schemaOf(["workflow-editor"])).toContain(
      "(save_workflow_credential.ref ->> 'tenant') is distinct from (save_workflow_credential.tenant)::text",
    );
  });

  it("lists its contract in custom mode", () => {
    const custom: AnyBlocksConfig = { "workflow-editor": { mode: "custom" } };
    expect(moduleBody("workflow-editor", { modules: custom })).toBeUndefined();

    const [contract] = customContracts(["workflow-editor"], {
      modules: custom,
    });

    const names = contract!.functions.map((fn) => fn.name);

    for (const name of [
      "save_workflow_definition",
      "publish_workflow_version",
      "workflow_start_target",
      "workflow_subject_start_target",
      "start_test_run",
      "fork_workflow_definition",
      "set_workflow_opt_out",
      "set_workflow_definition_grant",
      "workflow_webhook_target",
      "workflow_graph_permissions",
      "workflow_run_principal",
      "record_workflow_node_run",
      "check_workflow_alerts",
    ]) {
      expect(names).toContain(name);
    }
  });
});
