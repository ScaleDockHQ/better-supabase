import { describe, expect, it } from "vitest";

import { BLOCK_MANIFESTS } from "../../src/blocks/registry.ts";
import {
  EXPECTED_VERSION_GAPS,
  IDEMPOTENCY_GAPS,
} from "./write-safety-gaps.ts";

/**
 * Write safety follows the entity's declared surface (ADR 0809): an `editable`
 * entity takes `expectedVersion` on update, and an entity with a `create` takes
 * an `idempotencyKey`. The gap lists hold what is still missing.
 */

const entities = BLOCK_MANIFESTS.flatMap((block) =>
  Object.entries(block.entities ?? {}).map(
    ([key, surface]) => ({ id: `${block.name}.${key}`, surface }) as const,
  ),
);

describe("write safety of the entity surface", () => {
  it("lists every editable entity without expectedVersion, and only those", () => {
    const missing = entities
      .filter(
        ({ surface }) =>
          surface.mutability === "editable" && surface.expectedVersion !== true,
      )
      .map(({ id }) => id)
      .toSorted();

    expect(missing).toStrictEqual([...EXPECTED_VERSION_GAPS].toSorted());
  });

  it("lists every entity with a create and no idempotencyKey, and only those", () => {
    const missing = entities
      .filter(
        ({ surface }) =>
          surface.emits?.create !== undefined &&
          !(surface.idempotent ?? []).includes("create"),
      )
      .map(({ id }) => id)
      .toSorted();

    expect(missing).toStrictEqual([...IDEMPOTENCY_GAPS].toSorted());
  });

  it("declares expectedVersion only on editable entities", () => {
    const wrong = entities
      .filter(
        ({ surface }) =>
          surface.expectedVersion === true && surface.mutability !== "editable",
      )
      .map(({ id }) => id);

    expect(wrong).toStrictEqual([]);
  });
});
