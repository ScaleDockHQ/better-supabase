import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/render.ts";

const body = (
  module: string,
  layout: Parameters<typeof renderModules>[1] = {},
): string =>
  renderModules([module], layout)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("hiring module", () => {
  it("binds applications to a pipeline per job before pipelines renders", () => {
    const files = renderModules(["hiring"]);
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
