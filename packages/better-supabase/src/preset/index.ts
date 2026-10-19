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

export {
  conventionConfig,
  expandPreset,
  presetConfig,
  presetOf,
} from "./config.ts";

export { appReservedColumns, isAppDefault } from "../config/app-tables.ts";

export {
  APP_COLUMN_FORMATS,
  type AppColumnFormat,
} from "../config/types/app-tables.ts";

export {
  decodeDesign,
  DESIGN_FORMAT,
  DesignTooLongError,
  designFormat,
  designApplyCommand,
  designConfig,
  designConfigSource,
  designInstallCommand,
  designOf,
  encodeDesign,
  isDesignCode,
  MAX_DESIGN_CODE_LENGTH,
} from "./design.ts";

export type { CreateDesign } from "./design.ts";

export { diffAppTables, diffDesigns } from "./design-diff.ts";

export type {
  DesignChange,
  DesignChangeKind,
  DiffOptions,
} from "./design-diff.ts";

export type { ConfigConventions, PresetInput } from "./config.ts";

export {
  DEFAULT_CONVENTIONS,
  integrationsForFramework,
  PRESET_FIELDS,
  PRESET_FRAMEWORKS,
  PRESET_TENANT_NAMES,
  PRESET_VERSION,
  presetField,
  presetValueLabel,
} from "./fields.ts";

export type {
  Preset,
  PresetAccess,
  PresetConventions,
  PresetField,
  PresetFieldKey,
  PresetFieldValue,
  PresetFramework,
  PresetPlatforms,
  PresetScope,
  PresetValueInfo,
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
  PROVIDER_COMMENT,
} from "./render.ts";

export { listNames, presetBlockConflict, resolvePreset } from "./resolve.ts";

export type {
  PresetConflict,
  PresetIntegration,
  ResolvedPreset,
  ResolvedPresetBlock,
} from "./resolve.ts";
