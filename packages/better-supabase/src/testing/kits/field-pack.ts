import type { FieldPack } from "../../blocks/custom-fields/pack.ts";
import type { ConformanceReport } from "../conformance.ts";

import {
  FIELD_PACK_KEY_PATTERN,
  defineFieldPack,
} from "../../blocks/custom-fields/pack.ts";
import { CUSTOM_FIELD_TYPES } from "../../core/contracts/field-formats.ts";
import { conform, expect } from "../conformance.ts";

export interface TestFieldPackOptions {
  /**
   * The subject types the app registers. When set, the kit checks that the pack
   * names only those, which `install_field_pack` enforces in the database.
   */
  readonly subjects?: readonly string[];
}

/**
 * Runs the `FieldPack` contract: API version 1, a lower case key and a whole
 * version, at least one field, valid and unique field keys per subject type,
 * known field types, a pack that survives JSON (the database receives it as
 * `jsonb`), and subject types the app registers.
 */
export function testFieldPack(
  pack: FieldPack,
  options: TestFieldPackOptions = {},
): Promise<ConformanceReport> {
  const entries = Object.entries(pack.subjects);

  return conform(`FieldPack "${pack.key}"`, [
    [
      "targets field pack API v1",
      () => {
        const version: unknown = pack.apiVersion;

        expect(version === 1, `apiVersion is ${String(version)}`);
      },
    ],
    [
      "has a lower case key and a whole version of 1 or more",
      () => {
        expect(
          FIELD_PACK_KEY_PATTERN.test(pack.key),
          `key "${pack.key}" must be lower case`,
        );
        expect(
          Number.isInteger(pack.version) && pack.version >= 1,
          `version is ${String(pack.version)}`,
        );
      },
    ],
    [
      "adds fields to at least one subject type",
      () => {
        expect(
          entries.some(([, fields]) => fields.length > 0),
          "no subject type has a field",
        );
      },
    ],
    [
      "uses valid, unique field keys and known types",
      () => {
        for (const [subject, fields] of entries) {
          const keys = new Set<string>();

          for (const field of fields) {
            expect(
              FIELD_PACK_KEY_PATTERN.test(field.key),
              `${subject}.${field.key}: the key must be lower case`,
            );
            expect(
              field.label.trim() !== "",
              `${subject}.${field.key}: the label is empty`,
            );
            expect(
              CUSTOM_FIELD_TYPES.includes(field.type),
              `${subject}.${field.key}: type "${field.type}" is unknown`,
            );
            expect(
              !keys.has(field.key),
              `${subject}.${field.key} is listed twice`,
            );
            keys.add(field.key);
          }
        }
      },
    ],
    [
      "passes defineFieldPack",
      () => {
        defineFieldPack(pack);
      },
    ],
    [
      "survives a JSON round trip",
      () => {
        expect(
          JSON.stringify(JSON.parse(JSON.stringify(pack))) ===
            JSON.stringify(pack),
          "the pack holds a value JSON can't carry, such as undefined or a function",
        );
      },
    ],
    [
      "names only registered subject types",
      () => {
        const registered = options.subjects;

        if (registered === undefined) {
          return;
        }

        for (const [subject] of entries) {
          expect(
            registered.includes(subject),
            `"${subject}" is not a registered subject type`,
          );
        }
      },
    ],
  ]);
}
