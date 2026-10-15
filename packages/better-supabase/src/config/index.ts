export { CONFIG_DEFAULTS } from "./defaults.ts";
export { GEN_TASKS, INTEGRATION_NAMES, SKILLS_AGENTS } from "./names.ts";
export { resolveJsonSchema } from "./json.ts";
export { CONFIG_SCHEMA_URL, defineConfig, resolveConfig } from "./resolve.ts";
export type {
  ActorConfig,
  Casing,
  ClaimsConfig,
  CodecsConfig,
  GeneratedFile,
  Generator,
  GeneratorColumn,
  GeneratorInput,
  GeneratorModel,
  GeneratorTable,
  JsonSchemaSource,
  JsonTypeConfig,
  PluginFlagsConfig,
  RelationsConfig,
  SoftDeleteConfig,
  SourceConfig,
  TableConfig,
  TenantConfig,
  TimestampsConfig,
} from "./types/codegen.ts";
export type {
  BucketConfig,
  RealtimeConfig,
  ResolvedSqlConfig,
  SeedConfig,
  SqlConfig,
  SqlWorkflow,
  TopicTriggerConfig,
  VectorDistance,
  VectorSearchConfig,
} from "./types/database.ts";
export type { SubjectConfig, SubjectsConfig } from "./types/subjects.ts";
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
  OpenApiConfig,
  ScaffoldApiConfig,
  ScaffoldConfig,
  SkillsAgent,
  SkillsConfig,
} from "./types/tooling.ts";
export type {
  BetterSupabaseConfig,
  EnvironmentConfig,
  ResolvedConfig,
} from "./types/config.ts";
export type {
  ColumnPrivilege,
  ExposeConfig,
  ExposePrivilege,
  ExposeRole,
  Privilege,
  ResolvedExpose,
} from "./expose.ts";
export type {
  AuthorizationFunctions,
  AuthorizationMembership,
  AuthorizationOperation,
  AuthorizationPermission,
  AuthorizationProvider,
  AuthorizationRequirement,
  AuthorizationRoleSource,
  AuthorizationScope,
  AuthorizationTokenHook,
} from "./authorization.ts";
export { providerApiProblem } from "./authorization.ts";
export type {
  AccessBlockConfig,
  ActiveTenantSource,
  DisabledRow,
  BlockMode,
  BlockConfig,
  BlockScope,
  BlocksConfig,
  SqlNaming,
} from "./blocks.ts";
export { DEFAULT_ACTIVE_TENANT } from "./blocks.ts";
export type * from "./snapshot.ts";
export {
  type ClaimPaths,
  claimPaths,
  DEFAULT_CLAIMS,
  tenantClaimPaths,
} from "../core/claims.ts";
export {
  buildJsonSchema,
  jsonSchema,
  type JsonSchemaGeneratorOptions,
  type JsonSchemaTarget,
} from "../generators/json-schema.ts";
export {
  standardSchema,
  type StandardSchemaGeneratorOptions,
} from "../generators/standard-schema.ts";
export {
  valibot,
  type ValibotGeneratorOptions,
} from "../generators/valibot.ts";
export {
  zod,
  type ZodFlavor,
  type ZodGeneratorOptions,
} from "../generators/zod.ts";
