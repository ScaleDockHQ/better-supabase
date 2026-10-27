import { describe, expect, it } from "vitest";

import {
  groupConfigJson,
  groupConfigSource,
} from "../../../src/cli/sql/config-group.ts";

const grouped = (source: string): string => {
  const edit = groupConfigSource(source);

  if (!edit.ok) {
    throw new Error(edit.reason);
  }

  return edit.text;
};

describe("groupConfigSource", () => {
  const source = `import { defineConfig } from "better-supabase/config";

export default defineConfig({
  // Where the database comes from.
  source: { dbUrl: process.env.DATABASE_URL },
  casing: "camel",
  output: "src/lib/supabase/generated.ts",
  subjects: { customer: { table: "customers" } },
  integrations: ["next"],
  claims: { tenant: "app_metadata.org_id" },
  doctor: { strict: true },
  appTables: {
    notes: { scope: "user", columns: { body: { type: "text" } } },
  },
  blocks: {
    teams: { mode: "adopt", entities: { team: "squad" } },
  },
});
`;

  it("moves each key into its group and renames the moved keys, with their comments", () => {
    expect(grouped(source))
      .toBe(`import { defineConfig } from "better-supabase/config";

export default defineConfig({
  database: {
    // Where the database comes from.
    source: { dbUrl: process.env.DATABASE_URL },
  },
  gen: {
    casing: "camel",
    output: "src/lib/supabase/generated.ts",
  },
  subjects: { customer: { table: "customers" } },
  adapters: ["next"],
  tooling: {
    doctor: { strict: true },
  },
  appTables: {
    notes: { owner: "user", columns: { body: { type: "text" } } },
  },
  blocks: {
    teams: { ownership: "adopt", names: { team: "squad" } },
  },
  auth: {
    tenant: { claim: "app_metadata.org_id" },
  },
});
`);
  });

  it("leaves a grouped config alone", () => {
    const once = grouped(source);

    expect(grouped(once)).toBe(once);
  });

  it("groups an inline object inline", () => {
    expect(
      grouped(
        `export default { casing: "camel", relations: true, blocks: ["tags"] };\n`,
      ),
    ).toBe(
      `export default { gen: { casing: "camel", relations: true }, blocks: ["tags"] };\n`,
    );
  });

  it("refuses a config with a spread", () => {
    expect(
      groupConfigSource(
        `export default defineConfig({ ...base, casing: "camel" });\n`,
      ),
    ).toEqual({
      ok: false,
      reason:
        "the config object has a spread or a computed key; move its keys into the groups by hand",
    });
  });

  it("renames sql.scope and the tenant plugin's column, keeping the other claims", () => {
    expect(
      grouped(`export default defineConfig({
  sql: { scope: "tenant" },
  claims: { tenant: "org_id", features: "app_metadata.features" },
  plugins: { tenant: { column: "workspace_id" } },
  blocks: { notes: { scope, "mode": "adopt" } },
});
`),
    ).toMatchInlineSnapshot(`
      "export default defineConfig({
        database: {
          sql: { owner: "tenant" },
        },
        auth: {
          tenant: { claim: "org_id", column: "workspace_id" },
          claims: { features: "app_metadata.features" },
        },
        plugins: { tenant: true },
        blocks: { notes: { owner: scope, "ownership": "adopt" } },
      });
      "
    `);
  });

  it("merges keys into a group the config already has, and groups the environment blocks", () => {
    expect(
      grouped(`export default defineConfig({
  database: {
    schemas: ["public"],
  },
  expose: ["api"],
  $env: {
    production: { casing: "camel" },
  },
  $test: { doctor: { strict: true } },
});
`),
    ).toMatchInlineSnapshot(`
      "export default defineConfig({
        database: {
          schemas: ["public"],
          expose: ["api"],
        },
        $env: {
          production: { gen: { casing: "camel" } },
        },
        $test: { tooling: { doctor: { strict: true } } },
      });
      "
    `);
  });

  it("moves keys that share a line and skips what has nothing to move", () => {
    expect(
      grouped(`export default defineConfig({
  casing: "camel", relations: true,
  database: {},
  claims: { features: "app_metadata.features" },
  plugins: { tenant: {}, audit: true },
  $env: { preview: base, production: { gen: { casing: "snake" } } },
  output: \`src/
generated.ts\`,
});
`),
    ).toMatchInlineSnapshot(`
      "export default defineConfig({
        gen: {
          casing: "camel",
          relations: true,
          output: \`src/
      generated.ts\`,
        },
        auth: {
          claims: { features: "app_metadata.features" },
        },
        plugins: { tenant: true, audit: true },
        $env: { preview: base, production: { gen: { casing: "snake" } } },
      });
      "
    `);
  });

  it("leaves a plugin set to true and an empty config alone", () => {
    const source =
      "export default defineConfig({ plugins: { tenant: true } });\n";

    expect(grouped(source)).toBe(source);
    expect(grouped("export default defineConfig({});\n")).toBe(
      "export default defineConfig({});\n",
    );
  });

  it("adds auth.tenant to an inline object", () => {
    expect(
      grouped(`export default { claims: { tenant: "org_id" }, blocks: [] };\n`),
    ).toMatchInlineSnapshot(`
      "export default { blocks: [], auth: { tenant: { claim: "org_id" } } };
      "
    `);
  });

  it("leaves a group key that isn't an object literal where it is", () => {
    expect(
      grouped(`export default defineConfig({ database, casing: "camel" });\n`),
    ).toMatchInlineSnapshot(`
      "export default defineConfig({ database, gen: { casing: "camel" } });
      "
    `);
  });

  it("refuses a file without a config object", () => {
    expect(groupConfigSource("export const x = 1;\n")).toEqual({
      ok: false,
      reason: "no defineConfig({...}) or default export object found",
    });
  });
});

describe("groupConfigJson", () => {
  it("groups the keys, the generator overrides and the environment blocks", () => {
    const edit = groupConfigJson(
      `${JSON.stringify(
        {
          casing: "camel",
          schemas: ["public"],
          tables: { audit: { serviceRole: true } },
          $production: { doctor: { strict: true } },
        },
        null,
        2,
      )}\n`,
    );

    expect(edit.ok && JSON.parse(edit.text)).toEqual({
      database: { schemas: ["public"] },
      gen: { casing: "camel", tables: { audit: { serviceRole: true } } },
      $production: { tooling: { doctor: { strict: true } } },
    });
  });

  it("leaves a grouped config alone", () => {
    const source = '{\n  "gen": { "casing": "camel" }\n}\n';

    expect(groupConfigJson(source)).toEqual({ ok: true, text: source });
  });

  it("refuses invalid JSON and a value that isn't an object", () => {
    expect(groupConfigJson("{")).toEqual({
      ok: false,
      reason: "it isn't valid JSON",
    });
    expect(groupConfigJson("[]")).toEqual({
      ok: false,
      reason: "it isn't a JSON object",
    });
  });
});
