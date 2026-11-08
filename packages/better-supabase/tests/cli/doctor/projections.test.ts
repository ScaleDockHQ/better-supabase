import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";
import type {
  Catalog,
  CatalogTable,
} from "../../../src/cli/introspect/types.ts";
import type { BetterSupabaseConfig } from "../../../src/config/index.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import { PROJECTION_RULES } from "../../../src/cli/doctor/projections.ts";
import { toCatalog } from "../../../src/cli/introspect/catalog.ts";
import { fromCatalog } from "../../../src/cli/introspect/from-catalog.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { snapshotFixture } from "../fixtures/library.ts";

const base = await parseSnapshot(snapshotFixture);

type Mutable<T> = { -readonly [K in keyof T]: T[K] };

const VIEW = `create view public.job_attachments with (security_invoker = true) as
  select id, tenant_id as organization_id, name from better_supabase.attachments where subject_type = 'job';`;

const context = (
  config: BetterSupabaseConfig,
  extra: Partial<DoctorContext> = {},
  snapshot = base,
): DoctorContext => ({
  config: resolveConfig(config, "/project"),
  snapshot,
  configToml: undefined,
  envFiles: [],
  gitignore: "",
  sources: [],
  ...extra,
});

const check = (code: string, ctx: DoctorContext) =>
  PROJECTION_RULES.filter((rule) => rule.code === code).flatMap(
    (rule) => rule.check(ctx) as { message: string }[],
  );

describe("BS381", () => {
  const sqlFiles = [
    { path: "supabase/schemas/030_projections.sql", text: VIEW },
  ];

  const config = { blocks: { attachments: {} } };

  const sources = (text: string) => [{ path: "src/native.ts", text }];

  it("flags a helper that names the block's table while a view projects it", () => {
    const found = check(
      "BS381",
      context(config, {
        sqlFiles,
        sources: sources(
          'export const bsb = createNativeClient(app, supabase, { engine: powersyncEngine(db, { tables: { "better_supabase.attachments": route } }) });',
        ),
      }),
    );

    expect(found).toHaveLength(2);
    expect(found[0]?.message).toContain("public.job_attachments");
  });

  it("flags the bare table name when the view has another name", () => {
    expect(
      check(
        "BS381",
        context(config, {
          sqlFiles,
          sources: sources(
            "const route = attachmentQueueRoute(server.db.attachments);",
          ),
        }),
      ),
    ).toHaveLength(1);
  });

  it("accepts a call that names the view, and a call with no projection", () => {
    expect(
      check(
        "BS381",
        context(config, {
          sqlFiles,
          sources: sources(
            "powersyncEngine(db, { tables: { job_attachments: route } });",
          ),
        }),
      ),
    ).toStrictEqual([]);

    expect(
      check(
        "BS381",
        context(config, {
          sqlFiles: [],
          sources: sources("attachmentQueueRoute(server.db.attachments);"),
        }),
      ),
    ).toStrictEqual([]);
  });
});

describe("BS382", () => {
  const tagged = (comment: string) => {
    const copy = structuredClone(toCatalog(base)) as Mutable<Catalog>;

    const notes = (copy.tables as Mutable<CatalogTable>[]).find(
      (table) => table.schema === "public" && table.name === "notes",
    )!;

    notes.comment = comment;

    return fromCatalog(copy);
  };

  it("flags an option the tag and the config give differently", () => {
    const found = check(
      "BS382",
      context(
        { subjects: { notes: { table: "notes", title: "subject" } } },
        {},
        tagged("@bsb subject title=name"),
      ),
    );

    expect(found).toHaveLength(1);
    expect(found[0]?.message).toContain("notes.title");
    expect(found[0]?.message).toContain('"name"');
    expect(found[0]?.message).toContain('"subject"');
  });

  it("accepts a tag the config repeats or does not set", () => {
    const snapshot = tagged("@bsb subject title=name");

    expect(
      check(
        "BS382",
        context(
          { subjects: { notes: { table: "notes", title: "name" } } },
          {},
          snapshot,
        ),
      ),
    ).toStrictEqual([]);

    expect(check("BS382", context({}, {}, snapshot))).toStrictEqual([]);
  });
});
