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
  EntitlementsConfig,
  ExposeConfig,
  GeneratedFile,
  Generator,
  GeneratorInput,
  JsonSchemaSource,
  JsonTypeConfig,
  OpenApiConfig,
  PermdockPathsConfig,
  PluginFlagsConfig,
  Privilege,
  RealtimeConfig,
  ResolvedConfig,
  ResolvedExpose,
  SeedConfig,
  SoftDeleteConfig,
  SourceConfig,
  SqlConfig,
  TableConfig,
  TenantConfig,
  TimestampsConfig,
  VectorDistance,
  VectorSearchConfig,
} from "./config.ts";
export type {
  AccessKitConfig,
  ActiveTenantSource,
  KitMode,
  KitModuleConfig,
  KitsConfig,
} from "./kits.ts";
export { DEFAULT_ACTIVE_TENANT } from "./kits.ts";
export type * from "./snapshot.ts";
export { DEFAULT_CLAIMS, tenantClaimPaths } from "../core/claims.ts";
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
