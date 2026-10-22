import type { SchemaData } from "../../src/create/index.ts";
import type { Preset, PresetName, PresetSpec } from "../../src/preset/index.ts";

import {
  previewFiles,
  parseSchema,
  tenantColumnOf,
  schemaData,
} from "../../src/create/index.ts";
import { presetSpec, namedPreset } from "../../src/preset/index.ts";

/** A preset with its spec and the schema the canvas draws for it. */
export interface PresetSchema {
  readonly preset: Preset;
  readonly spec: PresetName | PresetSpec;
  readonly data: SchemaData;
}

/** The preset, its spec and the schema `/create/schema` returns for it. */
export function presetSchema(
  name: PresetName,
  overrides: Partial<Preset> = {},
): PresetSchema {
  const preset = { ...namedPreset(name), ...overrides };
  const spec = presetSpec(preset);

  return {
    preset,
    spec,
    data: schemaData(
      parseSchema(previewFiles(spec), { tenantColumn: tenantColumnOf(preset) }),
      preset.tenantName,
    ),
  };
}
