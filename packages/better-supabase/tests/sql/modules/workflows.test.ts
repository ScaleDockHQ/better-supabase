import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { customContracts, moduleTopics } from "../../../src/sql/render.ts";
import { moduleBody, renderBlocks } from "../app-columns.ts";

const files = (names: readonly string[], modules: AnyBlocksConfig = {}) =>
  renderBlocks(names, { modules });

const schemaOf = (names: readonly string[], modules: AnyBlocksConfig = {}) =>
  files(names, modules)
    .filter((file) => file.kind === "schema")
    .map((file) => file.contents)
    .join("\n");

const dataOf = (name: string, modules: AnyBlocksConfig = {}) =>
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
    const custom: AnyBlocksConfig = { workflows: { mode: "custom" } };
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

describe("workflows module, registry only", () => {
  const registryOnly: AnyBlocksConfig = {
    workflows: {
      tables: { schedules: null, semaphores: null, startRequests: null },
    },
  };

  it("leaves out the schedule, semaphore and admission functions", () => {
    const sql = schemaOf(["workflows"], registryOnly);
    expect(sql).toContain("record_workflow_run");
    expect(sql).toContain("claim_workflow_run_dispatch");
    expect(sql).not.toContain("create_workflow_schedule");
    expect(sql).not.toContain("acquire_workflow_semaphore");
    expect(sql).not.toContain("request_workflow_start");
    expect(sql).not.toContain("workflow_schedules");
  });

  it("lists only the functions it installs in custom mode", () => {
    const [contract] = customContracts(["workflows"], {
      modules: { workflows: { mode: "custom", ...registryOnly["workflows"] } },
    });

    const names = contract!.functions.map((fn) => fn.name);
    expect(names).toContain("set_workflow_run_engine");
    expect(names).not.toContain("create_workflow_schedule");
  });

  it("adds the run's extra columns and passes them to record_workflow_run", () => {
    const sql = schemaOf(["workflows"], {
      workflows: { options: { runExtraColumns: { region: "text" } } },
    });

    expect(sql).toContain('add column "region" text');
    expect(sql).toContain("fields jsonb default null");
  });

  it("keeps the idempotency key unique per tenant", () => {
    const sql = schemaOf(["workflows"]);
    expect(sql).toContain("workflow_runs_idempotency_key");
    expect(sql).toContain("pending:");
  });
});

describe("workflow-sdk module", () => {
  it("closes the workflow schema and mirrors runs into workflow_runs", () => {
    const sql = moduleBody("workflow-sdk", {})!;
    expect(sql).toContain(
      "revoke all on schema workflow from public, anon, authenticated;",
    );
    expect(sql).toContain(
      "after insert or update of status, attributes, error on workflow.workflow_runs",
    );
    expect(sql).toContain("- 'bsb.tenant' - 'bsb.actor'");
    expect(sql).toContain(
      `"better_supabase"."claim_jobs"('workflow_deliveries', 60, greatest(coalesce(batch, 20), 1))`,
    );
  });

  it("schedules pg_net delivery only in the pg_net mode", () => {
    expect(dataOf("workflow-sdk")).not.toContain("cron.schedule");

    const sql = dataOf("workflow-sdk", {
      "workflow-sdk": {
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

    const body = moduleBody("workflow-sdk", {
      modules: {
        "workflow-sdk": {
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

  it("keeps the dispatcher but schedules no cron job in vercel-queue mode", () => {
    const body = moduleBody("workflow-sdk", {
      modules: { "workflow-sdk": { options: { delivery: "vercel-queue" } } },
    })!;

    expect(body).toContain("workflow_delivery_headers");
    expect(body).toContain("WORKFLOW_DELIVERY_UNCONFIGURED");
    expect(body).not.toContain("cron.schedule('better-supabase-workflow");
  });

  it("schedules the purge backstops only where no World polls", () => {
    const backstops = "cron.schedule('better-supabase-workflow-backstops'";

    expect(dataOf("workflow-sdk")).not.toContain(backstops);

    for (const delivery of ["pg_net", "vercel-queue"]) {
      expect(
        dataOf("workflow-sdk", { "workflow-sdk": { options: { delivery } } }),
      ).toContain(
        `${backstops}, '* * * * *', 'select "better_supabase"."workflow_purge_backstops"()')`,
      );
    }
  });

  it("records only world-postgres's purge backstops in workflow.add_job", () => {
    const body = moduleBody("workflow-sdk")!;

    expect(body).toContain("create or replace function workflow.add_job(");
    expect(body).toContain("hint = 'WORKFLOW_GRAPHILE_UNSUPPORTED'");
    expect(body).toContain(
      "grant execute on function workflow.add_job(text, json, timestamptz, integer, text) to service_role;",
    );
    expect(body).toContain(
      "delete from workflow.workflow_purge_backstops where run_id = any (v_ids);",
    );
  });

  it("rejects an unknown delivery mode or queue name", () => {
    expect(() =>
      dataOf("workflow-sdk", {
        "workflow-sdk": { options: { delivery: "http" } },
      }),
    ).toThrow('must be "poll", "pg_net" or "vercel-queue", got "http"');
    expect(() =>
      moduleBody("workflow-sdk", {
        modules: { "workflow-sdk": { options: { queue: "Bad-Name" } } },
      }),
    ).toThrow('"Bad-Name" is not a queue name');
  });

  it("renders nothing in custom mode and lists the dispatcher contract", () => {
    const custom: AnyBlocksConfig = { "workflow-sdk": { mode: "custom" } };

    expect(moduleBody("workflow-sdk", { modules: custom })).toBeUndefined();

    const [contract] = customContracts(["workflow-sdk"], { modules: custom });

    expect(contract!.functions.map((fn) => fn.name)).toEqual([
      "dispatch_workflow_deliveries",
      "workflow_claim_run_key",
      "workflow_set_run_key",
      "workflow_release_run_key",
      "workflow_purge_runs",
      "workflow_purge_backstops",
      "workflow_open_hooks",
      "eve_session_wake",
      "eve_session_lease",
      "eve_session_commit",
      "eve_session_release",
      "eve_sessions_behind",
      "eve_open_sessions",
      "eve_session_mark",
    ]);
    expect(contract!.functions[0]).toEqual({
      name: "dispatch_workflow_deliveries",
      args: ["integer"],
      returns: "integer",
    });
  });
});
