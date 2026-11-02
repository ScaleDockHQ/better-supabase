import { describe, expect, it } from "vitest";

import type { SubjectsConfig } from "../../../src/config/index.ts";

import { PIPELINE_VARIANTS } from "../../../src/sql/modules/pipelines-seeds.ts";
import { renderBlocks } from "../../../src/sql/render.ts";

const SUBJECTS: SubjectsConfig = {
  deal: { table: "public.deals" },
  candidate: { table: "public.candidates" },
  application: { table: "hr.applications" },
};

const open = { open: "open", won: "success" };

const render = (on: Record<string, unknown>): string =>
  renderBlocks(["pipelines"], {
    subjects: SUBJECTS,
    // SAFETY: the test passes plain option objects the module parses.
    modules: { pipelines: { on: on as never } },
  })
    .filter((file) => file.module === "pipelines")
    .map((file) => file.contents)
    .join("\n");

const seedFunction = (sql: string): string => {
  const start = sql.search(
    /create or replace function [^\n]*"seed_pipelines_defaults"\(/,
  );

  return start === -1 ? "" : sql.slice(start, sql.indexOf("\n$$;", start));
};

const deal = {
  categories: open,
  variant: "b2b-sales",
  stages: [
    { key: "lead", name: "Lead", category: "open", probability: 10 },
    { key: "won", name: "Won", category: "won" },
  ],
};

const candidate = {
  categories: { active: "open", hired: "success" },
  stages: [
    { key: "applied", name: "Applied", category: "active" },
    { key: "hired", name: "Hired", category: "hired" },
  ],
};

describe("pipeline seeds", () => {
  it("names the variants presets can reference", () => {
    expect(PIPELINE_VARIANTS).toEqual(["b2b-sales", "recruiting"]);
  });

  it("declares the default pipeline and stages of an unscoped binding", () => {
    const body = seedFunction(render({ deal }));

    expect(body).toContain("'deal', null, 'default', 'Default'");
    expect(body).toContain("'lead', 'Lead', ('open'), ('open')");
    expect(body).toMatch(/'lead', 10\n/);
    expect(body.match(/where not exists/g)).toHaveLength(3);
  });

  it("seeds a variant binding for its variant and when none is named", () => {
    const body = seedFunction(render({ deal }));

    expect(body).toContain("(p_variant is null or p_variant = 'b2b-sales')");
  });

  it("seeds a binding without a variant for every call", () => {
    const body = seedFunction(render({ candidate }));

    expect(body).not.toMatch(/p_variant (is|=)/);
    expect(body).toContain("'Applied'");
  });

  it("keeps separate variants apart", () => {
    const body = seedFunction(
      render({ deal, candidate: { ...candidate, variant: "recruiting" } }),
    );

    expect(body).toContain("p_variant = 'b2b-sales'");
    expect(body).toContain("p_variant = 'recruiting'");
    expect(body.indexOf("p_variant = 'b2b-sales'")).not.toBe(
      body.indexOf("p_variant = 'recruiting'"),
    );
  });

  it("matches the pipeline of the same type and organization, unscoped", () => {
    const body = seedFunction(render({ deal }));

    expect(body).toContain(
      'x."tenant_id" = p_tenant and x."subject_type" = \'deal\' and x."scope_id" is null and x."key" = \'default\'',
    );
  });

  it("leaves scoped bindings to the first use", () => {
    const sql = render({
      application: { ...candidate, scope: "job_id", variant: "recruiting" },
    });

    expect(seedFunction(sql)).toBe("");
    expect(sql).toContain(
      "('applied', 'Applied', 'active', 'open', null::smallint",
    );
    expect(sql).not.toContain("seed_pipelines_defaults");
  });

  it("makes default_pipeline apply the declared defaults", () => {
    const sql = render({ deal, candidate });

    expect(sql).toContain(
      "\"seed_pipelines_defaults\"(default_pipeline.tenant, 'b2b-sales')",
    );
    expect(sql).toContain(
      '"seed_pipelines_defaults"(default_pipeline.tenant, null)',
    );
    expect(sql).toContain("exception when unique_violation then");
    expect(sql).toContain(
      'create or replace function "better_supabase"."default_pipeline"(tenant uuid, subject_type text, scope_id text)',
    );
  });

  it("refuses a variant name that is not lowercase words", () => {
    expect(() => render({ deal: { ...deal, variant: "B2B Sales" } })).toThrow(
      /variant must be a lowercase name/,
    );
  });

  it("renders no seed function without bindings", () => {
    expect(seedFunction(render({}))).toBe("");
  });
});
