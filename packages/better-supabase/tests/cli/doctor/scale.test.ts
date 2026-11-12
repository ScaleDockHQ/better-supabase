import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";
import type {
  Catalog,
  CatalogTable,
  Snapshot,
} from "../../../src/cli/introspect/types.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import { RULES, runRules } from "../../../src/cli/doctor/rules.ts";
import { toCatalog } from "../../../src/cli/introspect/catalog.ts";
import { fromCatalog } from "../../../src/cli/introspect/from-catalog.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { moduleSnapshotFixture as fixture } from "../fixtures/library.ts";

const base = await parseSnapshot(fixture);

type Mutable<T> = { -readonly [K in keyof T]: T[K] };

function snapshot(
  change: (tables: Mutable<CatalogTable>[]) => void,
  functions: NonNullable<Snapshot["extras"]["functions"]> = [],
): Snapshot {
  const copy = structuredClone(toCatalog(base)) as Mutable<Catalog>;
  change(copy.tables as Mutable<CatalogTable>[]);
  const built = fromCatalog(copy);

  return { ...built, extras: { ...built.extras, functions: [...functions] } };
}

const notes = (tables: Mutable<CatalogTable>[]): Mutable<CatalogTable> =>
  tables.find((entry) => entry.name === "notes")!;

const context = (
  snap: Snapshot,
  extra: Partial<DoctorContext> = {},
): DoctorContext => ({
  config: resolveConfig(
    { auth: { tenant: { column: "organization_id" } } },
    "/project",
  ),
  snapshot: snap,
  configToml: undefined,
  envFiles: [],
  gitignore: "",
  sources: [],
  ...extra,
});

const run = (ctx: DoctorContext, code: string) =>
  runRules(
    ctx,
    RULES.filter((rule) => rule.code === code),
  );

const trigger = (name: string, fn = "better_supabase.fn") => ({
  name,
  timing: "after" as const,
  events: ["insert" as const],
  level: "row" as const,
  function: fn,
});

const index = (
  name: string,
  columns: string[],
  extra: Partial<CatalogTable["indexes"][number]> = {},
): CatalogTable["indexes"][number] => ({
  name,
  columns,
  unique: false,
  primary: false,
  partial: false,
  method: "btree",
  predicate: null,
  ...extra,
});

describe("scale rules on the fixture", () => {
  it("pass the fixture schema", async () => {
    for (const code of ["BS386", "BS387", "BS390", "BS391"]) {
      expect(await run(context(base), code)).toEqual([]);
    }
  });
});

describe("BS386 per-row policy functions", () => {
  const fn = (
    overrides: Partial<
      NonNullable<Snapshot["extras"]["functions"]>[number]
    > = {},
  ) => ({
    schema: "public",
    name: "can_read",
    signature: "id uuid",
    language: "plpgsql",
    volatility: "volatile" as const,
    securityDefiner: false,
    settings: {},
    ...overrides,
  });

  const withPolicy = (using: string, functions = [fn()]) =>
    snapshot((tables) => {
      notes(tables).policies = [
        {
          name: "read",
          command: "select",
          roles: ["authenticated"],
          permissive: true,
          using,
          check: null,
          functions: ["public.can_read"],
        },
      ];
    }, functions);

  it("flags a bare call", async () => {
    const findings = await run(
      context(withPolicy("public.can_read(id)")),
      "BS386",
    );

    expect(findings).toHaveLength(1);
    expect(findings[0]?.code).toBe("BS386");
    expect(findings[0]?.target).toBe("public.notes:read");
  });

  it("accepts a call inside an InitPlan, even when it is volatile", async () => {
    expect(
      await run(
        context(withPolicy("(id = ( SELECT public.can_read(id) AS can_read))")),
        "BS386",
      ),
    ).toEqual([]);
  });

  it("accepts a set helper in an uncorrelated in (select ... from fn())", async () => {
    for (const using of [
      "id in (select t.id::uuid from public.can_read('participant') as t(id))",
      "(id IN ( SELECT (t.id)::uuid AS id FROM public.can_read('participant'::text) t(id)))",
    ]) {
      expect(await run(context(withPolicy(using)), "BS386")).toEqual([]);
    }
  });

  it("flags a set helper whose arguments read the row", async () => {
    const findings = await run(
      context(
        withPolicy(
          "id in (select t.id from public.can_read(organization_id) as t(id))",
        ),
      ),
      "BS386",
    );

    expect(findings).toHaveLength(1);
    expect(findings[0]?.target).toBe("public.notes:read");
  });

  it("leaves the blocks' own policies to upgrade", async () => {
    const renamed = snapshot(
      (tables) => {
        notes(tables).policies = [
          {
            name: "bsb_notes_read",
            command: "select",
            roles: ["authenticated"],
            permissive: true,
            using: "public.can_read(id)",
            check: null,
            functions: ["public.can_read"],
          },
        ];
      },
      [fn()],
    );

    expect(await run(context(renamed), "BS386")).toEqual([]);
  });

  it("accepts a stable SQL function", async () => {
    expect(
      await run(
        context(
          withPolicy("public.can_read(id)", [
            fn({ language: "sql", volatility: "stable" }),
          ]),
        ),
        "BS386",
      ),
    ).toEqual([]);
  });
});

