import { describe, expect, it } from "vitest";

import { adoptedColumnProblems } from "../../src/sql/adopted-columns.ts";

describe("adoptedColumnProblems", () => {
  it("refuses a default optional column the adopted table does not declare", () => {
    const problems = adoptedColumnProblems(
      {
        organizations: {
          mode: "adopt",
          tables: { organizations: "public.organizations" },
        },
      },
      [
        {
          text: `create table public.organizations (
  id uuid primary key,
  name text not null,
  slug text
);`,
        },
      ],
      ["public"],
    );
    expect(problems.join("\n")).toContain("disabled_at");
    expect(problems.join("\n")).toContain("deleted_at");
  });

  it("passes when the missing columns are mapped to null", () => {
    expect(
      adoptedColumnProblems(
        {
          organizations: {
            mode: "adopt",
            tables: { organizations: "public.organizations" },
            columns: {
              organizations: {
                slug: null,
                createdBy: null,
                createdAt: null,
                updatedAt: null,
                deletedAt: null,
                disabledAt: null,
              },
            },
          },
        },
        [
          {
            text: `create table public.organizations (
  id uuid primary key,
  name text not null
);`,
          },
        ],
        ["public"],
      ),
    ).toEqual([]);
  });
});
