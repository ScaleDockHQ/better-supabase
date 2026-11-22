import { describe, expect, it } from "vitest";

import type { CodemodProject } from "../../src/cli/codemod.ts";
import type { BetterSupabaseConfig } from "../../src/config/index.ts";

import { withTableTag } from "../../src/cli/codemod-extra-columns.ts";
import {
  tableFactMoves,
  tableTagFiles,
  withoutExemptEntry,
} from "../../src/cli/codemod-table-tags.ts";
import { CODEMODS } from "../../src/cli/codemod.ts";
import { resolveConfig } from "../../src/config/index.ts";
import { grantTag, lifecycleTag } from "../../src/sql/index.ts";

const CONFIG = `export default defineConfig({
  database: {
    expose: {
      invoices: { authenticated: ["select", "update(title)"], anon: ["select"] },
    },
  },
  blocks: {
    audit: {
      options: {
        exempt: [
          { table: "public.scratch", reason: "rebuilt nightly" },
          { table: "public.*_archive", reason: "archives" },
        ],
      },
    },
    "data-lifecycle": {
      options: {
        tables: {
          invoices: { user: "owner_id", export: false, omit: ["notes"] },
        },
      },
    },
  },
});
`;

const input: BetterSupabaseConfig = {
  database: {
    expose: {
      invoices: {
        authenticated: ["select", "update(title)"],
        anon: ["select"],
      },
    },
  },
  blocks: {
    audit: {
      options: {
        exempt: [
          { table: "public.scratch", reason: "rebuilt nightly" },
          { table: "public.*_archive", reason: "archives" },
        ],
      },
    },
    "data-lifecycle": {
      options: {
        tables: {
          invoices: { user: "owner_id", export: false, omit: ["notes"] },
        },
      },
    },
  },
};

const project = (sql: CodemodProject["sql"]): CodemodProject => ({
  config: resolveConfig(input, "/project"),
  sql,
  configFile: "/project/better-supabase.config.ts",
  configText: CONFIG,
});

const schema = (name: string): CodemodProject["sql"][number] => ({
  path: `/project/supabase/schemas/${name}.sql`,
  text: `create table public.${name} (id uuid primary key);\n`,
});

describe("tableFactMoves", () => {
  it("writes a tag line for each fact a comment can hold", () => {
    const { moves, review } = tableFactMoves(resolveConfig(input, "/project"));

    expect(review).toEqual([]);
    expect(moves.map((move) => [move.table, move.line])).toEqual([
      ["public.scratch", '@bsb audit-exempt reason="rebuilt nightly"'],
      [
        "public.invoices",
        "@bsb data-lifecycle user=owner_id export=false omit=notes",
      ],
      [
        "public.invoices",
        '@bsb grant anon=select authenticated="select,update(title)"',
      ],
    ]);
  });
});

describe("withTableTag", () => {
  it("adds a tag to the block a comment has and starts one otherwise", () => {
    const created = withTableTag(
      "create table a.b (id int);",
      "a.b",
      "@bsb x=1",
    );

    const added = withTableTag(created, "a.b", "@bsb y=2");

    expect(created).toContain(`comment on table "a"."b" is '@bsb x=1';`);
    expect(added).toContain(`is '@bsb x=1; y=2';`);
    expect(
      withTableTag("comment on table a.b is 'Text.';", "a.b", "@bsb y=2"),
    ).toContain("'Text.\n@bsb y=2'");
  });
});

describe("withoutExemptEntry", () => {
  it("cuts the element for the table and leaves the others", () => {
    const next = withoutExemptEntry(CONFIG, "public.scratch")!;

    expect(next).not.toContain("public.scratch");
    expect(next).toContain("public.*_archive");
    expect(withoutExemptEntry(CONFIG, "public.missing")).toBeUndefined();
  });
});

describe("table-tags codemod", () => {
  it("is registered after record-types", () => {
    expect(Object.keys(CODEMODS).indexOf("table-tags")).toBe(
      Object.keys(CODEMODS).indexOf("record-types") + 1,
    );
  });

  it("moves the facts into comments and drops the config entries", () => {
    const { files, review } = tableTagFiles(
      project([schema("invoices"), schema("scratch")]),
    );

    const byName = (name: string): string =>
      files.find((file) => file.path.endsWith(name))!.contents;

    expect(byName("invoices.sql")).toContain(
      "@bsb data-lifecycle user=owner_id export=false omit=notes",
    );
    expect(byName("invoices.sql")).toContain(
      '; grant anon=select authenticated="select,update(title)"',
    );

    const comment = /comment on table [^']*'([^']*)'/u.exec(
      byName("invoices.sql"),
    )![1]!;

    expect(grantTag(comment)).toEqual({
      anon: ["select"],
      authenticated: ["select", "update(title)"],
    });
    expect(lifecycleTag(comment)).toEqual({
      user: "owner_id",
      export: false,
      omit: ["notes"],
    });
    expect(byName("scratch.sql")).toContain(
      '@bsb audit-exempt reason="rebuilt nightly"',
    );

    const config = byName("better-supabase.config.ts");

    expect(config).not.toContain("owner_id");
    expect(config).not.toContain("public.scratch");
    expect(config).not.toContain("authenticated");
    expect(config).toContain("public.*_archive");
    expect(review).toEqual([]);
  });

  it("keeps a fact whose table no schema file creates", () => {
    const { files, review } = tableTagFiles(project([schema("invoices")]));
    const config = files.find((file) => file.path.endsWith(".ts"))!;

    expect(config.contents).toContain("public.scratch");
    expect(review).toEqual([
      expect.objectContaining({
        message: expect.stringContaining("no schema file creates the table"),
      }),
    ]);
  });

  it("leaves a fact a comment already holds", () => {
    const { review } = tableTagFiles(
      project([
        {
          path: "/project/supabase/schemas/invoices.sql",
          text: "create table public.invoices (id uuid primary key);\ncomment on table public.invoices is '@bsb grant authenticated=select; data-lifecycle user=owner_id';\n",
        },
        schema("scratch"),
      ]),
    );

    expect(review.map((line) => line.message)).toEqual([
      expect.stringContaining("already holds data-lifecycle"),
      expect.stringContaining("already holds grant"),
    ]);
  });
});
