import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const sqlOf = (layout: Layout = {}): string =>
  renderBlocks(["trash"], layout)
    .filter((file) => file.module === "trash")
    .map((file) => file.contents)
    .join("\n");

describe("trash module", () => {
  it("reads deletedAt and title from config.subjects and skips types without deletedAt", () => {
    const sql = sqlOf({
      subjects: {
        doc: {
          table: "public.docs",
          idType: "uuid",
          title: "name",
          deletedAt: "deleted_at",
        },
        tag: { table: "public.tags" },
      },
    });

    expect(sql).toContain(`update "public"."docs" s set "deleted_at" = now()`);
    expect(sql).toContain(`returning s."name"::text into v_title;`);
    expect(sql).not.toContain(`"public"."tags"`);
    expect(sql).toContain("now() + make_interval(days => 30)");
  });

  it("refuses every type when no subject has deletedAt", () => {
    const sql = sqlOf();
    expect(sql).toContain("TRASH_UNSUPPORTED");
    expect(sql).not.toContain("for v_child in");
  });

  it("cascades to children and checks unique columns on restore", () => {
    const sql = sqlOf({
      modules: {
        trash: {
          options: {
            retentionDays: 0,
            subjects: {
              project: {
                table: "app.projects",
                tenant: "org_id",
                deletedAt: "deleted_at",
                unique: ["slug"],
                children: [{ type: "task", column: "project_id" }],
              },
              task: { table: "app.tasks", deletedAt: "removed_at" },
            },
          },
        },
      },
    });

    expect(sql).toContain(
      `where c."project_id"::text = trash_cascade.subject_id`,
    );
    expect(sql).toContain(`and c."removed_at" is null`);
    expect(sql).toContain(`o."slug" = s."slug"`);
    expect(sql).toContain(`join "app"."projects" o on o."org_id" = s."org_id"`);
    expect(sql).toContain("returning null::text into v_title;");
    expect(sql).not.toContain("make_interval(days");
  });

  it("writes nothing in custom mode", () => {
    expect(
      renderBlocks(["trash"], { modules: { trash: { mode: "custom" } } }).find(
        (file) => file.module === "trash",
      )?.contents ?? "",
    ).not.toContain("create or replace function");
  });

  it.each<readonly [string, unknown, RegExp]>([
    ["deletedAt", { doc: { table: "t" } }, /deletedAt/],
    ["title", { doc: { table: "t", deletedAt: "d", title: "A" } }, /title/],
    [
      "unique",
      { doc: { table: "t", deletedAt: "d", unique: "slug" } },
      /unique/,
    ],
    [
      "children list",
      { doc: { table: "t", deletedAt: "d", children: {} } },
      /children/,
    ],
    [
      "child entry",
      { doc: { table: "t", deletedAt: "d", children: [{ type: "doc" }] } },
      /children/,
    ],
    [
      "child type",
      {
        doc: {
          table: "t",
          deletedAt: "d",
          children: [{ type: "page", column: "doc_id" }],
        },
      },
      /not a subject type/,
    ],
  ])("rejects a bad %s", (_name, subjects, message) => {
    expect(() =>
      sqlOf({ modules: { trash: { options: { subjects } } } }),
    ).toThrow(message);
  });

  it("rejects a bad retention", () => {
    expect(() =>
      sqlOf({ modules: { trash: { options: { retentionDays: -1 } } } }),
    ).toThrow(/retentionDays/);
  });
});
