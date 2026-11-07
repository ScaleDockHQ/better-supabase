import { describe, expect, it } from "vitest";

import type { BlockSqlFile } from "../../src/sql/index.ts";

import {
  extraColumnsFiles,
  extraColumnsOptions,
  schemasDirOf,
  withoutOptionKeys,
} from "../../src/cli/codemod-extra-columns.ts";

const rendered: BlockSqlFile[] = [
  {
    module: "tags",
    kind: "schema",
    path: "supabase/schemas/_better_supabase/900_tags.sql",
    contents: `-- @bsb-block tags@1 managed
alter table "better_supabase"."tags" add column if not exists "region" text not null default 'eu';
alter table "better_supabase"."tag_links" add column if not exists "weight" integer;`,
  },
];

const options = {
  tags: { extraColumns: { region: "text not null default 'eu'" } },
  calendar: { other: 1 },
};

describe("extraColumnsOptions", () => {
  it("lists the extraColumns options with their columns", () => {
    expect(
      extraColumnsOptions({
        tags: {
          extraColumns: { a: "text" },
          calendarExtraColumns: { b: "int" },
        },
        x: { bounds: { c: "text" }, lineExtraColumns: "nope" },
      }),
    ).toEqual([
      { block: "tags", key: "extraColumns", columns: [["a", "text"]] },
      { block: "tags", key: "calendarExtraColumns", columns: [["b", "int"]] },
    ]);
  });
});

describe("withoutOptionKeys", () => {
  const keys = new Set(["extraColumns", "calendarExtraColumns"]);

  it("drops the property, its comma and its line, and leaves strings alone", () => {
    const text = `export default {
  blocks: {
    tags: {
      options: {
        extraColumns: { region: "text", note: "{ extraColumns: 1 }" },
        other: 1,
      },
    },
  },
  note: "extraColumns: { x }",
};
`;

    expect(withoutOptionKeys(text, keys)).toBe(`export default {
  blocks: {
    tags: {
      options: {
        other: 1,
      },
    },
  },
  note: "extraColumns: { x }",
};
`);
  });

  it("handles an only property and an inline one", () => {
    expect(
      withoutOptionKeys(
        `a: { options: { extraColumns: { x: "text" } } }`,
        keys,
      ),
    ).toBe("a: { options: { } }");
  });
});

describe("extraColumnsFiles", () => {
  it("writes <table>.ext.sql when no app file alters the table", () => {
    const { files, review } = extraColumnsFiles({
      options,
      rendered,
      sql: [],
      schemasDir: "/p/supabase/schemas",
      config: {
        path: "/p/better-supabase.config.ts",
        text: `tags: { options: { extraColumns: { region: "text not null default 'eu'" }, keep: 1 } },\n`,
      },
    });

    expect(review).toEqual([]);

    const ext = files.find((file) => file.path.endsWith("tags.ext.sql"));

    expect(ext?.policy).toBe("create");
    expect(ext?.path).toBe("/p/supabase/schemas/tags.ext.sql");
    expect(ext?.contents).toContain(
      `alter table "better_supabase"."tags"\n  add column "region" text not null default 'eu';`,
    );

    expect(
      files.find((file) => file.path.endsWith("config.ts"))?.contents,
    ).toBe(`tags: { options: { keep: 1 } },\n`);
  });

  it("appends to the app file that already alters the table", () => {
    const { files } = extraColumnsFiles({
      options: {
        tags: { extraColumns: { region: "text", weight: "integer" } },
      },
      rendered,
      sql: [
        {
          path: "/p/supabase/schemas/app.sql",
          text: "alter table better_supabase.tags add constraint tags_x check (true);\n",
        },
      ],
      schemasDir: "/p/supabase/schemas",
    });

    const edit = files.find((file) => file.path.endsWith("app.sql"));

    expect(edit?.policy).toBe("edit");
    expect(edit?.contents).toContain("add constraint tags_x check (true);");
    expect(edit?.contents).toContain(`add column "region" text`);
    expect(
      files.find((file) => file.path.endsWith("tag_links.ext.sql"))?.contents,
    ).toContain('"better_supabase"."tag_links"');
  });

  it("keeps an option whose column no block table adds", () => {
    const { files, review } = extraColumnsFiles({
      options: { tags: { extraColumns: { missing: "text" } } },
      rendered,
      sql: [],
      schemasDir: "/p/supabase/schemas",
      config: {
        path: "/p/c.ts",
        text: `tags: { options: { extraColumns: { missing: "text" } } }\n`,
      },
    });

    expect(files).toEqual([]);
    expect(review[0]?.message).toContain("no table of the block adds");
  });
});

describe("schemasDirOf", () => {
  it("steps out of the folder the block files go in", () => {
    expect(schemasDirOf("supabase/schemas/_better_supabase")).toBe(
      "supabase/schemas",
    );
    expect(schemasDirOf("supabase/schemas/")).toBe("supabase/schemas");
  });
});
