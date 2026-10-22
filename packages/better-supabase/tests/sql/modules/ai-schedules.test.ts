import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { moduleBody, renderBlocks } from "../../../src/sql/render.ts";

const body = (modules: AnyBlocksConfig = {}) =>
  moduleBody("ai-schedules", { modules })!;

const rendered = (names: readonly string[]) =>
  renderBlocks([...names, "ai-schedules"], { modules: {} })
    .filter((file) => file.module === "ai-schedules")
    .map((file) => file.contents)
    .join("\n");

describe("ai-schedules module", () => {
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
    expect(rendered(["queue"])).toContain("queue => 'ai_task_run'");
  });

  it("references agents when installed", () => {
    expect(body()).not.toContain('"agents" ("id")');
    expect(rendered(["agents"])).toContain(
      'references "better_supabase"."agents" ("id") on delete set null',
    );
  });

  it("fails stale runs after staleAfter", () => {
    expect(
      body({ "ai-schedules": { options: { staleAfter: "2 hours" } } }),
    ).toContain("interval '2 hours'");
    expect(() =>
      moduleBody("ai-schedules", {
        modules: { "ai-schedules": { options: { staleAfter: "x" } } },
      }),
    ).toThrow(/staleAfter/);
    expect(() =>
      moduleBody("ai-schedules", {
        modules: { "ai-schedules": { options: { queue: "Bad" } } },
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
