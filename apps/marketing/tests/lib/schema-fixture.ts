import {
  encodePreset,
  namedPreset,
  type Preset,
  type PresetName,
} from "better-supabase/preset";

import { previewFiles } from "../../lib/preview-provider";
import { parseSchema, type SchemaData, tenantColumnOf } from "../../lib/schema";
import { schemaData } from "../../lib/schema-meta";

/** A preset with its code and the schema the canvas draws for it. */
export interface PresetSchema {
  readonly preset: Preset;
  readonly code: string;
  readonly data: SchemaData;
}

/** The preset, its code and the schema `/create/schema` returns for it. */
export function presetSchema(
  name: PresetName,
  overrides: Partial<Preset> = {},
): PresetSchema {
  const preset = { ...namedPreset(name), ...overrides };
  const code = encodePreset(preset);

  return {
    preset,
    code,
    data: schemaData(
      parseSchema(previewFiles(code), {
        tenantColumn: tenantColumnOf(preset),
      }),
      preset.tenantName,
    ),
  };
}
