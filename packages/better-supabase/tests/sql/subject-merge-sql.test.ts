import { describe, expect, it } from "vitest";

import type { Subject } from "../../src/sql/subjects.ts";

import { moduleContext } from "../../src/sql/module-context.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";
import { renderBlocks } from "../../src/sql/render.ts";
import {
  SUBJECT_MERGE_MARKER,
  moveSubjectRows,
  recordMergeFunction,
  subjectMergeHandler,
  subjectTableKey,
  withSubjectMergeFunction,
} from "../../src/sql/subject-merge-sql.ts";

describe("subjectTableKey", () => {
  it("puts a bare table in public and drops quotes", () => {
    expect(subjectTableKey("customers")).toBe("public.customers");
    expect(subjectTableKey('"app"."notes"')).toBe("app.notes");
  });
});

describe("moveSubjectRows", () => {
  const rows = { table: "app.notes", type: "subject_type", id: "subject_id" };

  it("moves every row of the type from drop to keep", () => {
    expect(moveSubjectRows(rows, "v_type")).toBe(
      "update app.notes x set subject_id = v_keep where x.subject_type = v_type and x.subject_id = v_drop;",
    );
  });

  it("first deletes the rows keep already has under the unique key", () => {
    const sql = moveSubjectRows(
      { ...rows, unique: ["actor", "emoji"] },
      "v_type",
    );

    expect(sql).toMatch(/^delete from app\.notes x where/);
    expect(sql).toContain(
      "y.actor is not distinct from x.actor and y.emoji is not distinct from x.emoji",
    );
    expect(sql).toContain("update app.notes x set subject_id = v_keep");
  });
});

describe("subjectMergeHandler", () => {
  const ctx = moduleContext("comments");

  it("renders nothing for a module without subjects", () => {
    expect(subjectMergeHandler(ctx, [], "select 1;")).toBe("");
  });

  it("maps each subject table to its types and marks the function", () => {
    const subjects: [string, Subject][] = [
      ["note", { table: "app.notes", extra: {} }],
      ["pinned_note", { table: "app.notes", extra: {} }],
      ["customer", { table: "customers", extra: {} }],
    ];

    const sql = subjectMergeHandler(ctx, subjects, "perform 1;");

    expect(sql).toContain("when 'app.notes' then array['note', 'pinned_note']");
    expect(sql).toContain("when 'public.customers' then array['customer']");
    expect(sql).toContain(
      '"better_supabase"."comments_subject_merge"(subject_table text, keep text, drop text)',
    );
    expect(sql).toContain(`is '${SUBJECT_MERGE_MARKER}'`);
    expect(sql).toContain("from public, anon, authenticated");
  });
});

describe("withSubjectMergeFunction", () => {
  it("defines the dispatcher once, only for SQL that calls it", () => {
    expect(withSubjectMergeFunction("select 1;")).toBe("select 1;");

    const calling =
      "perform better_supabase.merge_subject_refs('a.b', '1', '2');";

    const sql = withSubjectMergeFunction(calling);

    expect(sql).toContain(
      "create or replace function better_supabase.merge_subject_refs(",
    );
    expect(sql).toContain("p.proowner = ");
    expect(sql.endsWith(calling)).toBe(true);
    expect(withSubjectMergeFunction(sql)).toBe(sql);
  });
});

describe("recordMergeFunction", () => {
  const ctx = moduleContext("contacts");

  const merge = {
    name: "merge_people",
    table: "people",
    guard: (tenant: string) => `perform guard(${tenant});`,
    notFound: ["NOT_FOUND", "not found"],
    invalid: ["INVALID", "invalid"],
    clear: ["email"],
    record: (keep: string, drop: string) => `perform record(${keep}, ${drop});`,
    returns: (keep: string) => `(select ${keep})`,
  } as const;

  it("archives drop, fills keep and asks every module to move its rows", () => {
    const sql = recordMergeFunction(ctx, { ...merge, fill: ["phone"] });

    expect(sql).toContain('"email" = null, "merged_into" = merge_people.keep');
    expect(sql).toContain('"phone" = coalesce(x."phone", v_drop."phone")');
    expect(sql).toContain(
      "perform better_supabase.merge_subject_refs('better_supabase.people', merge_people.keep::text, merge_people.drop::text);",
    );
    expect(sql).toContain('perform guard(v_keep."tenant_id");');
    expect(sql).toContain(
      "perform record(merge_people.keep, merge_people.drop);",
    );
  });

  it("skips the fill update without fill columns and runs move first", () => {
    const sql = recordMergeFunction(ctx, {
      ...merge,
      fill: [],
      move: (keep, drop) => `perform move(${keep}, ${drop});`,
    });

    expect(sql).not.toContain(", v_drop.");
    expect(sql.indexOf("perform move(")).toBeLessThan(
      sql.indexOf("merge_subject_refs("),
    );
  });
});

describe("rendered modules", () => {
  const files = renderBlocks(
    Object.values(SQL_MODULES)
      .filter((module) => module.target === "schema")
      .map((module) => module.name),
    { subjects: { note: { table: "app.notes", idType: "uuid" } } },
  );

  it("marks a handler in every module that keeps rows per subject", () => {
    const marked = files
      .filter((file) => file.contents.includes(`is '${SUBJECT_MERGE_MARKER}'`))
      .map((file) => file.module);

    for (const module of [
      "messaging",
      "attachments",
      "reactions",
      "tags",
      "relations",
      "guests",
    ]) {
      expect(marked).toContain(module);
    }
  });

  it("defines the dispatcher in each file that calls it", () => {
    const callers = files.filter((file) =>
      file.contents.includes("perform better_supabase.merge_subject_refs("),
    );

    expect(callers.map((file) => file.module)).toContain("contacts");
    expect(
      callers.filter(
        (file) =>
          !file.contents.includes(
            "create or replace function better_supabase.merge_subject_refs(",
          ),
      ),
    ).toEqual([]);
  });
});
