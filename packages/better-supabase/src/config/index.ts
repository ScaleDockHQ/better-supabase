export {
  CONFIG_SCHEMA_URL,
  defineConfig,
  resolveConfig,
  resolveJsonSchema,
} from "./config.ts";
export type {
  ActorConfig,
  BetterSupabaseConfig,
  BucketConfig,
  Casing,
  ClaimsConfig,
  CodecsConfig,
  DoctorConfig,
  EntitlementPlansSource,
  EntitlementsConfig,
  EnvFileConfig,
  EnvironmentConfig,
  ExposeConfig,
  ExposeRole,
  GenConfig,
  GenTask,
  GeneratedFile,
  Generator,
  GeneratorColumn,
  GeneratorInput,
  GeneratorModel,
  GeneratorTable,
  IntegrationName,
  JsonSchemaSource,
  JsonTypeConfig,
  KeysConfig,
  OpenApiConfig,
  PluginFlagsConfig,
  ColumnPrivilege,
  ExposePrivilege,
  Privilege,
  RealtimeConfig,
  RelationsConfig,
  ResolvedConfig,
  ResolvedExpose,
  ScaffoldApiConfig,
  ScaffoldConfig,
  SeedConfig,
  SkillsAgent,
  SkillsConfig,
  SoftDeleteConfig,
  SourceConfig,
  ResolvedSqlConfig,
  SqlConfig,
  TableConfig,
  TenantConfig,
  TimestampsConfig,
  VectorDistance,
  VectorSearchConfig,
} from "./config.ts";
export type {
  AuthorizationFunctions,
  AuthorizationMembership,
  AuthorizationPermission,
  AuthorizationProvider,
  AuthorizationRequirement,
  AuthorizationRoleSource,
  AuthorizationScope,
  AuthorizationTokenHook,
} from "./authorization.ts";
export { providerApiProblem } from "./authorization.ts";
export type {
  AccessModuleConfig,
  ActiveTenantSource,
  DisabledRow,
  ModuleMode,
  ModuleConfig,
  ModulesConfig,
} from "./modules.ts";
export { DEFAULT_ACTIVE_TENANT } from "./modules.ts";
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
