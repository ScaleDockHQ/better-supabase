import type { EntitySchema } from "../entity-schema.ts";
import type { ProductInput } from "./catalog.ts";

import { entitySchema, moneyField } from "../entity-schema.ts";
import { PRODUCT_KINDS } from "./catalog.ts";

/**
 * What `createProduct` and `updateProduct` take, with the bounds the SQL
 * checks.
 */
export const productInputSchema: EntitySchema<ProductInput> =
  entitySchema<ProductInput>({
    title: "ProductInput",
    fields: {
      title: { kind: "string", minLength: 1, maxLength: 500 },
      slug: {
        kind: "string",
        optional: true,
        minLength: 1,
        description: "Lower-case letters, digits and hyphens.",
      },
      description: { kind: "string", optional: true },
      kind: { kind: "enum", values: PRODUCT_KINDS, optional: true },
      price: { ...moneyField, optional: true },
      trackInventory: { kind: "boolean", optional: true },
    },
  });
