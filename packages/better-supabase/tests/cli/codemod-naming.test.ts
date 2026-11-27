import { describe, expect, it } from "vitest";

import {
  appCheckNames,
  appPolicyKeys,
  NAMING_RENAMES,
  namingCodemod,
  renameEnvFileNames,
  renameMigrationSql,
  renameNames,
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

const ENV = [
  {
    from: "BSB_STACK",
    to: "BETTER_SUPABASE_STACK",
    kind: "env",
    since: "0.54",
  },
] as const;

describe("renameEnvFileNames", () => {
  it("renames whole names only", () => {
    expect(
      renameEnvFileNames("BSB_STACK X_BSB_STACK BSB_STACK_2 BSB_STACK", ENV),
    ).toBe(
      "BETTER_SUPABASE_STACK X_BSB_STACK BSB_STACK_2 BETTER_SUPABASE_STACK",
    );
  });
});

describe("renameNames", () => {
  const renames = [
    ...ENV,
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
      renameNames(
        `a("OLD_CODE"); b('OLD_CODE'); c("LEDGER_OLD_CODE"); d(\`thing.saved\`); e("thing.savedx");`,
        renames,
      ).text,
    ).toBe(
      `a("NEW_CODE"); b('NEW_CODE'); c("LEDGER_OLD_CODE"); d(\`thing.published\`); e("thing.savedx");`,
    );
  });

  it("renames an environment variable where code names it", () => {
    const { text } = renameNames(
      'const a = process.env.BSB_STACK;\nconst b = process.env["BSB_STACK"];\nconst c = { BSB_STACK: 1, BSB_STACK_2: 2 };\n',
      renames,
    );

    expect(text).toBe(
      'const a = process.env.BETTER_SUPABASE_STACK;\nconst b = process.env["BETTER_SUPABASE_STACK"];\nconst c = { BETTER_SUPABASE_STACK: 1, BSB_STACK_2: 2 };\n',
    );
  });

  it("leaves comments alone and lists a string that mentions a name", () => {
    const source =
      '// set BSB_STACK first, then "OLD_CODE"\n/* BSB_STACK */\nlog("set BSB_STACK to x");\n';

    const result = renameNames(source, renames);

    expect(result.text).toBe(source);
    expect(result.review).toHaveLength(1);
    expect(result.review[0]?.line).toBe(3);
  });

  it("renames a shorthand property with its binding", () => {
    expect(
      renameNames("const BSB_STACK = 1;\nuse({ BSB_STACK });\n", renames).text,
    ).toBe(
      "const BETTER_SUPABASE_STACK = 1;\nuse({ BETTER_SUPABASE_STACK });\n",
    );
  });

  it("lists a file that does not parse", () => {
    expect(renameNames("const = ;", renames).review).toHaveLength(1);
  });

  it("is applied by the codemod to source files, and to env files as text", () => {
    const codemod = namingCodemod(renames);

    expect(
      applyCodemod(codemod, 'if (error.hint === "OLD_CODE") {}\n').text,
    ).toBe('if (error.hint === "NEW_CODE") {}\n');
    expect(
      applyCodemod(codemod, "BSB_STACK=1\n", undefined, ".env.local").text,
    ).toBe("BETTER_SUPABASE_STACK=1\n");
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
      tenantColumns: {
        global: new Set(["organization_id"]),
        byTable: new Map(),
      },
    });

    expect(loaded).not.toContain('rename column "organization_id"');
    expect(loaded).toContain('rename column "locked_until"');

    const oneTable = renameMigrationSql(NAMING_RENAMES, sql, {
      configLoaded: true,
      tenantColumns: {
        global: new Set(),
        byTable: new Map([
          ["better_supabase.agents", new Set(["organization_id"])],
        ]),
      },
    });

    expect(oneTable).not.toContain(
      'alter table "better_supabase"."agents" rename column "organization_id"',
    );
    expect(oneTable).toContain(
      'alter table "better_supabase"."agent_installs" rename column "organization_id"',
    );

    expect(
      renameMigrationSql(NAMING_RENAMES, sql, {
        configLoaded: false,
        tenantColumns: { global: new Set(), byTable: new Map() },
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

  it("leaves a policy the app's schema files create, such as PermDock's", () => {
    const own =
      'create policy better_supabase_attachments_delete_read_only_actors on "better_supabase"."attachments" as restrictive for delete to authenticated using (true);';

    const migration = renameMigrationSql([], `${sql}\n${own}`, {
      configLoaded: true,
      tenantColumns: { global: new Set(), byTable: new Map() },
      appPolicies: appPolicyKeys(own),
    });

    expect(migration).toContain('rename to "bsb_tasks_read"');
    expect(migration).not.toContain("read_only_actors");
  });
});

describe("renamed SQL functions in the app's files", () => {
  const renames = [
    {
      from: "save_task",
      to: "upsert_task",
      kind: "sqlFunctionName" as const,
      since: "0.88",
    },
  ];

  it("rewrites calls through the api schema in SQL", async () => {
    const codemod = namingCodemod(renames);

    const out = await codemod.sql!(
      "select api.save_task('{}');\nselect better_supabase.save_task('{}');\nselect app.save_task_x();",
      {
        configLoaded: false,
        tenantColumns: { global: new Set(), byTable: new Map() },
      },
    );

    expect(out).toBe(
      "select api.upsert_task('{}');\nselect better_supabase.upsert_task('{}');\nselect app.save_task_x();",
    );
  });

  it("rewrites rpc paths and rpc names in TypeScript", () => {
    // A template literal with a placeholder, written without one here.
    const tick = String.fromCodePoint(96);
    const url = ["$", "{url}"].join("");

    const source = (name: string, other: string): string =>
      [
        `await fetch(${tick}${url}/rest/v1/rpc/${name}${tick});`,
        `await fetch("/rest/v1/rpc/${name}?select=id");`,
        `await db.rpc("${name}");`,
        `const other = "rpc/${other}";`,
        "",
      ].join("\n");

    expect(renameNames(source("save_task", "save_tasks"), renames).text).toBe(
      source("upsert_task", "save_tasks"),
    );
  });
});

describe("generated check names", () => {
  it("keeps the check constraints the app's own SQL names", () => {
    const migration = renameMigrationSql(
      [],
      "create table better_supabase.x (a int);",
      {
        configLoaded: true,
        tenantColumns: { global: new Set(), byTable: new Map() },
        appChecks: new Set(["profiles_locale_check", "Teams_Icon"]),
      },
    );

    expect(migration).toContain("rename constraint %I to %I");
    expect(migration).toContain(
      "k.conname <> all (array['profiles_locale_check', 'Teams_Icon'])",
    );
  });
});

describe("appCheckNames", () => {
  it("names the unnamed check of a column an app file adds to a block table", () => {
    expect(
      appCheckNames(
        `alter table "better_supabase"."flags"\n  add column "expires_at" timestamptz,\n  add column "kind" text not null default 'release' check (kind in ('release', 'ops')),\n  add column "owner" text;`,
      ),
    ).toEqual(new Set(["flags_kind_check"]));
  });

  it("reads the names of the checks a schema file declares", () => {
    expect(
      appCheckNames(
        'alter table better_supabase.profiles add constraint profiles_locale_check check (true);\ncreate table t (a int constraint "Teams_Icon" check (a > 0), b int constraint t_b_fk references u);',
      ),
    ).toEqual(new Set(["profiles_locale_check", "Teams_Icon"]));
  });
});

describe("BS260", () => {
  const rule = NAMING_RENAME_RULES[0]!;

  it("reports a source file that uses an old name", async () => {
    const findings = await rule.check({
      config: { blocks: {} },
      sources: [
        {
          path: "a.ts",
          text: 'import { buildApiModel } from "better-supabase";\nconst s = buildApiModel(x);\n',
        },
        { path: "b.ts", text: "const s = defineApiModel(x);\n" },
        { path: "c.ts", text: "process.env.BSB_STACK\n" },
      ],
    } as never);

    expect(findings).toHaveLength(2);

    const subpath = await rule.check({
      config: { blocks: {} },
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

  it("leaves a local function of the same name alone", async () => {
    expect(
      await rule.check({
        config: { blocks: {} },
        sources: [{ path: "a.ts", text: "const s = buildApiModel(x);\n" }],
      } as never),
    ).toEqual([]);
  });
});

describe("BS260 reads what the codemod changes", () => {
  const rule = NAMING_RENAME_RULES[0]!;

  it("ignores an old name in a comment or a longer string", async () => {
    const findings = await rule.check({
      config: { blocks: {} },
      sources: [
        {
          path: "a.ts",
          text: [
            "// buildApiModel(x) was renamed",
            'const note = "call buildApiModel(x) and BSB_STACK";',
            "export { note };",
          ].join("\n"),
        },
      ],
    } as never);

    expect(findings).toEqual([]);
  });

  it("names the line of the first change", async () => {
    const findings = await rule.check({
      config: { blocks: {} },
      sources: [
        {
          path: "a.ts",
          text: '// buildApiModel\nimport { buildApiModel } from "better-supabase";\nconst s = buildApiModel(x);\n',
        },
      ],
    } as never);

    expect(findings).toMatchObject([{ location: { file: "a.ts", line: 2 } }]);
  });
});

describe("BS260 argument names", () => {
  const rule = NAMING_RENAME_RULES[0]!;

  const check = (text: string) =>
    rule.check({
      config: { blocks: {} },
      sources: [{ path: "a.ts", text }],
    } as never);

  it("leaves a local variable of an old argument name alone", async () => {
    expect(
      await check(
        "const workItemId = row.id;\ncall(a, workItemId, b);\nawait tasks.move({ taskId: workItemId });\n",
      ),
    ).toEqual([]);
  });

  it("reports the old name where the codemod renames it, on its line", async () => {
    expect(
      await check("const id = 1;\nawait tasks.move({ workItemId: id });\n"),
    ).toMatchObject([{ location: { file: "a.ts", line: 2 } }]);
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
        "await tasks.archive({ workItemId: taskId });",
        "call(a, workItemId, b);",
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
        "await tasks.archive({ taskId });",
        "call(a, workItemId, b);",
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
        'const a2 = blockConfig["time-tracking"];',
        "const b = db.$blocks.timeTracking.list();",
        "const c = db.$blocks.bulk.run();",
        "const d = other.timeTracking;",
        '// blocks["time-tracking"] stays in a comment',
        'defineBlocks(blockConfig, { "time-tracking": blocks["time-tracking"].with({}) });',
        'const e = { "time-tracking": other["time-tracking"] };',
        '// "time-tracking": blocks["time-entries"] and db.$blocks.timeTracking',
        "",
      ].join("\n"),
    );

    expect(text).toBe(
      [
        'const a = config.blocks["time-entries"];',
        'const a2 = blockConfig["time-entries"];',
        "const b = db.$blocks.timeEntries.list();",
        "const c = db.$blocks.bulkActions.run();",
        "const d = other.timeTracking;",
        '// blocks["time-tracking"] stays in a comment',
        'defineBlocks(blockConfig, { "time-entries": blocks["time-entries"].with({}) });',
        'const e = { "time-tracking": other["time-tracking"] };',
        '// "time-tracking": blocks["time-entries"] and db.$blocks.timeTracking',
        "",
      ].join("\n"),
    );
  });

  it("keeps the argument names of an entity the config renamed", async () => {
    const rule = NAMING_RENAME_RULES[0]!;

    const sources = [
      { path: "a.ts", text: "tasks.assign({ workItemId: id });\n" },
    ];

    const context = (blocks: object): never =>
      // SAFETY: the rule reads only `config.blocks` and `sources`.
      ({ config: { blocks }, sources }) as never;

    expect(await rule.check(context({}))).toHaveLength(1);

    const kept = await rule.check(
      context({ tasks: { entities: { task: "work_item" } } }),
    );

    expect(kept).toEqual([]);
  });
});