describe("BS386 non-inlinable functions in select policies", () => {
  const definer = {
    schema: "public",
    name: "can_note",
    signature: "p_row notes, p_permission text",
    language: "sql",
    volatility: "stable" as const,
    securityDefiner: true,
    settings: { search_path: "" },
  };

  const withPolicy = (
    using: string,
    command: "select" | "all" | "update" = "select",
    fn = definer,
  ) =>
    snapshot(
      (tables) => {
        notes(tables).policies = [
          {
            name: "read",
            command,
            roles: ["authenticated"],
            permissive: true,
            using,
            check: null,
            functions: ["public.can_note"],
          },
        ];
      },
      [fn],
    );

  it("flags a stable security definer check called per row", async () => {
    for (const using of [
      "public.can_note(notes, 'read')",
      "public.can_note(notes.*, 'read'::text)",
    ]) {
      const findings = await run(context(withPolicy(using)), "BS386");

      expect(findings).toHaveLength(1);
      expect(findings[0]?.target).toBe("public.notes:read");
    }
  });

  it("flags a stable SQL function with a set clause", async () => {
    const findings = await run(
      context(
        withPolicy("public.can_note(notes.*, 'read'::text)", "select", {
          ...definer,
          securityDefiner: false,
        }),
      ),
      "BS386",
    );

    expect(findings).toHaveLength(1);
  });

  it("accepts the check as the fallback after a set check", async () => {
    for (const using of [
      "id in (select public.note_ids('read')) or public.can_note(notes, 'read')",
      "((id IN ( SELECT public.note_ids('read'::text) AS note_ids)) OR public.can_note(notes.*, 'read'::text))",
      "((organization_id IN ( SELECT public.org_ids('notes.read'::text) AS org_ids)) AND ((id IN ( SELECT public.note_ids('read'::text) AS note_ids)) OR public.can_note(notes.*, 'read'::text)))",
    ]) {
      expect(await run(context(withPolicy(using)), "BS386")).toEqual([]);
    }
  });

  it("flags the check when the set check is an and, not an or", async () => {
    const findings = await run(
      context(
        withPolicy(
          "((id IN ( SELECT public.note_ids('read'::text) AS note_ids)) AND public.can_note(notes.*, 'read'::text))",
        ),
      ),
      "BS386",
    );

    expect(findings).toHaveLength(1);
  });

  it("accepts the check inside an InitPlan", async () => {
    expect(
      await run(
        context(
          withPolicy(
            "( SELECT public.can_note(NULL::notes, 'read'::text) AS can_note)",
          ),
        ),
        "BS386",
      ),
    ).toEqual([]);
  });

  it("accepts set helpers joined laterally in the from of a subquery", async () => {
    for (const using of [
      "(id IN ( SELECT eligible.id FROM (public.org_ids() member(id) CROSS JOIN LATERAL public.can_note(member.id) eligible(id))))",
      "(id IN ( SELECT eligible.id FROM public.org_ids() member(id), LATERAL public.can_note(member.id, 'read'::text) eligible(id)))",
    ]) {
      expect(await run(context(withPolicy(using)), "BS386")).toEqual([]);
    }
  });

  it("flags a lateral set helper whose arguments read the row", async () => {
    expect(
      await run(
        context(
          withPolicy(
            "(id IN ( SELECT eligible.id FROM (public.org_ids() member(id) CROSS JOIN LATERAL public.can_note(notes.organization_id) eligible(id))))",
          ),
        ),
        "BS386",
      ),
    ).toHaveLength(1);
  });

  it("leaves write policies to the volatile and PL/pgSQL rule", async () => {
    expect(
      await run(
        context(withPolicy("public.can_note(notes.*, 'read'::text)", "update")),
        "BS386",
      ),
    ).toEqual([]);
  });

  it("flags the check in a policy for all commands", async () => {
    expect(
      await run(
        context(withPolicy("public.can_note(notes.*, 'read'::text)", "all")),
        "BS386",
      ),
    ).toHaveLength(1);
  });
});

