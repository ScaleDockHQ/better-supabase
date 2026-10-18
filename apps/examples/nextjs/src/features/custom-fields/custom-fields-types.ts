import * as v from "valibot";

/** The records the editor defines fields for, by subject type. */
export const FIELD_ENTITIES = ["customer", "work_item"] as const;

export type FieldEntity = (typeof FIELD_ENTITIES)[number];

export const FieldEntitySchema = v.picklist(FIELD_ENTITIES);

/** The value types the custom-fields module accepts. */
export const FIELD_TYPES = [
  "text",
  "number",
  "date",
  "bool",
  "option",
  "json",
] as const;

export type FieldType = (typeof FIELD_TYPES)[number];

export const FieldTypeSchema = v.picklist(FIELD_TYPES);

export interface FieldRow {
  readonly id: string;
  readonly key: string;
  readonly label: string;
  readonly type: string;
  readonly sensitive: boolean;
}
