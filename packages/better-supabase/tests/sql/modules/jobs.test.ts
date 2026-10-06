import { describe, expect, it } from "vitest";

import {
  moduleBody,
  SQL_MODULES,
  upgradePlan,
} from "../../../src/sql/registry.ts";

const jobs = (options?: Readonly<Record<string, unknown>>) =>
  moduleBody("jobs", options ? { modules: { jobs: { options } } } : {})!;

describe("jobs module", () => {
  it("defaults to pgmq and pg_cron", () => {
    const sql = jobs();
    expect(sql).toContain("create extension if not exists pgmq;");
    expect(sql).toContain("return cron.schedule(");
    expect(sql).not.toContain("job_messages");
    expect(sql).not.toContain("job_schedules");
    expect(sql).toContain("'ensure_job_queue(text)'");
    expect(SQL_MODULES["jobs"]!.sql).toBe(sql);
  });

  it("renders the table backend without pgmq", () => {
    const sql = jobs({ backend: "table" });
    expect(sql).not.toContain("create extension if not exists pgmq");
    expect(sql).not.toMatch(/pgmq\.\w/);
    expect(sql).toContain(
      "create table if not exists better_supabase.job_messages",
    );
    expect(sql).toContain("for update skip locked");
    expect(sql).not.toContain("ensure_job_queue");
  });

  it("renders the drain scheduler with a schedules table", () => {
    const sql = jobs({ scheduler: "drain" });
    expect(sql).toContain(
      "create table if not exists better_supabase.job_schedules",
    );
    expect(sql).toContain("pg_timezone_names");
    expect(sql).not.toContain("cron.schedule(");
  });

  it("keeps one function contract for every option", () => {
    const signatures = (sql: string) =>
      [...sql.matchAll(/create or replace function (better_supabase\.\w+)/g)]
        .map((match) => match[1])
        .filter((name) => !/index_job_queue|ensure_job_queue/.test(name!))
        .toSorted((a, b) => a!.localeCompare(b!));
    const pgmq = signatures(jobs());
    expect(signatures(jobs({ backend: "table", scheduler: "drain" }))).toEqual(
      pgmq,
    );
  });

  it("rejects unknown options", () => {
    expect(() => jobs({ backend: "redis" })).toThrow(/backend/);
    expect(() => jobs({ scheduler: "cron" })).toThrow(/scheduler/);
  });

  it("drops the old schedule_job signature when upgrading from version 1", () => {
    const [plan] = upgradePlan([{ module: "jobs", version: 1 }]);
    expect(plan).toMatchObject({ module: "jobs", from: 1, to: 4 });
    expect(plan!.steps[0]!.sql).toContain(
      "drop function if exists better_supabase.schedule_job(text, text, text, jsonb);",
    );
    expect(plan!.steps[1]!.sql).toContain(
      "drop function if exists better_supabase.purge_job_archive(text, interval, integer);",
    );
    expect(plan!.steps[2]!.sql).toContain(
      "drop function if exists better_supabase.schedule_job(text, text, text, jsonb, text, timestamptz);",
    );
  });

  it("keeps a tenant per drain schedule and refuses one under pg_cron", () => {
    const drain = jobs({ scheduler: "drain" });
    expect(drain).toContain(
      "alter table better_supabase.job_schedules add column if not exists tenant text;",
    );
    expect(drain).toContain(
      "create or replace function better_supabase.list_schedules(name_prefix text default null, for_tenant text default null)",
    );
    expect(drain).toContain("where s.tenant = unschedule_tenant.tenant");
    const cron = jobs();
    expect(cron).toContain("pg_cron schedules have no tenant");
    expect(cron).toContain("from cron.job j where $1 is null");
  });

  it("dead-letters lost last attempts, jitters retries and replays dead letters", () => {
    for (const backend of ["pgmq", "table"]) {
      const sql = moduleBody("jobs", {
        modules: { jobs: { options: { backend } } },
      })!;
      expect(sql).toContain("The lease ran out on the last attempt");
      expect(sql).toContain(
        "1 + floor(random() * least(3600, 10 * power(2, attempt - 1)))::integer",
      );
      expect(sql).toContain("dead_older_than interval default '30 days'");
      expect(sql).toContain(
        "function better_supabase.replay_dead_job(queue text, job_id bigint)",
      );
      expect(sql).toContain("'replay_dead_job(text, bigint)'");
    }
    expect(moduleBody("jobs", {})).toContain(
      "perform pgmq.set_vt(queue, job_id, lease);",
    );
  });
});
