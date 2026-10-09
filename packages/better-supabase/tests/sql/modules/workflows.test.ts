import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import {
  customContracts,
  moduleBody,
  moduleTopics,
  renderModules,
} from "../../../src/sql/registry.ts";

const files = (names: readonly string[], modules: ModulesConfig = {}) =>
  renderModules(names, { modules });
const schemaOf = (names: readonly string[], modules: ModulesConfig = {}) =>
  files(names, modules)
    .filter((file) => file.kind === "schema")
    .map((file) => file.contents)
    .join("\n");
const dataOf = (name: string, modules: ModulesConfig = {}) =>
  files([name], modules).find(
    (file) => file.kind === "data" && file.module === name,
  )!.contents;

describe("workflows module", () => {
  it("pings the run's topics, with terminal outbox events when the outbox is installed", () => {
    const sql = schemaOf(["workflows"]);
    expect(sql).toContain("'workflow-run:' || new.\"id\"::text");
    expect(sql).not.toContain("when 'completed' then");
    expect(schemaOf(["workflows", "outbox"])).toContain(
      "when 'completed' then",
    );
    expect(schemaOf(["workflows", "outbox"])).toContain(
      "'workflow_run.failed:' || new.\"id\"",
    );
  });

  it("lists its topics and its contract in custom mode", () => {
    expect(moduleTopics(["workflows"]).map((entry) => entry.topic)).toEqual([
      "workflow-run:{runId}",
      "workflow-runs:{tenant}",
    ]);
    const custom: ModulesConfig = { workflows: { mode: "custom" } };
    expect(moduleBody("workflows", { modules: custom })).toBeUndefined();
    const [contract] = customContracts(["workflows"], { modules: custom });
    expect(contract!.functions.map((fn) => fn.name)).toContain(
      "record_workflow_run",
    );
    expect(contract!.functions.map((fn) => fn.name)).toContain(
      "claim_workflow_start_requests",
    );
  });
});

describe("workflow-sdk-world module", () => {
  it("closes the workflow schema and mirrors runs into workflow_runs", () => {
    const sql = moduleBody("workflow-sdk-world", {})!;
    expect(sql).toContain(
      "revoke all on schema workflow from public, anon, authenticated;",
    );
    expect(sql).toContain(
      "after insert or update of status, attributes, error on workflow.workflow_runs",
    );
    expect(sql).toContain("- 'bs.tenant' - 'bs.actor'");
    expect(sql).toContain(
      `"better_supabase"."claim_jobs"('workflow_deliveries', 60, greatest(coalesce(batch, 20), 1))`,
    );
  });

  it("schedules pg_net delivery only in the pg_net mode", () => {
    expect(dataOf("workflow-sdk-world")).not.toContain("cron.schedule");
    const sql = dataOf("workflow-sdk-world", {
      "workflow-sdk-world": {
        options: {
          delivery: "pg_net",
          schedule: "5 seconds",
          queue: "wf_q",
          batch: 5,
          timeout: 10_000,
        },
      },
    });
    expect(sql).toContain(
      "cron.schedule('better-supabase-workflow-deliveries', '5 seconds'",
    );
    const body = moduleBody("workflow-sdk-world", {
      modules: {
        "workflow-sdk-world": {
          options: { queue: "wf_q", batch: 5, timeout: 10_000 },
        },
      },
    })!;
    expect(body).toContain(
      `"claim_jobs"('wf_q', 40, greatest(coalesce(batch, 5), 1))`,
    );
    expect(body).toContain(
      "to_regprocedure('net.http_post(text, jsonb, jsonb, jsonb, integer)')",
    );
    expect(body).toContain("timeout_milliseconds := $4)");
    expect(body).toContain("), 10000;");
    expect(body).not.toContain("perform net.http_post");
  });

  it("rejects an unknown delivery mode or queue name", () => {
    expect(() =>
      dataOf("workflow-sdk-world", {
        "workflow-sdk-world": { options: { delivery: "http" } },
      }),
    ).toThrow('must be "poll" or "pg_net", got "http"');
    expect(() =>
      moduleBody("workflow-sdk-world", {
        modules: { "workflow-sdk-world": { options: { queue: "Bad-Name" } } },
      }),
    ).toThrow('"Bad-Name" is not a queue name');
  });

  it("renders nothing in custom mode and lists the dispatcher contract", () => {
    const custom: ModulesConfig = { "workflow-sdk-world": { mode: "custom" } };
    expect(
      moduleBody("workflow-sdk-world", { modules: custom }),
    ).toBeUndefined();
    const [contract] = customContracts(["workflow-sdk-world"], {
      modules: custom,
    });
    expect(contract!.functions).toEqual([
      {
        name: "dispatch_workflow_deliveries",
        args: ["integer"],
        returns: "integer",
      },
    ]);
  });
});
