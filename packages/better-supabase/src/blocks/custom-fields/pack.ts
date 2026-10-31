import type { CustomFieldType } from "../../core/contracts/field-formats.ts";

import { CUSTOM_FIELD_TYPES } from "../../core/contracts/field-formats.ts";

/**
 * The pattern a pack key and a field key follow; `install_field_pack` checks
 * the same one.
 */
export const FIELD_PACK_KEY_PATTERN: RegExp = /^[a-z][a-z0-9_.-]{0,62}$/u;

/** One field a pack adds to a subject type. */
export interface FieldPackField {
  /** Unique per subject type; the pack matches existing definitions by it. */
  readonly key: string;
  readonly label: string;
  readonly type: CustomFieldType;
  readonly required?: boolean;
  readonly sensitive?: boolean;
  /** The permission key that gates reads of the field's values. */
  readonly permission?: string;
}

/**
 * A versioned set of field definitions for registered subject types. Packs
 * carry the fields of an industry or a team, so the library ships none. Raise
 * `version` when the fields change; installing the same version again changes
 * nothing.
 */
export interface FieldPack {
  readonly apiVersion: 1;
  /** Names the pack in `field_definitions.pack`. */
  readonly key: string;
  readonly version: number;
  /** Subject type to the fields it gets. */
  readonly subjects: Readonly<Record<string, readonly FieldPackField[]>>;
}

const fail = (message: string): never => {
  throw new TypeError(`defineFieldPack: ${message}`);
};

/**
 * Checks a pack and returns it. Throws on a bad key, version, type or a
 * duplicate field; the database applies the same rules in `install_field_pack`
 * and also checks that every subject type is registered.
 */
export function defineFieldPack<const T extends FieldPack>(pack: T): T {
  // oxlint-disable-next-line typescript/no-unnecessary-condition -- packs written in JavaScript skip the type check.
  if (pack.apiVersion !== 1) {
    fail(`apiVersion must be 1, got ${String(pack.apiVersion)}`);
  }

  if (!FIELD_PACK_KEY_PATTERN.test(pack.key)) {
    fail(`key "${pack.key}" must be lower case, such as "crm-basics"`);
  }

  if (!Number.isInteger(pack.version) || pack.version < 1) {
    fail(`version must be a whole number of 1 or more`);
  }

  for (const [subject, fields] of Object.entries(pack.subjects)) {
    const seen = new Set<string>();

    for (const field of fields) {
      if (!FIELD_PACK_KEY_PATTERN.test(field.key)) {
        fail(`${subject}.${field.key}: the key must be lower case`);
      }

      if (field.label.trim() === "") {
        fail(`${subject}.${field.key}: the label is empty`);
      }

      if (!CUSTOM_FIELD_TYPES.includes(field.type)) {
        fail(
          `${subject}.${field.key}: type "${field.type}" is not one of ${CUSTOM_FIELD_TYPES.join(", ")}`,
        );
      }

      if (seen.has(field.key)) {
        fail(`${subject}.${field.key} is listed twice`);
      }

      seen.add(field.key);
    }
  }

  return pack;
}
