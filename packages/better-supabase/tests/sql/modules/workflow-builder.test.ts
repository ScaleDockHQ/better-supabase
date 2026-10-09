import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import {
  customContracts,
  moduleBody,
  renderModules,
} from "../../../src/sql/registry.ts";

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
    expect(sql).not.toContain("'workflow.alert'");
    expect(schemaOf(["workflow-builder", "outbox"])).toContain(
      "'workflow.alert'",
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
      "record_workflow_node_run",
      "check_workflow_alerts",
    ]) {
      expect(names).toContain(name);
    }
  });
});