describe("BS387 trigger pile-up", () => {
  it("flags a table with six row-level bsb triggers", async () => {
    const snap = snapshot((tables) => {
      notes(tables).triggers = [1, 2, 3, 4, 5, 6].map((n) =>
        trigger(`bsb_t${String(n)}`),
      );
    });

    const findings = await run(context(snap), "BS387");

    expect(findings).toHaveLength(1);
    expect(findings[0]?.target).toBe("public.notes");
  });

  it("ignores statement-level and app triggers", async () => {
    const snap = snapshot((tables) => {
      notes(tables).triggers = [
        ...[1, 2, 3, 4, 5].map((n) => trigger(`bsb_t${String(n)}`)),
        trigger("app_trigger"),
        { ...trigger("bsb_statement"), level: "statement" as const },
      ];
    });

    expect(await run(context(snap), "BS387")).toEqual([]);
  });
});

describe("BS388 search triggers on import targets", () => {
  const config = resolveConfig(
    {
      auth: { tenant: { column: "organization_id" } },
      recordTypes: { note: { table: "notes" } },
      blocks: {
        imports: { options: { targets: { note: { subjectType: "note" } } } },
      },
    },
    "/project",
  );

  const snap = snapshot((tables) => {
    notes(tables).triggers = [
      trigger("bsb_search_note_index", "better_supabase.search_index_note"),
    ];
  });

  const body = (
    guard: string,
  ): string => `create or replace function better_supabase.search_index_note()
returns trigger language plpgsql as $$
begin
  ${guard}
  perform better_supabase.search_refresh('note', new.id::text);
  return new;
end;
$$;`;

  it("flags a function without the guard", async () => {
    const findings = await run(
      {
        ...context(snap),
        config,
        sqlFiles: [{ path: "a.sql", text: body("") }],
      },
      "BS388",
    );

    expect(findings).toHaveLength(1);
  });

  it("accepts a guarded function and a function it can't find", async () => {
    const guarded = body(
      "if better_supabase.import_run() is not null then return new; end if;",
    );

    expect(
      await run(
        {
          ...context(snap),
          config,
          sqlFiles: [{ path: "a.sql", text: guarded }],
        },
        "BS388",
      ),
    ).toEqual([]);

    expect(await run({ ...context(snap), config }, "BS388")).toEqual([]);
  });

  it("accepts a function that defers through search_enqueue", async () => {
    const deferred = `create or replace function better_supabase.search_index_note()
returns trigger language plpgsql as $$
begin
  perform "better_supabase"."search_enqueue"('note', new.id::text);
  return null;
end;
$$;`;

    expect(
      await run(
        {
          ...context(snap),
          config,
          sqlFiles: [{ path: "a.sql", text: deferred }],
        },
        "BS388",
      ),
    ).toEqual([]);
  });

  it("skips projects without the imports block", async () => {
    expect(
      await run(
        { ...context(snap), sqlFiles: [{ path: "a.sql", text: body("") }] },
        "BS388",
      ),
    ).toEqual([]);
  });
});

describe("BS389 audit purge", () => {
  const withLog = snapshot((tables) => {
    const source = notes(tables);
    tables.push({
      ...structuredClone(source),
      schema: "better_supabase",
      name: "audit_events",
    });
  });

  it("flags an audit table nothing purges", async () => {
    expect(await run(context(withLog), "BS389")).toHaveLength(1);
  });

  it("accepts a call in the app's files or sources", async () => {
    expect(
      await run(
        {
          ...context(withLog),
          sqlFiles: [
            {
              path: "supabase/schemas/cron.sql",
              text: "select cron.schedule('p', '0 3 * * *', 'select better_supabase.purge_audit_log()');",
            },
          ],
        },
        "BS389",
      ),
    ).toEqual([]);

    expect(
      await run(
        {
          ...context(withLog),
          sources: [
            { path: "src/jobs.ts", text: "await audit.purgeAuditLog()" },
          ],
        },
        "BS389",
      ),
    ).toEqual([]);
  });

  it("does not count the module's own declaration", async () => {
    expect(
      await run(
        {
          ...context(withLog),
          sqlFiles: [
            {
              path: "supabase/schemas/audit.sql",
              text: "-- @bsb-block audit\ncreate function better_supabase.purge_audit_log() returns integer language sql as 'select 1';",
            },
          ],
        },
        "BS389",
      ),
    ).toHaveLength(1);
  });

  it("accepts a pg_cron job", async () => {
    expect(
      await run(
        {
          ...context(withLog),
          database: {
            describe: "test",
            session: true,
            query: (async () => [{ n: 1 }]) as never,
          },
        },
        "BS389",
      ),
    ).toEqual([]);
  });

  it("skips projects without the audit table", async () => {
    expect(await run(context(base), "BS389")).toEqual([]);
  });
});

