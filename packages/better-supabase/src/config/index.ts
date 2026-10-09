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
  ExposeConfig,
  ExposeRole,
  GeneratedFile,
  Generator,
  GeneratorColumn,
  GeneratorInput,
  GeneratorModel,
  GeneratorTable,
  JsonSchemaSource,
  JsonTypeConfig,
  OpenApiConfig,
  PluginFlagsConfig,
  ColumnPrivilege,
  ExposePrivilege,
  Privilege,
  RealtimeConfig,
  RelationsConfig,
  ResolvedConfig,
  ResolvedExpose,
  SeedConfig,
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
} from "../generators/json-schema.ts";
export {
  valibot,
  type ValibotGeneratorOptions,
} from "../generators/valibot.ts";
export { zod, type ZodGeneratorOptions } from "../generators/zod.ts";
