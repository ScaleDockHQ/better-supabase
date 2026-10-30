import { describe, expect, it } from "vitest";

import { withBlockSubjects } from "../../../src/config/block-subjects.ts";
import { renderBlocks } from "../../../src/sql/render.ts";

type Layout = NonNullable<Parameters<typeof renderBlocks>[1]>;

const dataOf = (
  names: readonly string[],
  module: string,
  layout: Layout = {},
): string =>
  renderBlocks(names, layout)
    .filter(
      (file) =>
        file.module === module && file.contents.includes("@bsb-block-data"),
    )
    .map((file) => file.contents)
    .join("\n");

describe("subject type renames", () => {
  it("moves the old task type in every installed subject type column", () => {
    const sql = dataOf(["tasks", "relations", "comments"], "tasks");

    expect(sql).toContain(
      `update "better_supabase"."relations" set "source_type" = 'task' where "source_type" = 'work_item';`,
    );
    expect(sql).toContain(
      `update "better_supabase"."relations" set "target_type" = 'task' where "target_type" = 'work_item';`,
    );
    expect(sql).toMatch(
      /set "subject_type" = 'task' where "subject_type" = 'work_item';/,
    );
  });

  it("moves the old activity and policy types", () => {
    expect(dataOf(["activities", "relations"], "activities")).toContain(
      `set "source_type" = 'activity' where "source_type" = 'engagement';`,
    );
    expect(dataOf(["compliance", "relations"], "compliance")).toContain(
      `set "source_type" = 'compliance_policy' where "source_type" = 'policy';`,
    );
  });

  it("still resolves the old type in the subject dispatch", () => {
    const sql = renderBlocks(["tasks"], {
      subjects: withBlockSubjects({}, ["tasks"], {}),
    })
      .filter((file) => file.module === "subjects")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain("when 'task', 'work_item' then");
  });

  it("keeps the type of an install that names the entity", () => {
    const sql = dataOf(["tasks", "relations"], "tasks", {
      modules: { tasks: { entities: { task: { name: "ticket" } } } },
    });

    expect(sql).not.toContain("'work_item'");
  });

  it("keeps an old type the app's subjects still declare", () => {
    const sql = dataOf(["compliance", "relations"], "compliance", {
      subjects: { policy: { table: "public.policies" } },
    });

    expect(sql).not.toContain("where \"source_type\" = 'policy'");
  });
});
