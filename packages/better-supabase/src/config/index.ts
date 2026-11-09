export { CONFIG_DEFAULTS } from "./defaults.ts";

export {
  GEN_TASKS,
  INTEGRATION_INFO,
  INTEGRATION_NAMES,
  type IntegrationInfo,
  SKILLS_AGENTS,
} from "./names.ts";

export { resolveJsonSchema } from "./json.ts";

export {
  CONFIG_SCHEMA_URL,
  defineConfig,
  generatorProblem,
  resolveConfig,
} from "./resolve.ts";

export type {
  BlockTableReference,
  BucketName,
  ConfigReferences,
  RoleNames,
} from "./references.ts";

export type { ExpandedConfig } from "../preset/config.ts";

export type {
  Casing,
  ClaimsConfig,
  CodecsConfig,
  GeneratedFile,
  Generator,
  GeneratorBlock,
  GeneratorBlockEntity,
  GeneratorColumn,
  GeneratorEntitySchemas,
  GeneratorField,
  GeneratorFunction,
  GeneratorFunctionArg,
  GeneratorCapability,
  GeneratorConfigView,
  GeneratorImports,
  GeneratorInput,
  GeneratorInputSchema,
  GeneratorJsonSchema,
  GeneratorModel,
  GeneratorModule,
  GeneratorNoun,
  GeneratorTable,
  JsonSchemaSource,
  JsonTypeConfig,
  RelationsConfig,
  SourceConfig,
  TableConfig,
} from "./types/codegen.ts";

export type {
  BucketConfig,
  RealtimeConfig,
  ResolvedSqlConfig,
  SeedConfig,
  SeedDefaultsConfig,
  SeedSampleConfig,
  SeedSampleSize,
  ResolvedSeedConfig,
  SqlBlockDefaults,
  SqlConfig,
  SqlWorkflow,
  TopicTriggerConfig,
  TopicTriggerLookupConfig,
  TopicTriggerPayloadValueConfig,
  TopicTriggerTopicConfig,
  TopicTriggerValueConfig,
  VectorDistance,
  VectorSearchConfig,
} from "./types/database.ts";

export type {
  SubjectConfig,
  SubjectPermission,
  SubjectSearch,
  SubjectsConfig,
  SubjectTeam,
} from "./types/subjects.ts";

export {
  FIELD_FORMATS,
  type FieldFormat,
  type FieldFormatInput,
} from "../core/contracts/field-formats.ts";

export {
  APP_COLUMN_ACCESS,
  APP_COLUMN_FORMATS,
  APP_COLUMN_TYPES,
  APP_ON_DELETE_ACTIONS,
  APP_ROLLUP_AGGREGATES,
  APP_TABLE_EVENT_KINDS,
  type AppColumnAccess,
  type AppColumnConfig,
  type AppColumnFormat,
  type AppColumnType,
  type AppOnDeleteAction,
  type AppLookupConfig,
  type AppReference,
  type AppReferenceTarget,
  type AppRollupAggregate,
  type AppRollupConfig,
  type AppTableConfig,
  type AppTableEventKind,
  type AppTableEmbedding,
  type AppTableEvents,
  type AppTableVersions,
  type AppTableSubject,
  type AppTablesConfig,
} from "./types/app-tables.ts";

export type {
  EntitlementPlansSource,
  EntitlementsConfig,
} from "./types/entitlements.ts";

export type {
  DoctorConfig,
  EnvFileConfig,
  GenConfig,
  GenTask,
  IntegrationName,
  KeysConfig,
  MigrationSafetyConfig,
  PowerSyncGenConfig,
  SkillsAgent,
  SkillsConfig,
} from "./types/tooling.ts";

export type {
  ApiConfig,
  AppTableInput,
  AppTablesInput,
  AuthConfig,
  BetterSupabaseConfig,
  BlockInput,
  BlocksInput,
  DatabaseConfig,
  DataHooksConfig,
  DataHooksFramework,
  DataHooksSelect,
  HooksFramework,
  EnvironmentConfig,
  FlatConfig,
  GenGroupConfig,
  TenantConfig,
  ResolvedConfig,
  ResolvedExtensions,
  SqlInput,
  ToolingConfig,
} from "./types/config.ts";

export type { ResolveInput } from "./resolve.ts";

export {
  CONFIG_GROUPS,
  flattenConfig,
  groupConfig,
  groupEntries,
  RENAMED_BLOCK_KEYS,
  blockEntrySource,
  RENAMED_CONFIG_KEYS,
} from "./groups.ts";

export type {
  ColumnPrivilege,
  ExposeConfig,
  ExposePrivilege,
  ExposeRole,
  Privilege,
  ResolvedExpose,
} from "./expose.ts";

export type {
  AuthorizationFixtureRole,
  AuthorizationFunctions,
  AuthorizationMembership,
  AuthorizationOperation,
  AuthorizationPermission,
  AuthorizationPersona,
  AuthorizationPlatformRoles,
  AuthorizationProvider,
  AuthorizationRequirement,
  AuthorizationRoleSource,
  AuthorizationScope,
  AuthorizationTokenHook,
  AuthorizationVersions,
} from "./authorization.ts";

export {
  PERMISSION_LEVEL_SEPARATOR,
  permissionLevelKey,
  providerApiProblem,
  resolvePersonas,
  splitPermissionLevel,
} from "./authorization.ts";

export type {
  AccessBlockConfig,
  ActiveTenantSource,
  DisabledRow,
  BlockMode,
  BlockConfig,
  AnyBlocksConfig,
  BlockScope,
  BlocksConfig,
  OwnTablePolicies,
  EntitiesConfig,
  EntityConfig,
} from "./blocks.ts";

export {
  blockEntities,
  blockEntityRenames,
  blockEventRenames,
  blockFormerFunctions,
  blockSubjectTypes,
} from "./block-subjects.ts";

export type { BlockEntity } from "./block-subjects.ts";

export { DEFAULT_ACTIVE_TENANT, tenantNameOf } from "./blocks.ts";

export type * from "./snapshot.ts";

export {
  type ClaimPaths,
  claimPaths,
  DEFAULT_CLAIMS,
  tenantClaimPaths,
} from "../core/claims.ts";
