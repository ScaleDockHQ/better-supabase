import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/render.ts";

const render = (
  layout: Parameters<typeof renderModules>[1] = {},
  extra: readonly string[] = [],
) => renderModules(["deals", ...extra], layout);

const body = (
  module: string,
  files: ReturnType<typeof renderModules>,
): string =>
  files
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("deals module", () => {
  it("renders the deals table before pipelines binds it", () => {
    const modules = render().map((file) => file.module);
    expect(modules.indexOf("deals")).toBeLessThan(modules.indexOf("pipelines"));
    const pipelines = body("pipelines", render());
    expect(pipelines).toContain(
      'create trigger bsb_pipeline_deal before insert or update of "stage_id", "pipeline_id", "owner_user_id" on "better_supabase"."deals"',
    );
    expect(pipelines).toContain(
      "('closed_won', 'Closed won', 'won', 'success', 100::smallint",
    );
  });

  it("merges an app's binding over the default", () => {
    const pipelines = body(
      "pipelines",
      render({
        modules: {
          pipelines: {
            options: {
              subjects: {
                deal: {
                  stages: [
                    { key: "lead", name: "Lead", category: "open" },
                    { key: "won", name: "Won", category: "won" },
                  ],
                },
              },
            },
          },
        },
      }),
    );

    expect(pipelines).toContain("('lead', 'Lead', 'open', 'open'");
    expect(pipelines).not.toContain("'qualified'");
    expect(pipelines).toContain("bsb_pipeline_status_deal");
  });

  it("scopes reads to the team without readAll and uses number-sequences when configured", () => {
    const scoped = body(
      "deals",
      render({ modules: { deals: { options: { readAll: false } } } }),
    );

    expect(scoped).toContain("deal_members");
    expect(scoped).toMatch(
      /create policy deals_read[\s\S]*owner_user_id" = auth.uid\(\)/,
    );

    const numbered = body(
      "deals",
      render(
        {
          modules: {
            "number-sequences": {
              options: {
                entities: { deal: { period: "none", format: "D-{n}" } },
              },
            },
          },
        },
        ["number-sequences"],
      ),
    );

    expect(numbered).toContain("format_assigned_number('D-{n}'");
    expect(body("deals", render())).toContain("'DEAL-' || v_seq::text");
  });

  it("reads the next step from engagements when installed", () => {
    expect(body("deals", render({}, ["engagements"]))).toContain(
      "next_engagement\"('deal'",
    );
    expect(body("deals", render())).not.toContain("next_engagement");
  });

  it("renders nothing in custom mode and rejects bad option lists", () => {
    expect(
      body("deals", render({ modules: { deals: { mode: "custom" } } })),
    ).not.toContain("create_deal");
    expect(() =>
      render({ modules: { deals: { options: { motions: ["New"] } } } }),
    ).toThrow(/lowercase names/);
  });
});
