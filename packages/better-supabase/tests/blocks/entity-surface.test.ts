import { describe, expect, it } from "vitest";

import type { AnyBlock } from "../../src/blocks/define-block.ts";

import { defineBlock } from "../../src/blocks/define-block.ts";
import {
  ENTITY_METHODS,
  ENTITY_MUTABILITIES,
} from "../../src/blocks/entity-surface.ts";
import { BLOCK_MANIFESTS } from "../../src/blocks/registry.ts";
import { EMIT_GAPS } from "./emit-gaps.ts";

/**
 * Every block declares the entities it owns (ADR 0689). `emit-gaps.ts` holds
 * today's mutating methods without an event; shrink it, never grow it.
 */

const KEY = /^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$/;

const entriesOf = (
  block: AnyBlock,
): [string, NonNullable<AnyBlock["entities"]>[string]][] =>
  Object.entries(block.entities ?? {});

describe("the entity surface of a manifest", () => {
  it("defaults to no entities", () => {
    const block = defineBlock({ name: "empty", category: "admin" });

    expect(block.entities).toStrictEqual({});
  });

  it("keeps what a block declares", () => {
    const block = defineBlock({
      name: "demo",
      category: "admin",
      entities: {
        note: {
          mutability: "editable",
          sorts: ["createdAt"],
          emits: { update: false },
        },
      },
    });

    expect(block.entities["note"]?.sorts).toStrictEqual(["createdAt"]);
  });

  it("is declared by every block that installs SQL", () => {
    const without = BLOCK_MANIFESTS.filter(
      (block) => block.sql.length > 0 && entriesOf(block).length === 0,
    ).map((block) => block.name);

    expect(without).toStrictEqual([]);
  });

  it("gives every entity a snake_case key and a mutability", () => {
    for (const block of BLOCK_MANIFESTS) {
      for (const [key, surface] of entriesOf(block)) {
        expect(key, `${block.name}.${key}`).toMatch(KEY);
        expect(ENTITY_MUTABILITIES, `${block.name}.${key}`).toContain(
          surface.mutability,
        );
      }
    }
  });

  it("only declares emits for methods an entity has", () => {
    for (const block of BLOCK_MANIFESTS) {
      for (const [key, surface] of entriesOf(block)) {
        const methods = Object.keys(surface.emits ?? {});

        expect(
          methods.filter(
            (method) => !ENTITY_METHODS.some((each) => each === method),
          ),
          `${block.name}.${key}`,
        ).toStrictEqual([]);

        expect(
          surface.mutability === "read-only" ? methods : [],
          `${block.name}.${key}`,
        ).toStrictEqual([]);
      }
    }
  });

  it("names an event of the entity wherever a method emits", () => {
    const wrong: string[] = [];

    for (const block of BLOCK_MANIFESTS) {
      const types = block.events.types;

      for (const [key, surface] of entriesOf(block)) {
        const emits = Object.values(surface.emits ?? {}).some(Boolean);

        if (emits && !types.some((type) => type.startsWith(`${key}.`))) {
          wrong.push(`${block.name}.${key}`);
        }
      }
    }

    expect(wrong).toStrictEqual([]);
  });

  it("lists every mutating method without an event", () => {
    const declared = BLOCK_MANIFESTS.flatMap((block) =>
      entriesOf(block).flatMap(([key, surface]) =>
        ENTITY_METHODS.filter(
          (method) => surface.emits?.[method] === false,
        ).map((method) => `${block.name}.${key}.${method}`),
      ),
    );

    expect(declared.toSorted()).toStrictEqual([...EMIT_GAPS].toSorted());
  });
});
