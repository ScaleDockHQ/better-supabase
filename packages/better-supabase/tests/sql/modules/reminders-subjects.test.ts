import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";

const sqlOf = (modules: AnyBlocksConfig = {}): string =>
  renderBlocks(["reminders"], { modules })
    .filter((file) => file.module === "reminders")
    .map((file) => file.contents)
    .join("\n");

const TASKS = { table: "public.tasks", idType: "uuid", at: "due_at" };

describe("reminders on subjects", () => {
  it("takes a one-time reminder and schedules it once", () => {
    const sql = sqlOf();

    expect(sql).toContain("remind_at timestamptz default null");
    expect(sql).toContain(
      `alter table "better_supabase"."reminders" add column if not exists "remind_at" timestamptz;`,
    );
    expect(sql).toContain(
      `select r."id", r."remind_at", 'UTC'::text, 'FREQ=DAILY;COUNT=1'::text, 0,`,
    );
    expect(sql).toContain(
      `drop function if exists "better_supabase"."save_reminder"(uuid, text, text, integer);`,
    );
    expect(sql).not.toContain("REMINDER_SUBJECT_UNSUPPORTED");
  });

  it("counts back from a subject's at column without a rule", () => {
    const sql = sqlOf({ reminders: { on: { task: TASKS } } });

    expect(sql).toContain(`select r."id", s."due_at"::timestamptz`);
    expect(sql).toContain(
      `join "public"."tasks" s on s."id" = (r."subject_id")::uuid`,
    );
    expect(sql).toContain("hint = 'REMINDER_SUBJECT_UNSUPPORTED'");
    expect(sql).toContain("hint = 'REMINDER_SUBJECT_NOT_FOUND'");
  });

  it("refuses an at that isn't a column name", () => {
    expect(() =>
      sqlOf({ reminders: { on: { task: { ...TASKS, at: "due at" } } } }),
    ).toThrow(/on\.task\.at must be a column name/u);
  });

  it("keeps the old signature on a table without remind_at", () => {
    const sql = sqlOf({
      reminders: { columns: { reminders: { remindAt: null } } },
    });

    expect(sql).not.toContain("remind_at");
    expect(sql).toContain(
      `create or replace function "better_supabase"."save_reminder"(tenant uuid, subject_type text, subject_id text, offset_minutes integer)`,
    );
  });
});
