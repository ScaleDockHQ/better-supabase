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

function tenantSnapshot(): Snapshot {
  const copy = structuredClone(toCatalog(base)) as Mutable<Catalog>;
  const tables = copy.tables as Mutable<CatalogTable>[];
  const notes = tables.find((entry) => entry.name === "notes")!;
  const tags = tables.find((entry) => entry.name === "tags")!;
  const tenant = { ...notes.columns[0]!, name: "organization_id" };

  for (const entry of [notes, tags]) {
    entry.columns = [
      ...entry.columns.filter((column) => column.name !== "organization_id"),
      tenant,
    ];
  }

  notes.columns = [...notes.columns, { ...tenant, name: "tag_id" }];
  notes.foreignKeys = [
    {
      name: "notes_tag_id_fkey",
      columns: ["tag_id"],
      refSchema: "public",
      refTable: "tags",
      refColumns: ["id"],
      oneToOne: false,
      onDelete: "no action",
      onUpdate: "no action",
    },
  ];
  notes.triggers = [
    {
      name: "notes_tag_guard",
      timing: "before",
      events: ["insert", "update"],
      level: "row",
      function: "public.notes_tag_guard",
    },
  ];

  return fromCatalog(copy);
}

const trigger = (
  body: string,
): string => `create function public.notes_tag_guard()
returns trigger language plpgsql as $$
begin
  ${body}
  return new;
end;
$$;
create trigger notes_tag_guard before insert or update on public.notes
  for each row execute function public.notes_tag_guard();`;

const context = (body: string): DoctorContext => ({
  config: resolveConfig({ blocks: ["memberships"] }, "/project"),
  snapshot: tenantSnapshot(),
  configToml: undefined,
  envFiles: [],
  gitignore: "",
  sources: [],
  sqlFiles: [{ path: "supabase/schemas/notes.sql", text: trigger(body) }],
});

const run = (code: string, ctx: DoctorContext) =>
  runRules(
    ctx,
    RULES.filter((rule) => rule.code === code),
  );

const target = (findings: readonly { readonly target?: string }[]) =>
  findings.filter((finding) => finding.target === "public.notes.tag_id");

describe("an app trigger on a tenant foreign key (BS340, BS398)", () => {
  const guarded =
    "if not exists (select 1 from public.tags t where t.id = new.tag_id and t.organization_id = new.organization_id) then raise exception 'tenant'; end if;";

  const unguarded =
    "if new.tag_id is null then raise exception 'tag required'; end if;";

  it("is registered", () => {
    expect(RULES.map((rule) => rule.code)).toContain("BS398");
  });

  it("makes BS340 accept the key, and BS398 stays quiet when the body checks the tenant", async () => {
    expect(target(await run("BS340", context(guarded)))).toEqual([]);
    expect(target(await run("BS398", context(guarded)))).toEqual([]);
  });

  it("still lists the key for BS340 without any app trigger", async () => {
    const ctx = { ...context(guarded), sqlFiles: [] };

    expect(target(await run("BS340", ctx))).toHaveLength(1);
    expect(target(await run("BS398", ctx))).toEqual([]);
  });

  it("reports a trigger that touches the column without the tenant (BS398)", async () => {
    const findings = target(await run("BS398", context(unguarded)));

    expect(findings).toMatchObject([
      {
        severity: "warning",
        message: expect.stringContaining("no trigger body mentions"),
      },
    ]);
  });
});
