import { readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";

import { resolveConfig } from "../../src/config/index.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { moduleLayout } from "../../src/sql/layout.ts";
import { renderModules } from "../../src/sql/registry.ts";

const contents = (name: string, config: Record<string, unknown> = {}) =>
  renderModules([name], moduleLayout(resolveConfig(config, "/project"))).find(
    (file) => file.path.includes(name.replaceAll("-", "_")),
  )!;

const ENTITLEMENTS = {
  entitlements: { customer: "organizations.stripe_customer_id" },
};

describe("pgTAP", () => {
  const file = contents("pgtap");

  it("writes the helpers to supabase/tests so `supabase test db` runs them first", () => {
    expect(file.path).toBe("supabase/tests/000_better_supabase_pgtap.test.sql");
  });

  it("installs pgtap and runs as a TAP test with a plan and finish", () => {
    expect(file.contents).toContain(
      "create extension if not exists pgtap with schema extensions;",
    );
    const plans = [
      ...file.contents.matchAll(/select extensions\.plan\((\d+)\);/g),
    ];
    expect(plans).toHaveLength(1);
    const assertions =
      file.contents
        .slice(plans[0]!.index)
        .match(
          /select (extensions\.)?(ok|is|isnt|has_function|lives_ok|throws_ok|pass)\(/g,
        ) ?? [];
    expect(assertions).toHaveLength(Number(plans[0]![1]));
    expect(file.contents.trimEnd()).toMatch(
      /select \* from extensions\.finish\(\);$/,
    );
  });

  it("defines the documented helpers", () => {
    for (const helper of [
      "tests.create_user",
      "tests.authenticate_as",
      "tests.authenticate_as_anon",
      "tests.rls_enabled",
    ])
      expect(file.contents).toContain(`create or replace function ${helper}(`);
  });
});

describe(`pgvector iterative index scans (${SPEC_PINS.pgvector}+)`, () => {
  const file = contents("vector-search", {
    vectorSearch: {
      chunks: "embedding",
      "docs.pages": { column: "vec", distance: "inner_product" },
      "docs.images": { column: "vec", distance: "l2" },
    },
  });

  it("sets hnsw.iterative_scan to a value pgvector 0.8 accepts", () => {
    const values = [
      ...file.contents.matchAll(/set hnsw\.iterative_scan = '([a-z_]+)'/g),
    ].map((match) => match[1]);
    expect(values).toHaveLength(3);
    for (const value of values)
      expect(["strict_order", "relaxed_order"]).toContain(value);
  });

  it("uses the pgvector distance operator for each metric, schema-qualified", () => {
    expect(file.contents).toContain(
      'order by t."embedding" operator(extensions.<=>) query',
    );
    expect(file.contents).toContain('"docs"."search_pages"');
    expect(file.contents).toContain(
      'order by t."vec" operator(extensions.<#>) query',
    );
    expect(file.contents).toContain(
      'order by t."vec" operator(extensions.<->) query',
    );
  });

  it("is security invoker so RLS filters inside the index scan, and bounds k", () => {
    expect(file.contents.match(/^security invoker$/gm)).toHaveLength(3);
    expect(file.contents).not.toContain("security definer");
    expect(file.contents).toContain("limit least(greatest(k, 1), 1000)");
  });

  it("SPEC_PINS.pgvector is the minimum version with iterative scans", () => {
    const [major, minor] = SPEC_PINS.pgvector.split(".").map(Number);
    expect(major! > 0 || minor! >= 8).toBe(true);
  });
});

describe(`Stripe Sync Engine schema (${SPEC_PINS.stripeSyncEngine})`, () => {
  it("reads only columns that stripe.active_entitlements has at the pinned release", async () => {
    const migration = await readFile(
      new URL(
        `schemas/stripe-sync-engine-${SPEC_PINS.stripeSyncEngine}-active-entitlements.sql`,
        import.meta.url,
      ),
      "utf8",
    );
    const columns = new Set(
      [...migration.matchAll(/^\s+"([a-z_]+)" [a-z]/gm)].map(
        (match) => match[1],
      ),
    );
    expect(columns).toContain("customer");
    const sql = contents("entitlements", ENTITLEMENTS).contents;
    expect(sql).toContain("from stripe.active_entitlements e");
    const from = sql.indexOf("from stripe.active_entitlements e");
    const statement = sql.slice(
      sql.lastIndexOf("select", from),
      sql.indexOf(";", from),
    );
    const used = new Set(
      [...statement.matchAll(/\be\.([a-z_]+)/g)].map((match) => match[1]),
    );
    expect(used.size).toBeGreaterThan(0);
    for (const column of used) expect(columns).toContain(column);
  });

  it("returns no entitlements until the engine's table exists", () => {
    expect(contents("entitlements", ENTITLEMENTS).contents).toContain(
      "to_regclass('stripe.active_entitlements') is null",
    );
  });
});
