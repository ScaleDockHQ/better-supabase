import type { StandardSchemaV1 } from "@standard-schema/spec";

import { describe, expectTypeOf, it } from "vitest";

import type {
  workItemChangeSchema,
  workItemInputSchema,
  workItemListFilterSchema,
} from "../../src/blocks/work-items/schemas.ts";
import type {
  WorkItemChange,
  WorkItemInput,
  WorkItemListOptions,
} from "../../src/blocks/work-items/work-items.ts";

import { entitySchema } from "../../src/blocks/entity-schema.ts";

interface Note {
  readonly title: string;
  readonly body?: string;
  readonly tags: readonly string[];
}

describe("entitySchema", () => {
  it("outputs the hand-written types", () => {
    expectTypeOf<
      StandardSchemaV1.InferOutput<typeof workItemInputSchema>
    >().toEqualTypeOf<WorkItemInput>();
    expectTypeOf<
      StandardSchemaV1.InferOutput<typeof workItemChangeSchema>
    >().toEqualTypeOf<WorkItemChange>();
    expectTypeOf<
      StandardSchemaV1.InferOutput<typeof workItemListFilterSchema>
    >().toEqualTypeOf<WorkItemListOptions>();
  });

  it("needs every key, with optional and array flags that match the type", () => {
    entitySchema<Note>({
      fields: {
        title: { kind: "string" },
        body: { kind: "string", optional: true },
        tags: { kind: "string", array: true },
      },
    });

    entitySchema<Note>({
      // @ts-expect-error -- `tags` is missing.
      fields: {
        title: { kind: "string" },
        body: { kind: "string", optional: true },
      },
    });

    entitySchema<Note>({
      fields: {
        // @ts-expect-error -- `title` is required.
        title: { kind: "string", optional: true },
        body: { kind: "string", optional: true },
        tags: { kind: "string", array: true },
      },
    });

    entitySchema<Note>({
      fields: {
        title: { kind: "string" },
        // @ts-expect-error -- `body` is optional.
        body: { kind: "string" },
        tags: { kind: "string", array: true },
      },
    });

    entitySchema<Note>({
      fields: {
        title: { kind: "string" },
        body: { kind: "string", optional: true },
        // @ts-expect-error -- `tags` is a list.
        tags: { kind: "string" },
      },
    });

    entitySchema<Note>({
      fields: {
        title: { kind: "string" },
        body: { kind: "string", optional: true },
        tags: { kind: "string", array: true },
        // @ts-expect-error -- `Note` has no `extra`.
        extra: { kind: "string" },
      },
    });
  });
});
