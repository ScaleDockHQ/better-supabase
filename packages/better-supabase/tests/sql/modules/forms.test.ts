import { describe, expect, it } from "vitest";

import { customContracts, renderModules } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderModules>[1];

const sqlOf = (modules: readonly string[], layout: Layout = {}): string =>
  renderModules(modules, layout)
    .filter((file) => file.module === "forms")
    .map((file) => file.contents)
    .join("\n");

const withOptions = (options: Record<string, unknown>): Layout => ({
  modules: { forms: { options } },
});

describe("forms module", () => {
  it("keeps forms, versions and submissions and checks answers with pg_jsonschema", () => {
    const sql = sqlOf(["forms"]);

    for (const table of ["forms", "form_versions", "form_submissions"]) {
      expect(sql).toContain(
        `create table if not exists "better_supabase"."${table}"`,
      );
    }

    expect(sql).toContain("extensions.jsonschema_validation_errors(");
    expect(sql).toContain("hint = 'JSON_SCHEMA_INVALID'");
    expect(sql).toContain("FORM_DEFINITION_INVALID");
    expect(sql).toContain("https://json-schema.org/draft/2020-12/schema");
    expect(sql).toContain(
      `revoke execute on function "better_supabase"."form_submission_save"`,
    );
  });

  it("adds public forms only with share-links, rate limited by default", () => {
    expect(sqlOf(["forms"])).not.toContain("submit_public_form");
    const shared = sqlOf(["share-links", "forms"]);
    expect(shared).toContain(`"better_supabase"."submit_public_form"`);
    expect(shared).toContain("to anon");
    expect(shared).not.toContain("hit_rate_limit");
    const limited = sqlOf(["share-links", "rate-limit", "forms"]);
    expect(limited).toContain(`"better_supabase"."hit_rate_limit"('forms:'`);
    expect(limited).toContain("BS429");
    expect(
      sqlOf(
        ["share-links", "rate-limit", "forms"],
        withOptions({ publicLimit: false }),
      ),
    ).not.toContain("hit_rate_limit");
    expect(
      sqlOf(
        ["share-links", "rate-limit", "forms"],
        withOptions({ publicLimit: { max: 5, period: "PT10M" } }),
      ),
    ).toContain("5, 'PT10M'::interval");
  });

  it("copies custom fields in only when that module is installed", () => {
    expect(sqlOf(["forms"])).toContain(
      "customField needs the custom-fields module",
    );
    const fields = sqlOf(["custom-fields", "forms"]);
    expect(fields).toContain(`from "better_supabase"."field_definitions" d`);
    expect(fields).toContain(
      `to_regclass('"better_supabase"."field_options"')`,
    );
  });

  it("skips the options lookup when adopted custom fields have no options table", () => {
    const sql = sqlOf(["custom-fields", "forms"], {
      modules: {
        "custom-fields": {
          mode: "adopt",
          tables: { definitions: "app.field_defs", options: null },
        },
      },
    });

    expect(sql).toContain(`from "app"."field_defs" d`);
    expect(sql).not.toContain("to_regclass");
  });

  it("calls a handler per form key", () => {
    const sql = sqlOf(
      ["forms"],
      withOptions({
        handlers: { contact: "app.lead_from_submission", demo: "make_lead" },
      }),
    );

    expect(sql).toContain(`"app"."lead_from_submission"(v_row.`);
    expect(sql).toContain(`public."make_lead"(v_row.`);
    expect(sql).toContain("when 'contact' then");
  });

  it("rejects bad options", () => {
    expect(() => sqlOf(["forms"], withOptions({ handlers: "x" }))).toThrow(
      /handlers must map form keys/,
    );
    expect(() =>
      sqlOf(["forms"], withOptions({ handlers: { Contact: "public.x" } })),
    ).toThrow(/is not a form key/);
    expect(() =>
      sqlOf(["forms"], withOptions({ handlers: { contact: "drop table;" } })),
    ).toThrow(/must name a function/);
    expect(() =>
      sqlOf(
        ["forms"],
        withOptions({ publicLimit: { max: 0, period: "PT1H" } }),
      ),
    ).toThrow(/publicLimit/);
    expect(() =>
      sqlOf(
        ["forms"],
        withOptions({ publicLimit: { max: 2, period: "hourly" } }),
      ),
    ).toThrow(/publicLimit/);
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { forms: { mode: "custom" } } };
    expect(sqlOf(["forms"], custom).trim()).toBe("");
    const [contract] = customContracts(["forms"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual([
      "create_form",
      "publish_form_version",
      "get_form",
      "submit_form",
      "get_form_submission",
    ]);
  });

  it("works on adopted tables without creating them", () => {
    const sql = sqlOf(["forms"], {
      modules: {
        forms: {
          mode: "adopt",
          tables: {
            forms: "app.surveys",
            versions: "app.survey_versions",
            submissions: "app.survey_answers",
          },
          columns: { forms: { tenant: "org_id" } },
        },
      },
    });

    expect(sql).not.toMatch(
      /create table if not exists "?(app|better_supabase)"?\."?(surveys|form)/,
    );
    expect(sql).toContain(`"app"."surveys"`);
    expect(sql).toContain(`"org_id"`);
  });

  it("rejects a publicLimit that is not an object", () => {
    expect(() => sqlOf(["forms"], withOptions({ publicLimit: 5 }))).toThrow(
      /publicLimit/,
    );
    expect(() =>
      sqlOf(
        ["forms"],
        withOptions({ publicLimit: { max: 1.5, period: "PT1H" } }),
      ),
    ).toThrow(/publicLimit/);
  });
});
