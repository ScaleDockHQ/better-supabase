import { describe, expect, it } from "vitest";

import {
  NAMING_RENAMES,
  namingCodemod,
  renameEnvNames,
  renameMigrationSql,
  renameQuotedNames,
} from "../../src/cli/codemod-naming.ts";
import { applyCodemod } from "../../src/cli/codemod.ts";
import { NAMING_RENAME_RULES } from "../../src/cli/doctor/naming-renames.ts";

describe("the rename table", () => {
  it("renames each name once, to a name it doesn't rename again", () => {
    const from = NAMING_RENAMES.map(
      (rename) => `${rename.kind}:${rename.table ?? ""}:${rename.from}`,
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

describe("renameQuotedNames", () => {
  const renames = [
    { from: "OLD_CODE", to: "NEW_CODE", kind: "hint", since: "0.54" },
    {
      from: "thing.saved",
      to: "thing.published",
      kind: "event",
      since: "0.54",
    },
  ] as const;

  it("renames whole string literals of hints and events only", () => {
    expect(
      renameQuotedNames(
        `a("OLD_CODE") b('OLD_CODE') c("LEDGER_OLD_CODE") d(\`thing.saved\`) e("thing.savedx")`,
        renames,
      ),
    ).toBe(
      `a("NEW_CODE") b('NEW_CODE') c("LEDGER_OLD_CODE") d(\`thing.published\`) e("thing.savedx")`,
    );
  });

  it("is applied by the codemod to source files", () => {
    const { text } = applyCodemod(
      namingCodemod(renames),
      'if (error.hint === "OLD_CODE") {}\n',
    );

    expect(text).toBe('if (error.hint === "NEW_CODE") {}\n');
  });
});

describe("renameMigrationSql", () => {
  it("writes nothing for renames that touch no SQL", () => {
    expect(
      renameMigrationSql(
        NAMING_RENAMES.filter(
          (rename) =>
            rename.kind !== "sqlFunction" &&
            rename.kind !== "trigger" &&
            rename.kind !== "column" &&
            rename.kind !== "table" &&
            rename.kind !== "constraint" &&
            rename.kind !== "index",
        ),
      ),
    ).toBeUndefined();
  });

  it("leaves out a renamed SQL function the project's SQL never names", () => {
    const rename = {
      from: "bsb.owns(uuid)",
      to: "better_supabase.owns(uuid)",
      kind: "sqlFunction",
      since: "0.54",
    } as const;

    expect(renameMigrationSql([rename], "select 1;")).toBeUndefined();
    expect(renameMigrationSql([rename], "using (bsb.owns(owner))")).toContain(
      "alter function bsb.owns(uuid)",
    );
  });

  it("renames a trigger or an index the project's SQL names, and no other", () => {
    const rename = (kind: "index" | "trigger", from: string, to: string) =>
      ({
        from,
        to,
        kind,
        since: "0.54",
        table: "better_supabase.bookings",
      }) as const;

    const renames = [
      rename("trigger", "bookings_activity", "bsb_bookings_activity"),
      rename("index", "bsb_old_scope", "bsb_old_scope_key"),
    ];

    expect(renameMigrationSql(renames, "select 1;")).toBeUndefined();

    const sql = renameMigrationSql(
      renames,
      'create trigger bookings_activity after insert on "better_supabase"."bookings"; create index bsb_old_scope on t (a);',
    )!;

    expect(sql).toContain(
      'alter trigger "bookings_activity" on "better_supabase"."bookings" rename to "bsb_bookings_activity"',
    );
    expect(sql).toContain(
      'alter index "better_supabase"."bsb_old_scope" rename to "bsb_old_scope_key"',
    );
  });

  it("moves renamed SQL functions to their new schema behind an existence check", () => {
    const sql = renameMigrationSql([
      {
        from: "bsb.owns(uuid)",
        to: "better_supabase.owns(uuid)",
        kind: "sqlFunction",
        since: "0.54",
      },
    ]);

    expect(sql).toContain("to_regprocedure('bsb.owns(uuid)') is not null");
    expect(sql).toContain(
      'alter function bsb.owns(uuid) set schema "better_supabase"',
    );
  });

  it("renames tables, columns and policies behind existence checks", () => {
    const sql = renameMigrationSql([
      {
        from: "better_supabase.stream_entries",
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
      'alter table "better_supabase"."stream_entries" rename to "stream_entries"',
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

describe("column renames and the tenant column", () => {
  const sql =
    "create table t (organization_id uuid, locked_until timestamptz);";

  it("renames job_schedules.locked_until", () => {
    expect(renameMigrationSql(NAMING_RENAMES, sql)).toContain(
      'alter table "better_supabase"."job_schedules" rename column "locked_until" to "lock_expires_at"',
    );
  });

  it("skips the configured tenant column, and every column without a config", () => {
    const loaded = renameMigrationSql(NAMING_RENAMES, sql, {
      configLoaded: true,
      tenantColumns: new Set(["organization_id"]),
    });

    expect(loaded).not.toContain('rename column "organization_id"');
    expect(loaded).toContain('rename column "locked_until"');

    expect(
      renameMigrationSql(NAMING_RENAMES, sql, {
        configLoaded: false,
        tenantColumns: new Set(),
      }) ?? "",
    ).not.toContain("rename column");
  });
});

describe("generated policy names", () => {
  const sql = `
create policy tasks_read on "better_supabase"."tasks" for select to authenticated using (true);
create policy tasks_read on "better_supabase"."tasks" for select to authenticated using (true);
create policy bsb_tasks_write on "better_supabase"."tasks" for all to authenticated using (true);
create policy notes_read on public.notes for select using (true);
`;

  it("renames each unprefixed policy of a better_supabase table once, and no other", () => {
    const migration = renameMigrationSql([], sql);

    expect(migration).toContain(
      'alter policy "tasks_read" on "better_supabase"."tasks" rename to "bsb_tasks_read"',
    );

    expect(migration?.match(/alter policy/gu)).toHaveLength(1);
    expect(migration).not.toContain("notes_read");
    expect(migration).not.toContain("bsb_tasks_write");
  });

  it("writes nothing without the project's SQL", () => {
    expect(renameMigrationSql([])).toBeUndefined();
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

describe("argument renames", () => {
  const codemod = namingCodemod();

  it("renames the keys, members and shorthand of the tasks verb arguments", () => {
    const { text } = applyCodemod(
      codemod,
      [
        'import { workItemId } from "./x";',
        "await tasks.assign({ workItemId: id, userId });",
        "await tasks.move({ workItemId });",
        "const { workItemId } = event.data;",
        "log(event.data.workItemId);",
        'const note = "workItemId";',
        "",
      ].join("\n"),
    );

    expect(text).toBe(
      [
        'import { workItemId } from "./x";',
        "await tasks.assign({ taskId: id, userId });",
        "await tasks.move({ taskId: workItemId });",
        "const { taskId: workItemId } = event.data;",
        "log(event.data.taskId);",
        'const note = "workItemId";',
        "",
      ].join("\n"),
    );
  });
});

describe("block references", () => {
  it("renames string block keys and $blocks members of a renamed block", () => {
    const { text } = applyCodemod(
      namingCodemod(),
      [
        'const a = config.blocks["time-tracking"];',
        "const b = db.$blocks.timeTracking.list();",
        "const c = db.$blocks.bulk.run();",
        "const d = other.timeTracking;",
        '// blocks["time-tracking"] stays in a comment',
        "",
      ].join("\n"),
    );

    expect(text).toBe(
      [
        'const a = config.blocks["time-entries"];',
        "const b = db.$blocks.timeEntries.list();",
        "const c = db.$blocks.bulkActions.run();",
        "const d = other.timeTracking;",
        '// blocks["time-tracking"] stays in a comment',
        "",
      ].join("\n"),
    );
  });
});