describe("BS390 redundant indexes", () => {
  const withIndexes = (...indexes: CatalogTable["indexes"]) =>
    snapshot((tables) => {
      notes(tables).indexes = indexes;
    });

  it("flags an index that starts another", async () => {
    const findings = await run(
      context(
        withIndexes(
          index("notes_a", ["organization_id"]),
          index("notes_a_b", ["organization_id", "created_at"]),
        ),
      ),
      "BS390",
    );

    expect(findings).toHaveLength(1);
    expect(findings[0]?.target).toBe("public.notes:notes_a");
  });

  it("flags one of two identical indexes only", async () => {
    const findings = await run(
      context(
        withIndexes(
          index("notes_x", ["organization_id"]),
          index("notes_y", ["organization_id"]),
        ),
      ),
      "BS390",
    );

    expect(findings).toHaveLength(1);
    expect(findings[0]?.target).toBe("public.notes:notes_y");
  });

  it("keeps unique, partial and different-method indexes", async () => {
    expect(
      await run(
        context(
          withIndexes(
            index("notes_u", ["organization_id"], { unique: true }),
            index("notes_p", ["organization_id"], {
              partial: true,
              predicate: "(archived_at IS NULL)",
            }),
            index("notes_g", ["organization_id"], { method: "hash" }),
            index("notes_long", ["organization_id", "created_at"]),
          ),
        ),
        "BS390",
      ),
    ).toEqual([]);
  });
});

describe("BS391 null or any(param)", () => {
  const sql = (
    where: string,
  ): string => `create function public.pick(ids uuid[] default null)
returns setof public.notes language sql stable as $$
  select * from public.notes n where ${where};
$$;`;

  it("flags the pattern", async () => {
    const findings = await run(
      {
        ...context(base),
        sqlFiles: [
          { path: "s.sql", text: sql("ids is null or n.id = any(ids)") },
        ],
      },
      "BS391",
    );

    expect(findings).toHaveLength(1);
    expect(findings[0]?.location).toEqual({ file: "s.sql", line: 1 });
  });

  it("accepts a custom-plan function and the block modules' files", async () => {
    expect(
      await run(
        {
          ...context(base),
          sqlFiles: [
            {
              path: "a.sql",
              text: sql("ids is null or n.id = any(ids)").replace(
                "language sql",
                "language sql set plan_cache_mode = force_custom_plan",
              ),
            },
            {
              path: "m.sql",
              text: `-- @bsb-block notifications@1\n${sql("ids is null or n.id = any(ids)")}`,
            },
          ],
        },
        "BS391",
      ),
    ).toEqual([]);
  });

  it("accepts a plain any() and a migration", async () => {
    expect(
      await run(
        {
          ...context(base),
          sqlFiles: [
            { path: "s.sql", text: sql("n.id = any(ids)") },
            {
              path: "supabase/migrations/1_x.sql",
              text: sql("ids is null or n.id = any(ids)"),
            },
          ],
        },
        "BS391",
      ),
    ).toEqual([]);
  });
});

describe("BS392 searched tables", () => {
  const searched = (...indexes: CatalogTable["indexes"]) =>
    snapshot((tables) => {
      const table = notes(tables);
      table.comment = "@bsb search title";
      table.indexes = indexes;
    });

  it("flags a missing trigram and sort index", async () => {
    const findings = await run(
      context(
        searched(
          index("notes_pkey", ["id"], { primary: true }),
          index("notes_tsv", ["search_tsv"], { method: "gin" }),
        ),
      ),
      "BS392",
    );

    expect(findings.map((finding) => finding.target)).toEqual([
      "public.notes:search",
      "public.notes:sort",
    ]);
  });

  it("accepts a GIN and a time index", async () => {
    expect(
      await run(
        context(
          searched(
            index("notes_title_trgm", ["title"], { method: "gin" }),
            index("notes_time", ["organization_id", "created_at"]),
          ),
        ),
        "BS392",
      ),
    ).toEqual([]);
  });

  it("leaves tables without the option alone", async () => {
    expect(await run(context(base), "BS392")).toEqual([]);
  });
});

