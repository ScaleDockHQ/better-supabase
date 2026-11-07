import { describe, expect, it } from "vitest";

import {
  extraColumnsFiles,
  extraColumnsOptions,
  schemasDirOf,
  withoutOptionKeys,
} from "../../src/cli/codemod-extra-columns.ts";

const tableOf = (block: string, key: string): string | undefined => {
  if (block !== "tags") {
    return undefined;
  }

  return key === "extraColumns"
    ? "better_supabase.tags"
    : key === "linkExtraColumns"
      ? "better_supabase.tag_links"
      : undefined;
};

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

  it("drops several properties, last first", () => {
    const text = `a: { extraColumns: { x: "text" }, calendarExtraColumns: { y: "text" }, keep: 1 }`;

    expect(withoutOptionKeys(text, keys)).toBe("a: { keep: 1 }");
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
      tableOf,
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
        tags: {
          extraColumns: { region: "text" },
          linkExtraColumns: { weight: "integer" },
        },
      },
      tableOf,
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
      options: { tags: { unknownExtraColumns: { missing: "text" } } },
      tableOf,
      sql: [],
      schemasDir: "/p/supabase/schemas",
      config: {
        path: "/p/c.ts",
        text: `tags: { options: { unknownExtraColumns: { missing: "text" } } }\n`,
      },
    });

    expect(files).toEqual([]);
    expect(review[0]?.message).toContain("this release has no table");
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

describe("extraColumnsFiles over a table the app creates", () => {
  it("lists the columns in the table comment", () => {
    const { files } = extraColumnsFiles({
      options: { tags: { extraColumns: { region: "text" } } },
      tableOf,
      sql: [
        {
          path: "/p/supabase/schemas/tags.sql",
          text: `create table "better_supabase"."tags" ("id" uuid, "region" text);\ncomment on table "better_supabase"."tags" is 'Labels.';\n`,
        },
      ],
      schemasDir: "/p/supabase/schemas",
    });

    expect(files).toHaveLength(1);
    expect(files[0]?.contents).toContain("is 'Labels.\n@bsb fields region';");
  });

  it("adds a comment when the table has none", () => {
    const { files } = extraColumnsFiles({
      options: { tags: { extraColumns: { region: "text", weight: "int" } } },
      tableOf,
      sql: [
        {
          path: "/p/supabase/schemas/tags.sql",
          text: `create table better_supabase.tags (id uuid, region text, weight int);\n`,
        },
      ],
      schemasDir: "/p/supabase/schemas",
    });

    expect(files[0]?.contents).toContain(
      `comment on table "better_supabase"."tags" is '@bsb fields region, weight';`,
    );
  });
});
