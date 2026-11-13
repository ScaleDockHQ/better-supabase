import { describe, expect, it } from "vitest";

import type { BlockSqlLink } from "../../src/sql/links.ts";

import { BLOCK_CONCERNS, blockLink } from "../../src/blocks/composition.ts";
import { defineBlock } from "../../src/blocks/define-block.ts";
import { withSearchDefault } from "../../src/blocks/entity-search.ts";
import { BLOCK_MANIFESTS } from "../../src/blocks/registry.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";

/**
 * A block declares its links and concerns in the manifest (ADR 0830) and the
 * SQL module still renders from `NAMES`. These tests keep the two equal.
 */

const moduleNames = (block: { readonly sql: readonly string[] }) =>
  block.sql.flatMap((name) => {
    const names = SQL_MODULES[name]?.names;

    return names === undefined ? [] : [names];
  });

describe("the composition of a manifest", () => {
  it("defaults to no links and no concerns", () => {
    const block = defineBlock({ name: "empty", category: "admin" });

    expect(block.links).toStrictEqual([]);
    expect(block.concerns).toStrictEqual([]);
  });

  it("writes a link in one line", () => {
    expect(
      blockLink("task", "reference", "time_entry", "tasks", "task"),
    ).toStrictEqual({
      key: "task",
      kind: "reference",
      source: "time_entry",
      target: { block: "tasks", entity: "task" },
    });

    expect(
      blockLink(
        "fromDeal",
        "conversion",
        "quote",
        "deals",
        "deal",
        "quote_from_deal",
      ).via,
    ).toBe("quote_from_deal");
  });

  it("declares the links its SQL modules declare", () => {
    for (const block of BLOCK_MANIFESTS) {
      const sql: BlockSqlLink[] = moduleNames(block).flatMap((names) => [
        ...(names.links ?? []),
      ]);

      expect({ name: block.name, links: block.links ?? [] }).toStrictEqual({
        name: block.name,
        links: sql,
      });
    }
  });

  it("points every link at an entity of an existing block", () => {
    for (const block of BLOCK_MANIFESTS) {
      for (const link of block.links ?? []) {
        const target = BLOCK_MANIFESTS.find(
          (each) => each.name === link.target.block,
        );

        expect(target, `${block.name}.${link.key}`).toBeDefined();
        expect(
          Object.keys(block.entities ?? {}),
          `${block.name}.${link.key}`,
        ).toContain(link.source);
        expect(
          Object.keys(target?.entities ?? {}),
          `${block.name}.${link.key}`,
        ).toContain(link.target.entity);
      }
    }
  });

  it("declares the concerns its SQL modules and entities imply", () => {
    for (const block of BLOCK_MANIFESTS) {
      const found = new Set<string>();

      for (const names of moduleNames(block)) {
        for (const raw of Object.values(names.entities ?? {})) {
          const spec = withSearchDefault(raw, block.entities ?? {});

          if ((spec.subject?.history ?? []).length > 0) {
            found.add("history");
          }

          if (
            spec.table !== undefined &&
            names.tables[spec.table]?.lifecycle !== undefined
          ) {
            found.add("lifecycle");
          }

          if (spec.subject?.realtime === true) {
            found.add("realtime");
          }

          if (spec.subject?.search !== undefined) {
            found.add("search");
          }
        }
      }

      expect({
        name: block.name,
        concerns: block.concerns ?? [],
      }).toStrictEqual({
        name: block.name,
        concerns: BLOCK_CONCERNS.filter((concern) => found.has(concern)),
      });
    }
  });
});

describe("withSearchDefault", () => {
  const spec = {
    table: "notes",
    singular: "note",
    subject: {
      title: "title",
      permissions: { read: "notes.read", write: "notes.write" },
    },
  };

  it("registers the title column and no body", () => {
    expect(withSearchDefault(spec, {}).subject?.search).toStrictEqual({
      title: "title",
      body: [],
    });
  });

  it("takes the body columns the manifest entity lists", () => {
    expect(
      withSearchDefault(spec, { note: { search: ["text"] } }).subject?.search,
    ).toStrictEqual({ title: "title", body: ["text"] });
  });

  it("leaves an entity that opts out and one that names its own", () => {
    expect(withSearchDefault(spec, { note: { search: false } })).toBe(spec);

    const own = {
      ...spec,
      subject: { ...spec.subject, search: { title: "name", body: [] } },
    };

    expect(withSearchDefault(own, {})).toBe(own);
  });

  it("leaves an entity that is not a subject", () => {
    const plain = { table: "notes", singular: "note" };

    expect(withSearchDefault(plain, {})).toBe(plain);
  });
});
