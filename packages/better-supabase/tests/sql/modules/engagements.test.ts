import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/render.ts";

const sqlOf = (
  options: Record<string, unknown> = {},
  extra: readonly string[] = [],
): string =>
  renderModules(["engagements", ...extra], {
    subjects: {
      deal: { table: "public.deals" },
      note: { table: "public.notes", tenant: false },
    },
    modules: { engagements: { options } },
  })
    .filter((file) => file.module === "engagements")
    .map((file) => file.contents)
    .join("\n");

describe("engagements module", () => {
  it("checks every subject's tenant and readability", () => {
    const sql = sqlOf();
    expect(sql).toContain(
      `when 'deal' then exists (select 1 from "public"."deals" s where s."id"::text = (v_item ->> 'id') and s."organization_id"::text = v_tenant::text)`,
    );
    expect(sql).not.toContain(`when 'note' then`);
    expect(sql).toContain("'{call,email,meeting,note,task}'::text[]");
    expect(sql).not.toContain("engagement.assigned");
  });

  it("notifies an assigned owner with notifications installed", () => {
    expect(sqlOf({}, ["notifications"])).toContain(
      "'type', 'engagement.assigned'",
    );
  });

  it("takes configured types and rejects bad ones", () => {
    expect(sqlOf({ types: ["call", "visit"] })).toContain(
      "'{call,visit}'::text[]",
    );
    expect(() => sqlOf({ types: ["Visit"] })).toThrow(/lowercase names/);
  });
});

describe("engagements module, layouts", () => {
  it("renders nothing in custom mode and refuses every subject without a registry", () => {
    expect(
      renderModules(["engagements"], {
        modules: { engagements: { mode: "custom" } },
      })
        .filter((file) => file.module === "engagements")
        .map((file) => file.contents)
        .join(""),
    ).not.toContain("log_engagement");
    const sql = renderModules(["engagements"], {})
      .filter((file) => file.module === "engagements")
      .map((file) => file.contents)
      .join("\n");
    expect(sql).toContain("if not false then");
  });
});
