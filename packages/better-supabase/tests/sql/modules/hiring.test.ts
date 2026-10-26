import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const body = (
  module: string,
  layout: Parameters<typeof renderBlocks>[1] = {},
): string =>
  renderBlocks([module], layout)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("hiring module", () => {
  it("binds applications to a pipeline per job before pipelines renders", () => {
    const files = renderBlocks(["hiring"]);
    const modules = files.map((file) => file.module);
    expect(modules.indexOf("hiring")).toBeLessThan(
      modules.indexOf("pipelines"),
    );

    const pipelines = files
      .filter((file) => file.module === "pipelines")
      .map((file) => file.contents)
      .join("\n");

    expect(pipelines).toContain(
      'create trigger bsb_pipeline_application before insert or update of "stage_id", "pipeline_id", "owner_user_id" on "better_supabase"."applications"',
    );
    expect(pipelines).toContain('new."job_id"::text');
  });

  it("checks the per-action keys and inserts required extra columns", () => {
    const sql = body("hiring", {
      modules: {
        hiring: {
          permissions: {
            create: "hiring.apply",
            score: "hiring.score",
            jobsCreate: "jobs.create",
            jobsUpdate: "jobs.update",
          },
          options: { extraColumns: { slug: "text not null" } },
        },
      },
    });

    expect(sql).toContain("'hiring.apply'");
    expect(sql).toContain("'hiring.score'");
    expect(sql).toContain("(save_job.job is null and");
    expect(sql).toContain("'jobs.create'");
    expect(sql).toContain("'jobs.update'");
    expect(sql).toMatch(/"status", "slug"\)\n\s+values \(/u);
    expect(sql).toContain(
      `(jsonb_populate_record(null::"better_supabase"."job_openings", coalesce(save_job.attrs -> 'fields', '{}'::jsonb)))."slug"`,
    );

    const update = body("hiring", {
      modules: { hiring: { permissions: { jobsUpdate: "jobs.update" } } },
    });

    expect(update).toContain("'jobs.update'");
    expect(update).toContain("'hiring.manage'");
  });

  it("takes another candidate type and renders nothing in custom mode", () => {
    expect(
      body("hiring", {
        modules: { hiring: { options: { candidate: "contact" } } },
      }),
    ).toContain("coalesce(apply_to_job.candidate ->> 'type', 'contact')");
    expect(
      body("hiring", { modules: { hiring: { mode: "custom" } } }),
    ).not.toContain("apply_to_job");
  });
});
