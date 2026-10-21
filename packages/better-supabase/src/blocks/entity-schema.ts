import type {
  FieldSpec,
  TableSchema,
  TableSchemaSpec,
} from "../core/table-schema.ts";

import { tableSchema } from "../core/table-schema.ts";

type Nothing = Record<never, never>;

type OptionalFlag<T, K extends keyof T> =
  Nothing extends Pick<T, K>
    ? { readonly optional: true }
    : { readonly optional?: false };

type ArrayFlag<V> = unknown extends V
  ? Nothing
  : [Exclude<V, undefined>] extends [readonly unknown[]]
    ? { readonly array: true }
    : { readonly array?: false };

/**
 * The fields of `entitySchema<T>`: one per key of `T`, marked `optional` when
 * the key is and `array` when its value is a list, so the schema can't drift
 * from the type.
 */
export type EntityFieldSpecs<T> = {
  readonly [K in keyof T & string]-?: FieldSpec &
    OptionalFlag<T, K> &
    ArrayFlag<T[K]>;
};

export interface EntitySchemaSpec<T> {
  readonly title?: string;
  readonly description?: string;
  readonly fields: EntityFieldSpecs<T>;
}

/**
 * A Standard Schema that also converts to JSON Schema (Standard JSON Schema),
 * for one of a block's inputs, with the spec it was built from.
 */
export interface EntitySchema<T> extends TableSchema<T> {
  readonly spec: TableSchemaSpec;
}

/** What a block's client takes for one entity. */
export interface EntitySchemas {
  /** Creating one (`WorkItemInput`). */
  readonly input?: EntitySchema<unknown>;
  /** Updating one (`WorkItemChange`). */
  readonly change?: EntitySchema<unknown>;
  /** Listing them (`WorkItemListOptions`). */
  readonly listFilter?: EntitySchema<unknown>;
}

/** The keys of `EntitySchemas`. */
export const ENTITY_SCHEMA_KINDS: readonly (keyof EntitySchemas)[] = [
  "input",
  "change",
  "listFilter",
];

/** A block's input schemas, by entity key (its default singular noun). */
export type BlockSchemas = Readonly<Record<string, EntitySchemas>>;

/**
 * The Standard Schema for one of a block's input types, without a validation
 * library: it validates like `tableSchema`, drops unknown keys, and converts to
 * JSON Schema. The spec names every key of `T`.
 */
export function entitySchema<T>(spec: EntitySchemaSpec<T>): EntitySchema<T> {
  return { ...tableSchema<T>(spec), spec };
}
