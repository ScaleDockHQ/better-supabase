export { PRESET_CATALOG } from "./catalog.generated.ts";

export type {
  PresetCatalog,
  PresetCatalogBlock,
  PresetCatalogManifest,
  PresetGlueItem,
} from "./catalog-types.ts";

export {
  conventionConfig,
  expandPreset,
  presetConfig,
  presetOf,
} from "./config.ts";

export type { ExpandedConfig } from "./config.ts";

export {
  APP_NAME_MAX,
  appIdentifierError,
  appNameLengthError,
  appReservedColumns,
} from "../config/app-tables.ts";

export { appDefaultError, isAppDefault } from "../config/app-defaults.ts";

export {
  APP_COLUMN_FORMATS,
  type AppColumnFormat,
} from "../config/types/app-tables.ts";

export {
  decodeDesign,
  DESIGN_FILE,
  DESIGN_FORMAT,
  DesignParseError,
  designSchema,
  DesignTooLongError,
  designFileSource,
  designFormat,
  CREATE_URL,
  createQuery,
  createUrl,
  presetArgumentOf,
  presetKey,
  designConfig,
  designOf,
  encodeDesign,
  isDesignCode,
  MAX_DESIGN_CODE_LENGTH,
  parseDesign,
  presetAndDesignOf,
  presetApplyCommand,
  presetConfigSource,
  presetInstallCommand,
  readDesignFile,
  safeDesignFileSource,
  safeParseDesign,
} from "./design.ts";

export type {
  CreateDesign,
  DesignErrorCode,
  DesignFile,
  DesignParseIssue,
  DesignParseResult,
} from "./design.ts";

export { diffAppTables, diffDesigns } from "./design-diff.ts";

export type {
  DesignChange,
  DesignChangeKind,
  DiffOptions,
} from "./design-diff.ts";

export type { ConfigConventions, PresetInput } from "./config.ts";

export {
  DEFAULT_CONVENTIONS,
  CONVENTION_FIELDS,
  integrationsForFramework,
  PRESET_FRAMEWORKS,
  PRESET_TENANT_NAMES,
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
  PresetSubjectSettings,
  PresetValueInfo,
} from "./fields.ts";

export {
  DEFAULT_PRESET_NAME,
  defaultPreset,
  isPresetName,
  namedPreset,
  PRESET_GROUPS,
  PRESET_NAMES,
  PRESETS,
} from "./presets.ts";

export type { NamedPreset, PresetGroup, PresetName } from "./presets.ts";

export {
  glueCommand,
  presetBlocksSource,
  presetGlue,
  PROVIDER_COMMENT,
} from "./render.ts";

export {
  blockEntities,
  blockRequires,
  canAddInstance,
  entityName,
  installedBlocks,
  instanceBlock,
  instanceNameProblem,
  instancesOf,
  presetInstances,
  SINGLE_INSTANCE_BLOCKS,
  withEntityName,
  withInstance,
  withoutInstance,
} from "./instances.ts";

export type {
  BlockEntity,
  BlockInstance,
  PresetInstance,
} from "./instances.ts";

export { INSTANCE_NAME, instancePrefix } from "../config/instances.ts";

export { presetFromSpec, presetOfSpec, presetSpec } from "./spec.ts";

export type { PresetSpec } from "./spec.ts";

export { listNames, presetBlockConflict, resolvePreset } from "./resolve.ts";

export type {
  PresetConflict,
  PresetIntegration,
  ResolvedPreset,
  ResolvedPresetBlock,
} from "./resolve.ts";
