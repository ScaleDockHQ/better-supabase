import { describe, expect, it } from "vitest";

import { tenantsQuery } from "../../src/sql/index.ts";

describe("tenantsQuery", () => {
  it("is undefined without the organizations module", () => {
    expect(tenantsQuery({}, [], "acme")).toBeUndefined();
  });

  it("matches an adopted table without a slug by id", () => {
    const query = tenantsQuery(
      {
        modules: {
          organizations: {
            mode: "adopt",
            tables: { organizations: "app.teams" },
            columns: {
              organizations: { id: "team_id", slug: null, deletedAt: null },
            },
          },
        },
      },
      ["organizations"],
      "t1",
    );

    expect(query).toEqual({
      text: `select o."team_id"::text as id, null::text as slug, o."name"::text as name
from "app"."teams" o
where o."team_id"::text = $1
order by 2, 1`,
      values: ["t1"],
    });
    expect(
      tenantsQuery(
        {
          modules: {
            organizations: {
              mode: "adopt",
              tables: { organizations: "app.teams" },
              columns: { organizations: { slug: null, deletedAt: null } },
            },
          },
        },
        ["organizations"],
        "*",
      )?.text,
    ).not.toContain("where");
  });
});
