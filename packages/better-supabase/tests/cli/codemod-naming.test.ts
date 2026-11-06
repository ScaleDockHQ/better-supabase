import { describe, expect, it } from "vitest";

import {
  NAMING_RENAMES,
  namingCodemod,
  renameEnvNames,
  renameMigrationSql,
} from "../../src/cli/codemod-naming.ts";
import { applyCodemod } from "../../src/cli/codemod.ts";
import { NAMING_RENAME_RULES } from "../../src/cli/doctor/naming-renames.ts";

describe("the rename table", () => {
  it("renames each name once, to a name it doesn't rename again", () => {
    const from = NAMING_RENAMES.map(
      (rename) => `${rename.kind}:${rename.from}`,
    );

    expect(new Set(from).size).toBe(from.length);
    const names = new Set(NAMING_RENAMES.map((rename) => rename.from));

    expect(NAMING_RENAMES.filter((rename) => names.has(rename.to))).toEqual([]);
  });

  it("gives a column or policy rename its table", () => {
    expect(
      NAMING_RENAMES.filter(
        (rename) =>
          (rename.kind === "column" || rename.kind === "policy") &&
          rename.table === undefined,
      ),
    ).toEqual([]);
  });
});

describe("codemod naming", () => {
  const codemod = namingCodemod();

  it("renames imports and their uses", () => {
    const source =
      'import { buildJsonSchema as build, createRuleSink } from "better-supabase/config";\nbuild({});\ncreateRuleSink();\n';

    const { text } = applyCodemod(codemod, source);

    expect(text).toContain("toJsonSchema as build");
    expect(text).toContain("automationSink");
    expect(text).not.toContain("createRuleSink");
  });

  it("renames imports from two statements in one file", () => {
    const { text } = applyCodemod(
      codemod,
      'import { buildApiModel } from "better-supabase/spec";\nimport { buildJsonSchema } from "better-supabase/config";\nbuildApiModel(buildJsonSchema({}));\n',
    );

    expect(text).toBe(
      'import { defineApiModel } from "better-supabase/spec";\nimport { toJsonSchema } from "better-supabase/config";\ndefineApiModel(toJsonSchema({}));\n',
    );
  });

  it("renames a subpath in specifiers", () => {
    const { text } = applyCodemod(
      codemod,
      'import { x } from "better-supabase/ai-sdk/workflow/react";\n',
    );

    expect(text).toBe(
      'import { x } from "better-supabase/ai-sdk/workflow-react";\n',
    );
  });

  it("leaves a name it doesn't know and is idempotent", () => {
    const source = 'import { buildThing } from "better-supabase/config";\n';
    expect(applyCodemod(codemod, source).text).toBe(source);

    const once = applyCodemod(codemod, "BSB_STACK=a\n").text;
    expect(applyCodemod(codemod, once).text).toBe(once);
  });
});

describe("renameEnvNames", () => {
  it("renames whole names only", () => {
    expect(
      renameEnvNames("BSB_STACK X_BSB_STACK BSB_STACK_2 BSB_STACK", [
        {
          from: "BSB_STACK",
          to: "BETTER_SUPABASE_STACK",
          kind: "env",
          since: "0.54",
        },
      ]),
    ).toBe(
      "BETTER_SUPABASE_STACK X_BSB_STACK BSB_STACK_2 BETTER_SUPABASE_STACK",
    );
  });
});

describe("renameMigrationSql", () => {
  it("writes nothing for renames that touch no SQL", () => {
    expect(renameMigrationSql(NAMING_RENAMES)).toBeUndefined();
  });

  it("renames tables, columns and policies behind existence checks", () => {
    const sql = renameMigrationSql([
      {
        from: "better_supabase.stream_kv",
        to: "stream_entries",
        kind: "table",
        since: "0.54",
      },
      {
        from: "valid_until",
        to: "expires_at",
        kind: "column",
        since: "0.54",
        table: "better_supabase.tokens",
      },
      {
        from: "tasks_read",
        to: "bsb_tasks_select",
        kind: "policy",
        since: "0.54",
        table: "better_supabase.tasks",
      },
    ]);

    expect(sql).toContain("-- destructive: reviewed");
    expect(sql).toContain(
      'alter table "better_supabase"."stream_kv" rename to "stream_entries"',
    );
    expect(sql).toContain(
      'alter table "better_supabase"."tokens" rename column "valid_until" to "expires_at"',
    );
    expect(sql).toContain(
      'alter policy "tasks_read" on "better_supabase"."tasks" rename to "bsb_tasks_select"',
    );
    expect(sql).not.toMatch(/if not exists|drop /u);
  });
});

describe("BS260", () => {
  const rule = NAMING_RENAME_RULES[0]!;

  it("reports a source file that uses an old name", async () => {
    const findings = await rule.check({
      sources: [
        { path: "a.ts", text: "const s = buildApiModel(x);\n" },
        { path: "b.ts", text: "const s = defineApiModel(x);\n" },
        { path: "c.ts", text: "process.env.BSB_STACK\n" },
      ],
    } as never);

    expect(findings).toHaveLength(2);

    const subpath = await rule.check({
      sources: [
        {
          path: "d.ts",
          text: 'import "better-supabase/ai-sdk/workflow/react";\n',
        },
      ],
    } as never);

    expect(subpath).toHaveLength(1);
    expect(findings[0]).toMatchObject({
      target: "a.ts",
      location: { file: "a.ts", line: 1 },
    });
  });
});
