import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { rewriteForTableModules } from "../../src/cli/codemod-table-modules.ts";
import { applyCodemod, CODEMODS } from "../../src/cli/codemod.ts";
import { resolveConfig } from "../../src/config/resolve.ts";

const tables = [
  { key: "customers", name: "customersTable", file: "tables/customers.ts" },
  {
    key: "customerTags",
    name: "customerTagsTable",
    file: "tables/customer-tags.ts",
  },
];

const OUTPUT = "/app/src/lib/supabase/generated.ts";

describe("codemod table-modules", () => {
  it("imports schema from the schema module and keeps the other names", () => {
    const result = rewriteForTableModules(
      "/app/src/lib/supabase/index.ts",
      'import { schema, type Models } from "./generated.ts";\n',
      OUTPUT,
      tables,
    );

    expect(result.text).toBe(
      'import { type Models } from "./generated.ts";\nimport { schema } from "./generated-schema.ts";\n',
    );
  });

  it("follows the import style of the file", () => {
    const result = rewriteForTableModules(
      "/app/src/app/page.ts",
      'import { schema } from "../lib/supabase/generated";\n',
      OUTPUT,
      tables,
    );

    expect(result.text).toBe(
      'import { schema } from "../lib/supabase/generated-schema";\n',
    );
  });

  it("leaves imports from other modules alone", () => {
    const source = 'import { schema } from "./other.ts";\n';

    expect(
      rewriteForTableModules("/app/src/a.ts", source, OUTPUT, tables).text,
    ).toBe(source);
  });

  it("reads a table in a client file through its module", () => {
    const source = [
      '"use client";',
      "",
      'import { bsb } from "../lib/supabase/client";',
      "",
      "export const rows = () => bsb.db.customers.list();",
      'export const note = "bsb.db.customerTags";',
      "export const all = bsb.db.unknown.list();",
      "",
    ].join("\n");

    const result = rewriteForTableModules(
      "/app/src/app/rows.tsx",
      source,
      OUTPUT,
      tables,
    );

    expect(result.text).toContain("bsb.table(customersTable).list()");
    expect(result.text).toContain('"bsb.db.customerTags"');
    expect(result.text).toContain("bsb.db.unknown.list()");
    expect(result.text).toContain(
      'import { customersTable } from "../lib/supabase/tables/customers.ts";',
    );
    expect(result.text.startsWith('"use client";')).toBe(true);
  });

  it("leaves server files and lists a queries read", () => {
    const server = "export const rows = () => bsb.db.customers.list();\n";

    expect(
      rewriteForTableModules("/app/src/a.ts", server, OUTPUT, tables).text,
    ).toBe(server);

    const result = rewriteForTableModules(
      "/app/src/a.tsx",
      '"use client";\nconst q = bsb.queries.customers;\n',
      OUTPUT,
      tables,
    );

    expect(result.review).toHaveLength(1);
    expect(result.review[0]?.message).toContain("defineListQuery");
  });

  it("reads the table modules next to the generated module", async () => {
    const root = await mkdtemp(join(tmpdir(), "bsb-codemod-"));

    try {
      const folder = join(root, "src/lib/supabase");
      await mkdir(join(folder, "tables"), { recursive: true });

      await writeFile(
        join(folder, "tables/customers.ts"),
        "export const customersTable = /*#__PURE__*/ defineTable({});\n",
      );

      const config = resolveConfig(
        { gen: { file: "src/lib/supabase/generated.ts" } },
        root,
      );

      const codemod = CODEMODS["table-modules"]!;
      const rewrite = await codemod.files!({ config, sql: [] });

      const result = applyCodemod(
        codemod,
        '"use client";\nimport { bsb } from "./client";\nbsb.db.customers.list();\n',
        rewrite,
        join(root, "src/app/page.tsx"),
      );

      expect(result.text).toContain("bsb.table(customersTable)");
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});
