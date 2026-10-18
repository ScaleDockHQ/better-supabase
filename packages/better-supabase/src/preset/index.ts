export { PRESET_BLOCKS } from "./blocks.ts";

export { PRESET_CATALOG } from "./catalog.generated.ts";

export type {
  PresetCatalog,
  PresetCatalogBlock,
  PresetCatalogManifest,
  PresetGlueItem,
} from "./catalog-types.ts";

export {
  decodePreset,
  encodePreset,
  isPresetCode,
  withPresetField,
} from "./code.ts";

export type { DecodedPreset } from "./code.ts";

export { expandPreset, presetConfig, presetOf } from "./config.ts";

export type { PresetInput } from "./config.ts";

export {
  DEFAULT_CONVENTIONS,
  PRESET_FIELDS,
  PRESET_FRAMEWORKS,
  PRESET_VERSION,
} from "./fields.ts";

export type {
  Preset,
  PresetAccess,
  PresetConventions,
  PresetField,
  PresetFieldKey,
  PresetFramework,
  PresetPlatforms,
  PresetScope,
} from "./fields.ts";

export {
  isPresetName,
  namedPreset,
  PRESET_GROUPS,
  PRESET_NAMES,
  PRESETS,
} from "./presets.ts";

export type { NamedPreset, PresetGroup, PresetName } from "./presets.ts";

export {
  glueCommand,
  presetApplyCommand,
  presetBlocksSource,
  presetGlue,
  presetConfigSource,
  presetInstallCommand,
} from "./render.ts";

export { listNames, presetBlockConflict, resolvePreset } from "./resolve.ts";

export type {
  PresetConflict,
  PresetIntegration,
  ResolvedPreset,
  ResolvedPresetBlock,
} from "./resolve.ts";
