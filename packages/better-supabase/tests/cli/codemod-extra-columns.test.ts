import { describe, expect, it } from "vitest";

import type { BetterSupabaseConfig } from "../../src/config/index.ts";

import {
  extraColumnsCodemod,
  extraColumnsFiles,
  extraColumnsOptions,
  schemasDirOf,
  withoutOptionKeys,
} from "../../src/cli/codemod-extra-columns.ts";
import { primeSchemaFacts } from "../../src/cli/sql-facts.ts";
import { resolveConfig } from "../../src/config/index.ts";

const run = async (
  input: Parameters<typeof extraColumnsFiles>[0],
): Promise<ReturnType<typeof extraColumnsFiles>> => {
  await primeSchemaFacts(input.sql, "/p");

  return extraColumnsFiles(input);
};

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
  it("lists the extraColumns options with their columns", async () => {
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

  it("drops the property, its comma and its line, and leaves strings alone", async () => {
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

    expect(withoutOptionKeys(text, keys).text).toBe(`export default {
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

  it("drops several properties, last first", async () => {
    const text = `export default { blocks: { a: { options: { extraColumns: { x: "text" }, calendarExtraColumns: { y: "text" }, keep: 1 } } } };`;

    expect(withoutOptionKeys(text, keys).text).toBe(
      "export default { blocks: { a: { options: { keep: 1 } } } };",
    );
  });

  it("handles an only property and an inline one", async () => {
    expect(
      withoutOptionKeys(
        `export default { blocks: { a: { options: { extraColumns: { x: "text" } } } } };`,
        keys,
      ).text,
    ).toBe("export default { blocks: { a: { options: {} } } };");
  });

  it("keeps comments, follows a spread and a shorthand, and keeps CRLF", async () => {
    const text = [
      "const options = {",
      "  // the region",
      '  extraColumns: { region: "text" }, // moved',
      "  keep: 1, // stays",
      "};",
      "const tags = { options };",
      "export default {",
      "  // blocks",
      "  blocks: { tags },",
      "};",
      "",
    ].join("\r\n");

    const result = withoutOptionKeys(text, keys);

    expect(result.review).toEqual([]);
    expect(result.text).toContain("keep: 1, // stays");
    expect(result.text).toContain("// blocks");
    expect(result.text).not.toContain("extraColumns");
    expect(result.text).not.toContain("moved");
    expect(result.text).not.toMatch(/[^\r]\n/);
  });

  it("lists an option it cannot follow instead of skipping it", async () => {
    const text = `import { options } from "./options.ts";
export default { blocks: { tags: { options } } };
`;

    const result = extraColumnsFiles({
      options: { tags: { extraColumns: { region: "text" } } },
      tableOf: () => "better_supabase.tags",
      sql: [],
      schemasDir: "/p/supabase/schemas",
      config: { path: "/p/better-supabase.config.ts", text },
    });

    const line = result.review.find((entry) =>
      entry.message.includes("blocks.tags.options.extraColumns"),
    );

    expect(line?.message).toContain("remove it by hand");
    expect(result.files.some((file) => file.path.endsWith(".config.ts"))).toBe(
      false,
    );
  });
});

describe("extraColumnsFiles", () => {
  it("writes <table>.ext.sql when no app file alters the table", async () => {
    const { files, review } = await run({
      options,
      tableOf,
      sql: [],
      schemasDir: "/p/supabase/schemas",
      config: {
        path: "/p/better-supabase.config.ts",
        text: `export default { blocks: { tags: { options: { extraColumns: { region: "text not null default 'eu'" }, keep: 1 } } } };\n`,
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
    ).toBe(`export default { blocks: { tags: { options: { keep: 1 } } } };\n`);
  });

  it("appends to the app file that already alters the table", async () => {
    const { files } = await run({
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

  it("keeps an option whose column no block table adds", async () => {
    const { files, review } = await run({
      options: { tags: { unknownExtraColumns: { missing: "text" } } },
      tableOf,
      sql: [],
      schemasDir: "/p/supabase/schemas",
      config: {
        path: "/p/c.ts",
        text: `export default { blocks: { tags: { options: { unknownExtraColumns: { missing: "text" } } } } };\n`,
      },
    });

    expect(files).toEqual([]);
    expect(review[0]?.message).toContain("this release has no table");
  });
});

describe("schemasDirOf", () => {
  it("steps out of the folder the block files go in", async () => {
    expect(schemasDirOf("supabase/schemas/_better_supabase")).toBe(
      "supabase/schemas",
    );
    expect(schemasDirOf("supabase/schemas/")).toBe("supabase/schemas");
  });
});

describe("extraColumnsFiles over a table the app creates", () => {
  it("lists the columns in the table comment", async () => {
    const { files } = await run({
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

  it("adds a comment when the table has none", async () => {
    const { files } = await run({
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

describe("extra-columns codemod", () => {
  const run = (input: BetterSupabaseConfig, configText?: string) =>
    extraColumnsCodemod().project!({
      config: resolveConfig(input, "/project"),
      sql: [],
      ...(configText === undefined
        ? {}
        : { configFile: "/project/better-supabase.config.ts", configText }),
    });

  it("does nothing without an extraColumns option", async () => {
    expect(await run({ blocks: { tags: {} } })).toEqual({
      files: [],
      review: [],
    });
  });

  it("writes the columns to an app file and drops the option", async () => {
    const { files, review } = await run(
      {
        blocks: { tags: { options: { extraColumns: { region: "text" } } } },
      } as BetterSupabaseConfig,
      'export default { blocks: { tags: { options: { extraColumns: { region: "text" } } } } };\n',
    );

    expect(review).toEqual([]);
    expect(files.map((file) => [file.path, file.policy])).toEqual([
      ["/project/supabase/schemas/tags.ext.sql", "create"],
      ["/project/better-supabase.config.ts", "edit"],
    ]);
    expect(files[0]!.contents).toContain(
      'alter table "better_supabase"."tags"\n  add column "region" text;',
    );
    expect(files[1]!.contents).toBe(
      "export default { blocks: { tags: { options: {} } } };\n",
    );
  });

  it("keeps an option whose block has no table for it", async () => {
    const { files, review } = await run({
      blocks: { nope: { options: { extraColumns: { region: "text" } } } },
      instances: {
        second: {
          block: "tags",
          config: { options: { calendarExtraColumns: { a: "int" } } },
        },
      },
    } as BetterSupabaseConfig);

    expect(files).toEqual([]);
    expect(review).toEqual([
      {
        message:
          "blocks.nope.options.extraColumns.region: this release has no table for the option, so it stays in the config.",
      },
    ]);
  });
});
