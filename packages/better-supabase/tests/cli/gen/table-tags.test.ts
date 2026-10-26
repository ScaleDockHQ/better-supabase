import { describe, expect, it } from "vitest";

import type { Snapshot } from "../../../src/cli/introspect/types.ts";

import { withTableTags } from "../../../src/cli/gen/table-tags.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { loadFixtureSnapshot } from "../fixtures/render.ts";

async function tagged(table: string, comment: string): Promise<Snapshot> {
  const { schema } = await first();
  const snapshot = await loadFixtureSnapshot();

  return {
    ...snapshot,
    generator: {
      ...snapshot.generator,
      tables: snapshot.generator.tables.map((each) =>
        each.schema === schema && each.name === table
          ? { ...each, comment }
          : each,
      ),
    },
  };
}

async function first(): Promise<{ schema: string; name: string; key: string }> {
  const snapshot = await loadFixtureSnapshot();
  const { schemas } = resolveConfig({ blocks: {} }, "/tmp");

  const table = snapshot.generator.tables.find((each) =>
    schemas.includes(each.schema),
  );

  if (table === undefined) {
    throw new Error("The fixture has no table in the default schemas.");
  }

  return {
    schema: table.schema,
    name: table.name,
    key:
      table.schema === "public" ? table.name : `${table.schema}.${table.name}`,
  };
}

describe("withTableTags", () => {
  it("returns the config itself without tags", async () => {
    const config = resolveConfig({ blocks: {} }, "/tmp");

    expect(withTableTags(config, await loadFixtureSnapshot())).toBe(config);
  });

  it("turns subject, realtime and vector-search tags into config", async () => {
    const { name, key } = await first();
    const config = resolveConfig({ blocks: {} }, "/tmp");

    const next = withTableTags(
      config,
      await tagged(
        name,
        "Free text. @bsb subject title=id url=/x/{id}; realtime global; vector-search column=embedding",
      ),
    );

    expect(next.subjects[name]).toMatchObject({ table: key, title: "id" });
    expect(next.realtime.tables).toContain(key);
    expect(next.realtime.global).toContain(key);
    expect(next.vectorSearch).toContainEqual({
      table: key,
      column: "embedding",
      distance: "cosine",
    });
  });

  it("keeps what the config sets itself", async () => {
    const { name, key } = await first();

    const base = resolveConfig({ blocks: {} }, "/tmp");

    const config = {
      ...base,
      subjects: { [name]: { table: key, title: "kept" } },
    };

    const next = withTableTags(
      config,
      await tagged(name, "@bsb subject title=other"),
    );

    expect(next.subjects[name]?.title).toBe("kept");
  });

  it("skips tables outside the schemas and unusable tags", async () => {
    const { name, key } = await first();
    const config = resolveConfig({ blocks: {} }, "/tmp");

    const ignored = withTableTags(
      config,
      await tagged(
        name,
        "@bsb vector-search column=e distance=manhattan; vector-search; subject type=a tenant=org; unknown",
      ),
    );

    expect(ignored.vectorSearch).toEqual([]);
    expect(ignored.subjects["a"]).toMatchObject({ table: key, tenant: "org" });

    const present = {
      ...config,
      realtime: { ...config.realtime, tables: [key] },
      vectorSearch: [{ table: key, column: "x", distance: "cosine" as const }],
    };

    const kept = withTableTags(
      present,
      await tagged(name, "@bsb realtime; vector-search column=y"),
    );

    expect(kept.realtime.tables).toEqual([key]);
    expect(kept.vectorSearch).toHaveLength(1);

    const outside = withTableTags(
      { ...config, schemas: ["nowhere"] },
      await tagged(name, "@bsb realtime"),
    );

    expect(outside.realtime.tables).toEqual([]);
  });

  it("reads realtime global and user arguments and subject url", async () => {
    const { name, key } = await first();
    const config = resolveConfig({ blocks: {} }, "/tmp");

    const next = withTableTags(
      config,
      await tagged(
        name,
        "@bsb realtime global user=owner_id; subject url=/x/{id}",
      ),
    );

    expect(next.realtime.global).toContain(key);
    expect(next.realtime.users[key]).toBe("owner_id");
    expect(next.subjects[name]?.url).toBe("/x/{id}");
  });
});
