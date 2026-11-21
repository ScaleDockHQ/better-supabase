import { describe, expect, it } from "vitest";

import type { TableComment } from "../../../src/cli/gen/table-tags.ts";

import { withTableTags } from "../../../src/cli/gen/table-tags.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { moduleContext } from "../../../src/sql/module-context.ts";
import { lockModuleTable } from "../../../src/sql/modules/over-app.ts";
import { loadFixtureSnapshot } from "../fixtures/render.ts";

async function commented(
  name: string,
  comment: string,
): Promise<readonly TableComment[]> {
  const snapshot = await loadFixtureSnapshot();

  const found = snapshot.generator.tables.find(
    (each) => each.schema === "public",
  )!;

  return snapshot.generator.tables.map((each) =>
    each === found ? { ...each, name, comment } : { ...each, comment: null },
  );
}

describe("data-lifecycle and grant tags", () => {
  it("adds a lifecycle table entry to the installed block", async () => {
    const config = resolveConfig({ blocks: ["data-lifecycle"] }, "/tmp");

    const next = withTableTags(
      config,
      await commented(
        "invoices",
        "@bsb data-lifecycle user=owner_id tenant=organization_id export=false omit=notes",
      ),
    );

    expect(next.blocks["data-lifecycle"]?.options?.["tables"]).toEqual({
      invoices: {
        user: "owner_id",
        tenant: "organization_id",
        export: false,
        omit: ["notes"],
      },
    });
  });

  it("lets the config entry and the auto option win over the tag", async () => {
    const own = resolveConfig(
      {
        blocks: {
          "data-lifecycle": {
            options: { tables: { invoices: { user: "u" } } },
          },
        },
      },
      "/tmp",
    );

    const auto = resolveConfig(
      { blocks: { "data-lifecycle": { options: { tables: "auto" } } } },
      "/tmp",
    );

    const comments = await commented(
      "invoices",
      "@bsb data-lifecycle user=owner_id",
    );

    expect(
      withTableTags(own, comments).blocks["data-lifecycle"]?.options?.[
        "tables"
      ],
    ).toEqual({ invoices: { user: "u" } });
    expect(
      withTableTags(auto, comments).blocks["data-lifecycle"]?.options?.[
        "tables"
      ],
    ).toBe("auto");
  });

  it("ignores a lifecycle tag when the block is not installed", async () => {
    const config = resolveConfig({ blocks: {} }, "/tmp");

    expect(
      withTableTags(
        config,
        await commented("invoices", "@bsb data-lifecycle user=a"),
      ).blocks["data-lifecycle"],
    ).toBeUndefined();
  });

  it("turns a grant tag into an expose entry, unless the config has one", async () => {
    const config = resolveConfig({ blocks: {} }, "/tmp");

    const comments = await commented(
      "invoices",
      '@bsb grant authenticated="select,update(title)" anon=select',
    );

    expect(withTableTags(config, comments).expose["invoices"]).toMatchObject({
      authenticated: ["select", "update(title)"],
      anon: ["select"],
    });

    const own = resolveConfig(
      { database: { expose: { invoices: ["select"] } }, blocks: {} },
      "/tmp",
    );

    expect(
      withTableTags(own, comments).expose["invoices"]?.authenticated,
    ).toEqual(["select"]);
  });

  it("ignores a tag that does not parse", async () => {
    const config = resolveConfig({ blocks: ["data-lifecycle"] }, "/tmp");

    expect(
      withTableTags(
        config,
        await commented("invoices", "@bsb grant authenticated=drop"),
      ).expose["invoices"],
    ).toBeUndefined();
    expect(
      withTableTags(
        config,
        await commented("invoices", "@bsb data-lifecycle user=a purge=maybe"),
      ).blocks["data-lifecycle"]?.options?.["tables"],
    ).toBeUndefined();
  });

  it("exposes an adopted table, so the block only enables row level security there", async () => {
    const config = withTableTags(
      resolveConfig({ blocks: {} }, "/tmp"),
      await commented("invoices", "@bsb grant authenticated=select"),
    );

    const layout = (grants: boolean) => ({
      modules: { promotions: { tables: { promotions: "public.invoices" } } },
      ...(grants
        ? {
            grants: Object.entries(config.expose).flatMap(([table, entry]) =>
              entry.authenticated.map(() => ({
                table,
                role: "authenticated" as const,
                privileges: entry.authenticated,
              })),
            ),
          }
        : {}),
    });

    const locked = (grants: boolean): string =>
      lockModuleTable(
        moduleContext("promotions", layout(grants), ["promotions"]),
        "promotions",
      );

    expect(config.expose["invoices"]).toBeDefined();
    expect(locked(true)).toBe(
      'alter table "public"."invoices" enable row level security;',
    );
    expect(locked(false)).not.toBe(locked(true));
  });
});
