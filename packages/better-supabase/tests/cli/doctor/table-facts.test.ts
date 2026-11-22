import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";
import type {
  Catalog,
  CatalogTable,
  Snapshot,
} from "../../../src/cli/introspect/types.ts";
import type { BetterSupabaseConfig } from "../../../src/config/index.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import { RULES, runRules } from "../../../src/cli/doctor/rules.ts";
import { toCatalog } from "../../../src/cli/introspect/catalog.ts";
import { fromCatalog } from "../../../src/cli/introspect/from-catalog.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { snapshotFixture as fixture } from "../fixtures/library.ts";

const base = await parseSnapshot(fixture);

type Mutable<T> = { -readonly [K in keyof T]: T[K] };

const publicTable = (): string =>
  toCatalog(base).tables.find(
    (entry) => entry.schema === "public" && entry.kind === "table",
  )!.name;

function commented(
  name: string,
  comment: string,
  column?: { name: string; comment: string },
): Snapshot {
  const copy = structuredClone(toCatalog(base)) as Mutable<Catalog>;

  const found = (copy.tables as Mutable<CatalogTable>[]).find(
    (entry) => entry.schema === "public" && entry.name === name,
  )!;

  found.comment = comment;

  if (column !== undefined) {
    const target = found.columns.find((entry) => entry.name === column.name)!;

    (target as { comment: string | null }).comment = column.comment;
  }

  return fromCatalog(copy);
}

const context = (
  snapshot: Snapshot,
  config: BetterSupabaseConfig = {},
): DoctorContext => ({
  config: resolveConfig(config, "/project"),
  snapshot,
  configToml: undefined,
  envFiles: [],
  gitignore: "",
  sources: [],
});

const run = (code: string, ctx: DoctorContext) =>
  runRules(
    ctx,
    RULES.filter((rule) => rule.code === code),
  );

describe("audit-exempt tag (BS315)", () => {
  it("exempts a tagged table and asks for a reason when the tag has none", async () => {
    const name = publicTable();

    const withReason = await run(
      "BS315",
      context(commented(name, '@bsb audit-exempt reason="scratch data"'), {
        blocks: ["audit"],
      }),
    );

    const without = await run(
      "BS315",
      context(commented(name, "@bsb audit-exempt"), { blocks: ["audit"] }),
    );

    expect(withReason.map((finding) => finding.target)).not.toContain(
      `public.${name}`,
    );
    expect(without.map((finding) => finding.target)).toContain(
      `public.${name}`,
    );
    expect(
      without.find((finding) => finding.target === `public.${name}`)?.message,
    ).toContain("without a reason");
  });
});

describe("table facts held in the config (BS702)", () => {
  it("lists a table whose comment lacks the fact and skips one that has it", async () => {
    const name = publicTable();

    const config: BetterSupabaseConfig = {
      database: { expose: { [name]: ["select"] } },
      blocks: {
        audit: {
          options: { exempt: [{ table: `public.${name}`, reason: "scratch" }] },
        },
      },
    };

    const findings = await run("BS702", context(base, config));

    expect(findings).toHaveLength(1);
    expect(findings[0]).toMatchObject({
      severity: "info",
      target: `public.${name}`,
    });
    expect(findings[0]?.message).toContain("audit-exempt, grant");
    expect(findings[0]?.message).toContain("codemod table-tags");

    expect(
      await run(
        "BS702",
        context(
          commented(
            name,
            '@bsb audit-exempt reason="scratch"; grant authenticated=select',
          ),
          config,
        ),
      ),
    ).toEqual([]);
  });
});

describe("table tags that cannot take effect (BS703)", () => {
  it("reports a lifecycle tag without a column, a bad flag and a bad grant", async () => {
    const name = publicTable();

    const messages = async (comment: string): Promise<string[]> =>
      (await run("BS703", context(commented(name, comment)))).map(
        (finding) => finding.message,
      );

    expect(await messages("@bsb data-lifecycle export=false")).toEqual([
      expect.stringContaining("neither user= nor tenant="),
    ]);
    expect(
      await messages("@bsb data-lifecycle user=owner_id purge=maybe"),
    ).toEqual([expect.stringContaining("must be true or false")]);
    expect(await messages("@bsb grant authenticated=drop")).toHaveLength(1);
    expect(await messages("@bsb data-lifecycle user=owner_id")).toEqual([]);
    expect(await messages("@bsb grant authenticated=select")).toEqual([]);
  });

  it("reports same-tenant on a column no foreign key holds", async () => {
    const name = publicTable();

    const column = toCatalog(base).tables.find(
      (entry) => entry.schema === "public" && entry.name === name,
    )!.columns[0]!.name;

    const findings = await run(
      "BS703",
      context(
        commented(name, "", { name: column, comment: "@bsb same-tenant" }),
      ),
    );

    expect(findings.map((finding) => finding.message)).toEqual([
      expect.stringContaining(`same-tenant on ${column}`),
    ]);
  });
});
