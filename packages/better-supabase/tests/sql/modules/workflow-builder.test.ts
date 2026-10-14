import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import {
  customContracts,
  moduleBody,
  renderModules,
} from "../../../src/sql/render.ts";
import { moduleProvider } from "../../fixtures/authorization-provider.ts";

const schemaOf = (names: readonly string[]) =>
  renderModules(names, {})
    .filter((file) => file.kind === "schema")
    .map((file) => file.contents)
    .join("\n");

describe("workflow-builder module", () => {
  it("installs after workflows and emits alerts only with the outbox", () => {
    const names = renderModules(["workflow-builder"], {}).map(
      (file) => file.module,
    );
    expect(names.indexOf("workflows")).toBeLessThan(
      names.indexOf("workflow-builder"),
    );
    const sql = schemaOf(["workflow-builder"]);
    expect(sql).toContain(
      "workflow_definitions_tenant_slug_key unique nulls not distinct",
    );
    expect(sql).toContain("'workflow-run:' || v_run::text");
    expect(sql).not.toContain("'workflow_alert.triggered'");
    expect(schemaOf(["workflow-builder", "outbox"])).toContain(
      "'workflow_alert.triggered'",
    );
  });

  it("checks the step library and the graph shape when a version is published", () => {
    const body = moduleBody("workflow-builder", {})!;
    expect(body).toContain("WORKFLOW_GRAPH_INVALID");
    expect(body).toContain("which is not in the step library");
    expect(body).toContain("extensions.digest");
  });

  it("lets only the service role store a compiled form, and restricts node ids", () => {
    const body = moduleBody("workflow-builder", {})!;
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
    const body = moduleBody("workflow-builder", {})!;
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
    const body = moduleBody("workflow-builder", {})!;
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
      /revoke execute on function "better_supabase"\."workflow_run_principal"\(uuid\) from public, anon, authenticated;/,
    );
  });

  it("resolves step permissions from the provider's operations, then the renamed module key", () => {
    const permissionsFn = (sql: string) =>
      sql.slice(
        sql.indexOf('"workflow_graph_permissions"(graph jsonb)'),
        sql.indexOf(
          "$$;",
          sql.indexOf('"workflow_graph_permissions"(graph jsonb)'),
        ),
      );
    expect(permissionsFn(moduleBody("workflow-builder", {})!)).toContain(
      `coalesce('{}'::jsonb ->> (n.value ->> 'step'), 'workflow.run')`,
    );
    const layout = {
      modules: {
        "workflow-builder": { permissions: { run: "automations.run" } },
      } satisfies ModulesConfig,
      accessProvider: {
        ...moduleProvider,
        operations: {
          "workflow.node.crm.lookup": { permission: "crm.read" },
          "workflow.node.": { permission: "ignored" },
          "workflow.node.email.send": { permission: "" },
          "mcp.tool.search": { permission: "search.run" },
        },
      },
    };
    const sql = permissionsFn(moduleBody("workflow-builder", layout)!);
    expect(sql).toContain(
      `coalesce('{"crm.lookup":"crm.read"}'::jsonb ->> (n.value ->> 'step'), 'automations.run')`,
    );
    expect(sql).not.toContain("search.run");
  });

  it("rejects a credential ref outside the credential's tenant", () => {
    expect(schemaOf(["workflow-builder"])).toContain(
      "(save_workflow_credential.ref ->> 'tenant') is distinct from (save_workflow_credential.tenant)::text",
    );
  });

  it("lists its contract in custom mode", () => {
    const custom: ModulesConfig = { "workflow-builder": { mode: "custom" } };
    expect(moduleBody("workflow-builder", { modules: custom })).toBeUndefined();
    const [contract] = customContracts(["workflow-builder"], {
      modules: custom,
    });
    const names = contract!.functions.map((fn) => fn.name);
    for (const name of [
      "save_workflow_definition",
      "publish_workflow_version",
      "workflow_start_target",
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
