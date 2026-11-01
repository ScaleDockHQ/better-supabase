import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../src/sql/context.ts";
import type { BlockSql } from "../../src/sql/module-types.ts";

import { SQL_MODULES } from "../../src/sql/registry.ts";
import { renderBlocks, seedDefaultsSql } from "../../src/sql/render.ts";
import {
  renderSeedDefaults,
  renderSeedUmbrella,
  seedFunctionName,
} from "../../src/sql/seeds.ts";

const TABLE = {
  table: "public.stages",
  tenantColumn: "organization_id",
  key: ["key"],
  rows: [
    { values: { key: "open", name: "It's open", position: 1 } },
    {
      values: {
        key: "won",
        settings: { json: { color: "green" } },
        pipeline: {
          ref: {
            table: "public.pipelines",
            tenantColumn: "organization_id",
            match: { key: "sales" },
          },
        },
      },
    },
  ],
} as const;

describe("renderSeedDefaults", () => {
  const sql = renderSeedDefaults(
    "deals",
    "public.seed_deals_defaults",
    "uuid",
    [TABLE],
  );

  it("names the function after the module", () => {
    expect(seedFunctionName("state-machine")).toBe(
      "seed_state_machine_defaults",
    );
    expect(sql).toContain(
      "create or replace function public.seed_deals_defaults(p_tenant uuid",
    );
  });

  it("inserts a row only when its key is missing for the organization", () => {
    expect(sql.match(/where not exists/g)).toHaveLength(2);
    expect(sql).toContain(
      'x."organization_id" = p_tenant and x."key" is not distinct from \'open\'',
    );
  });

  it("escapes strings and resolves references inside the tenant", () => {
    expect(sql).toContain("'It''s open'");
    expect(sql).toContain('\'{"color":"green"}\'::jsonb');
    expect(sql).toContain(
      '(select x."id" from public.pipelines x where x."organization_id" = p_tenant and x."key" = \'sales\' limit 1)',
    );
  });

  it("is not callable by clients", () => {
    expect(sql).toContain(
      "revoke execute on function public.seed_deals_defaults(uuid, text, text) from public, anon, authenticated;",
    );
  });

  it("guards rows by variant and locale", () => {
    const guarded = renderSeedDefaults(
      "tax",
      "public.seed_tax_defaults",
      "uuid",
      [{ ...TABLE, variant: "nl", locales: ["nl", "en"] }],
    );

    expect(guarded).toContain(
      "p_variant is not distinct from 'nl' and p_locale = any (array['nl', 'en'])",
    );
  });

  it("refuses a row without its key", () => {
    expect(() =>
      renderSeedDefaults("x", "public.f", "uuid", [
        { ...TABLE, rows: [{ values: { name: "a" } }] },
      ]),
    ).toThrow(/no value for its key column/);
  });

  it("refuses a table without a key", () => {
    expect(() =>
      renderSeedDefaults("x", "public.f", "uuid", [{ ...TABLE, key: [] }]),
    ).toThrow(/key column/);
  });
});

describe("renderSeedUmbrella", () => {
  it("calls each module's function with its variant", () => {
    const sql = renderSeedUmbrella("public", "uuid", [
      { module: "cases", fn: "public.seed_cases_defaults" },
    ]);

    expect(sql).toContain(
      "perform public.seed_cases_defaults(p_tenant, p_variants ->> 'cases', p_locale);",
    );
  });
});

describe("declared defaults", () => {
  const declared = Object.values(SQL_MODULES).filter(
    (module) => module.seeds?.defaults,
  );

  // No shipped module declares defaults yet: each one that does needs a fixture
  // migration (ADR 0196). This keeps the check ready for the first.
  it.skipIf(declared.length === 0)("each one is checked below", () => {
    expect(declared.length).toBeGreaterThan(0);
  });

  it.each(declared.map((module) => module.name))(
    "%s renders idempotent, tenant-scoped inserts",
    (name) => {
      const files = renderBlocks([...SQL_MODULES[name]!.requires, name], {});

      const sql = files
        .filter((file) => file.module === name)
        .map((file) => file.contents)
        .join("\n");

      const start = sql.indexOf(`"${seedFunctionName(name)}"(`);
      const body = sql.slice(start, sql.indexOf("\n$$;", start));
      const inserts = body.match(/insert into /g)?.length ?? 0;

      expect(inserts).toBeGreaterThan(0);
      expect(body.match(/where not exists/g)?.length).toBe(inserts);
      expect(body).toMatch(/p_tenant/);
    },
  );
});

describe("seedDefaultsSql", () => {
  // SAFETY: the renderer reads only `fn` and `idType` from the context.
  const ctx = {
    fn: (name: string) => `app.${name}`,
    idType: "uuid",
  } as unknown as BlockSqlContext;

  const module = (defaults: BlockSql["seeds"]) =>
    ({ name: "demo-block", seeds: defaults }) as unknown as BlockSql;

  it("renders nothing for a module without defaults", () => {
    expect(seedDefaultsSql(module(undefined), ctx)).toBe("");
    expect(seedDefaultsSql(module({ defaults: () => [] }), ctx)).toBe("");
  });

  it("renders the module's function under its qualified name", () => {
    const sql = seedDefaultsSql(module({ defaults: () => [TABLE] }), ctx);

    expect(sql).toContain(
      "create or replace function app.seed_demo_block_defaults(",
    );
  });
});
