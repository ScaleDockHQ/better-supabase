import { describe, expect, it } from "vitest";

import type { SubjectsConfig } from "../../../src/config/index.ts";
import type { BlockSqlLayout } from "../../../src/sql/module-types.ts";

import { renderBlocks } from "../../../src/sql/render.ts";

const SUBJECTS: SubjectsConfig = {
  deal: { table: "public.deals", deletedAt: "deleted_at" },
  application: { table: "hr.applications" },
  note: { table: "public.notes", tenant: false },
};

const DEAL = {
  categories: { open: "open", won: "success", lost: "failure" },
  amount: "amount",
  currency: "currency",
  owner: "owner_id",
  enteredAt: "stage_entered_at",
  status: { column: "outcome", values: { won: "won", lost: "lost" } },
  stages: [
    { key: "lead", name: "Lead", category: "open", probability: 10 },
    { key: "won", name: "Won", category: "won", probability: 100 },
    { key: "lost", name: "Lost", category: "lost" },
  ],
};

const render = (
  subjects: Record<string, unknown>,
  extra: readonly string[] = [],
  layout: BlockSqlLayout = {},
): string =>
  renderBlocks(["pipelines", ...extra], {
    ...layout,
    subjects: SUBJECTS,
    modules: {
      ...layout.modules,
      pipelines: { ...layout.modules?.["pipelines"], options: { subjects } },
    },
  })
    .filter((file) => file.module === "pipelines")
    .map((file) => file.contents)
    .join("\n");

describe("pipelines module", () => {
  it("renders the tables and functions without bindings", () => {
    const sql = render({});
    expect(sql).toContain(
      'create table if not exists "better_supabase"."pipelines"',
    );
    expect(sql).toContain(
      'create table if not exists "better_supabase"."pipeline_stage_history"',
    );
    expect(sql).toContain(
      '"better_supabase"."pipeline_board"(subject_type text, pipeline uuid, owner uuid default null)',
    );
    expect(sql).not.toContain("bsb_pipeline_deal");
  });

  it("renders a trigger per bound subject that seeds the stage template", () => {
    const sql = render({
      deal: DEAL,
      application: {
        categories: { active: "open", hired: "success" },
        scope: "job_id",
      },
    });

    expect(sql).toContain(
      'create trigger bsb_pipeline_deal before insert or update of "stage_id", "pipeline_id", "owner_id" on "public"."deals"',
    );
    expect(sql).toContain(
      'create trigger bsb_pipeline_application before insert or update of "stage_id", "pipeline_id" on "hr"."applications"',
    );
    expect(sql).toContain("('lead', 'Lead', 'open', 'open', 10::smallint");
    expect(sql).toContain(
      "('active', 'Active', 'active', 'open', null::smallint",
    );
    expect(sql).toContain('new."job_id"::text');
    expect(sql).toContain('new."stage_entered_at" := now();');
    expect(sql).toContain(
      'create trigger bsb_pipeline_status_deal after insert or update of "stage_id"',
    );
    expect(sql).toContain("when 'won' then 'won' when 'lost' then 'lost'");
    expect(sql).toContain(
      'drop trigger if exists bsb_pipeline_status_application on "hr"."applications"',
    );
    expect(sql).toContain('and r."deleted_at" is null');
  });

  it("follows the owner and notifies watchers with notifications installed", () => {
    const sql = render({ deal: DEAL }, ["notifications"]);
    expect(sql).toContain(
      "-- The owner watches the record; a level they already chose stays.",
    );
    expect(sql).toContain("'type', 'pipeline.stage_changed'");
    expect(render({ deal: DEAL })).not.toContain(
      "The owner watches the record",
    );
  });

  it("drops the transitions table's function when the table is off", () => {
    const sql = render({}, [], {
      modules: { pipelines: { tables: { transitions: null } } },
    });

    expect(sql).not.toContain("set_pipeline_transitions");
    expect(sql).not.toContain("PIPELINE_TRANSITION_INVALID");
  });

  it.each([
    [{ deal: { categories: {} } }, /categories must map/],
    [{ deal: { categories: { won: "success" } } }, /needs an open category/],
    [{ deal: { categories: { open: "maybe" } } }, /open, success or failure/],
    [
      { deal: { categories: { open: "open" }, amount: "amount" } },
      /amount and currency go together/,
    ],
    [
      { deal: { categories: { open: "open" }, stage: "Stage Id" } },
      /must be a column name/,
    ],
    [
      {
        deal: {
          categories: { open: "open" },
          stages: [{ key: "a", name: "A", category: "won" }],
        },
      },
      /one of the categories/,
    ],
    [
      {
        deal: {
          categories: { open: "open", won: "success" },
          stages: [{ key: "a", name: "A", category: "won" }],
        },
      },
      /needs an open stage/,
    ],
    [
      {
        deal: {
          categories: { open: "open" },
          stages: [{ key: "a", name: "A", category: "open", probability: 101 }],
        },
      },
      /integer 0 to 100/,
    ],
    [
      {
        deal: {
          categories: { open: "open" },
          status: { column: "s", values: { won: "won" } },
        },
      },
      /no category/,
    ],
    [
      { task: { categories: { open: "open" } } },
      /register "task" in config.subjects/,
    ],
    [{ note: { categories: { open: "open" } } }, /needs a tenant column/],
  ])("rejects %j", (subjects, message) => {
    expect(() => render(subjects)).toThrow(message);
  });
});

describe("pipelines module, other layouts", () => {
  it("renders nothing in custom mode and no watch without a subscriptions table", () => {
    expect(
      renderBlocks(["pipelines"], {
        subjects: SUBJECTS,
        modules: { pipelines: { mode: "custom" } },
      })
        .filter((file) => file.module === "pipelines")
        .map((file) => file.contents)
        .join(""),
    ).not.toContain("create table");

    const sql = renderBlocks(["pipelines", "notifications"], {
      subjects: SUBJECTS,
      modules: {
        pipelines: { options: { subjects: { deal: DEAL } } },
        notifications: { tables: { subscriptions: null } },
      },
    })
      .filter((file) => file.module === "pipelines")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).not.toContain("The owner watches the record");
    expect(sql).toContain("'type', 'pipeline.stage_changed'");
  });
});
