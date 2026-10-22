import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const sqlOf = (layout: Layout = {}): string =>
  renderBlocks(["versions"], layout)
    .filter((file) => file.module === "versions")
    .map((file) => file.contents)
    .join("\n");

const withSubjects = (subjects: unknown, options: object = {}): Layout => ({
  modules: { versions: { options: { subjects, ...options } } },
});

describe("versions module", () => {
  it("restores through columns, an apply function, or not at all", () => {
    const sql = sqlOf(
      withSubjects({
        doc: { table: "public.docs", idType: "uuid", columns: ["title"] },
        page: { table: "app.pages", apply: "app.apply_page" },
        file: { table: "public.files" },
      }),
    );

    expect(sql).toContain(
      `update "public"."docs" s set "title" = r."title"\n      from jsonb_populate_record(null::"public"."docs", v_content) r`,
    );
    expect(sql).toContain(
      `perform "app"."apply_page"(v_subject_id, v_content);`,
    );
    expect(sql).toContain("VERSION_RESTORE_UNSUPPORTED");
    expect(sql).toContain(`e.key = any ('{title}'::text[]);`);
  });

  it("names an apply function in public without a schema", () => {
    expect(
      sqlOf(withSubjects({ doc: { table: "docs", apply: "apply_doc" } })),
    ).toContain(`perform public."apply_doc"(v_subject_id, v_content);`);
  });

  it("refuses restores when no subject can take one", () => {
    const sql = sqlOf(withSubjects({ file: { table: "public.files" } }));
    expect(sql).not.toContain("versions_restoring', 'on'");
  });

  it("adds auto and freeze triggers", () => {
    const sql = sqlOf(
      withSubjects({
        note: {
          table: "public.notes",
          columns: ["text", "title"],
          auto: true,
          freeze: { column: "status", values: ["sent", "paid"] },
        },
      }),
    );

    expect(sql).toContain(
      `after insert or update of "text", "title" on "public"."notes"`,
    );
    expect(sql).toContain(
      `after insert or update of "status" on "public"."notes"`,
    );
    expect(sql).toContain(
      `('note', 'id', 'organization_id', 'text,title', 'status', 'sent,paid')`,
    );
  });

  it("uses the keep and debounce options", () => {
    const sql = sqlOf(withSubjects(undefined, { keep: 7, debounce: 60 }));
    expect(sql).toContain("limit 7");
    expect(sql).toContain("make_interval(secs => 60)");
  });

  it("checks the subject's write permission on restore", () => {
    const sql = sqlOf({
      subjects: {
        doc: {
          table: "public.docs",
          permissions: { read: "docs.read", write: "docs.write" },
        },
      },
    });

    expect(sql).toContain(
      `when 'doc' then coalesce(better_supabase.can('tenant', v_tenant, 'docs.write'), false)`,
    );
  });

  it("writes nothing in custom mode", () => {
    expect(
      renderBlocks(["versions"], {
        modules: { versions: { mode: "custom" } },
      }).find((file) => file.module === "versions")?.contents ?? "",
    ).not.toContain("create or replace function");
  });

  it.each<readonly [string, unknown, object, RegExp]>([
    ["columns", { doc: { table: "t", columns: "a" } }, {}, /columns must be/],
    ["column names", { doc: { table: "t", columns: ["A b"] } }, {}, /columns/],
    ["apply", { doc: { table: "t", apply: "drop table" } }, {}, /apply must/],
    ["auto", { doc: { table: "t", columns: ["a"], auto: "yes" } }, {}, /auto/],
    [
      "auto without columns",
      { doc: { table: "t", auto: true } },
      {},
      /columns/,
    ],
    [
      "freeze shape",
      { doc: { table: "t", columns: ["a"], freeze: 1 } },
      {},
      /freeze/,
    ],
    [
      "freeze column",
      {
        doc: {
          table: "t",
          columns: ["a"],
          freeze: { column: "A", values: ["x"] },
        },
      },
      {},
      /freeze/,
    ],
    [
      "freeze values",
      {
        doc: {
          table: "t",
          columns: ["a"],
          freeze: { column: "s", values: ["a,b"] },
        },
      },
      {},
      /values/,
    ],
    ["keep", undefined, { keep: 0 }, /keep/],
    ["debounce", undefined, { debounce: -1 }, /debounce/],
  ])("rejects bad %s", (_name, subjects, options, message) => {
    expect(() => sqlOf(withSubjects(subjects, options))).toThrow(message);
  });

  it("restores only the named fields over the row's current values", () => {
    const sql = sqlOf(
      withSubjects({
        doc: { table: "public.docs", idType: "uuid", columns: ["title"] },
      }),
    );

    expect(sql).toContain(
      'restore_version"(version_id uuid, fields text[] default null)',
    );
    expect(sql).toContain("VERSION_FIELD_UNKNOWN");
    expect(sql).toContain("VERSION_FIELDS_EMPTY");
    expect(sql).toContain(
      "v_content := v_current || (\n      select jsonb_object_agg(e.key, e.value) from jsonb_each(v_content) e\n      where e.key = any (restore_version.fields)",
    );
  });

  it("keeps app tables with subject.versions next to the listed subjects", () => {
    const sql = sqlOf({
      subjects: {
        project: {
          table: "public.projects",
          idType: "uuid",
          versions: { columns: ["name"], auto: true },
        },
      },
      modules: {
        versions: {
          options: {
            subjects: { doc: { table: "public.docs", columns: ["title"] } },
          },
        },
      },
    });

    expect(sql).toContain(`update "public"."projects" s set "name" = r."name"`);
    expect(sql).toContain(
      `after insert or update of "name" on "public"."projects"`,
    );
  });
});
