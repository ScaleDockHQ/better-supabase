import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import { moduleBody, renderModules } from "../../../src/sql/registry.ts";

const body = (modules: ModulesConfig = {}) =>
  moduleBody("ai-tasks", { modules })!;

const rendered = (names: readonly string[]) =>
  renderModules([...names, "ai-tasks"], { modules: {} })
    .filter((file) => file.module === "ai-tasks")
    .map((file) => file.contents)
    .join("\n");

describe("ai-tasks module", () => {
  it("owns tasks and runs", () => {
    const sql = body();
    expect(sql).toContain(
      'create table if not exists "better_supabase"."ai_scheduled_tasks" (',
    );
    expect(sql).toContain(
      'create table if not exists "better_supabase"."ai_task_runs" (',
    );
    expect(sql).toContain("for update skip locked");
  });

  it("queues an ai_task_run job only with jobs installed", () => {
    expect(body()).not.toContain("enqueue_job");
    expect(rendered(["jobs"])).toContain("queue => 'ai_task_run'");
  });

  it("references agents when installed", () => {
    expect(body()).not.toContain('"agents" ("id")');
    expect(rendered(["agents"])).toContain(
      'references "better_supabase"."agents" ("id") on delete set null',
    );
  });

  it("fails stale runs after staleAfter", () => {
    expect(
      body({ "ai-tasks": { options: { staleAfter: "2 hours" } } }),
    ).toContain("interval '2 hours'");
    expect(() =>
      moduleBody("ai-tasks", {
        modules: { "ai-tasks": { options: { staleAfter: "x" } } },
      }),
    ).toThrow(/staleAfter/);
    expect(() =>
      moduleBody("ai-tasks", {
        modules: { "ai-tasks": { options: { queue: "Bad" } } },
      }),
    ).toThrow(/queue/);
  });

  it("keeps the scheduler functions to the service role", () => {
    const sql = body();
    for (const name of [
      "claim_due_ai_tasks",
      "schedule_ai_tasks",
      "start_ai_task_run",
      "finish_ai_task_run",
    ]) {
      expect(sql).toMatch(
        new RegExp(
          `revoke execute on function "better_supabase"."${name}"\\([^)]*\\) from public, anon, authenticated`,
        ),
      );
    }
  });
});