describe("BS393 import batches near the statement timeout", () => {
  const database = (mean: number, timeout: string | null) => ({
    describe: "test",
    session: true,
    query: (async (sql: string) => {
      if (sql.includes("from pg_extension")) {
        return [{ schema: "extensions" }];
      }

      if (sql.includes("pg_stat_statements")) {
        return [{ queryid: "7", calls: 12, mean_exec_time: mean }];
      }

      return [{ timeout }];
    }) as never,
  });

  const check = (mean: number, timeout: string | null, stats = true) =>
    run(
      { ...context(base), stats, database: database(mean, timeout) },
      "BS393",
    );

  it("flags a mean above half the timeout", async () => {
    const findings = await check(5000, "8s");

    expect(findings).toHaveLength(1);
    expect(findings[0]?.target).toBe("pg_stat_statements:7");
  });

  it("accepts a fast batch, no limit and a run without --stats", async () => {
    expect(await check(1000, "8s")).toEqual([]);
    expect(await check(500_000, "0")).toEqual([]);
    expect(await check(5000, "8s", false)).toEqual([]);
  });

  it("reads minutes", async () => {
    expect(await check(50_000, "2min")).toHaveLength(0);
    expect(await check(70_000, "2min")).toHaveLength(1);
  });

  it("reads hours and days, and skips a missing extension or a failed read", async () => {
    expect(await check(5000, "2h")).toEqual([]);
    expect(await check(50_000_000, "1d")).toHaveLength(1);
    expect(await check(5000, "500")).toHaveLength(1);
    expect(await check(5000, "never")).toEqual([]);

    const empty = {
      describe: "test",
      session: true,
      query: (async (sql: string) =>
        sql.includes("pg_stat_statements") ? [] : []) as never,
    };

    expect(
      await run({ ...context(base), stats: true, database: empty }, "BS393"),
    ).toEqual([]);

    const noBatches = {
      describe: "test",
      session: true,
      query: (async (sql: string) => {
        if (sql.includes("from pg_extension")) {
          return [{ schema: "extensions" }];
        }

        return sql.includes("pg_stat_statements") ? [] : [{ timeout: "8s" }];
      }) as never,
    };

    expect(
      await run(
        { ...context(base), stats: true, database: noBatches },
        "BS393",
      ),
    ).toEqual([]);

    const failed = {
      describe: "test",
      session: true,
      query: (async () => {
        throw new Error("down");
      }) as never,
    };

    const findings = await run(
      { ...context(base), stats: true, database: failed },
      "BS393",
    );

    expect(findings[0]?.message).toContain("down");
  });
});

describe("BS628 list cursor indexes", () => {
  const rule = RULES.find((entry) => entry.code === "BS628");

  const check = (text: string) =>
    rule!.check({
      sqlFiles: [{ path: "supabase/schemas/app.sql", text }],
    } as unknown as DoctorContext);

  it("flags a list ordered by created_at and id without an index", async () => {
    const findings = await check(`
      create or replace function app.list_cases()
      returns jsonb language sql as $$
        select 1 order by created_at desc, id desc
      $$;
    `);

    expect(findings.map((finding) => finding.message).join(" ")).toContain(
      "list_cases",
    );
  });

  it("accepts the same list when the file indexes both columns", async () => {
    const findings = await check(`
      create index cases_created_idx on app.cases (tenant_id, created_at desc, id desc);
      create or replace function app.list_cases()
      returns jsonb language sql as $$
        select 1 order by created_at desc, id desc
      $$;
    `);

    expect(findings).toEqual([]);
  });

  it("skips migrations and the files the blocks wrote", async () => {
    const list = `
      create or replace function app.list_cases()
      returns jsonb language sql as $$
        select 1 order by created_at desc, id desc
      $$;
    `;

    const findings = await rule!.check({
      sqlFiles: [
        { path: "supabase/migrations/1_cases.sql", text: list },
        {
          path: "supabase/schemas/900_better_supabase_001_cases.sql",
          text: `-- @bsb-block cases\n${list}`,
        },
      ],
    } as unknown as DoctorContext);

    expect(findings).toEqual([]);
  });

  it("ignores a list that does not continue by created_at and id", async () => {
    const findings = await check(`
      create or replace function app.list_cases()
      returns jsonb language sql as $$
        select 1
      $$;
    `);

    expect(findings).toEqual([]);
  });
});
