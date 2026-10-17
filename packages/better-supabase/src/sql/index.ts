export {
  customContracts,
  moduleBody,
  moduleTopics,
  renderModules,
} from "./render.ts";

export { isModuleIdType, moduleIdType, MODULE_ID_TYPES } from "./context.ts";

export { moduleDeprecations, upgradePlan } from "./upgrade.ts";

export { moduleFilePaths } from "./paths.ts";

export { moduleFileVersion, sameModuleFile } from "./markers.ts";

export {
  modulePermissionKeys,
  moduleEventTriggers,
  moduleSchemaExtensions,
} from "./introspect.ts";

export { moduleVersion } from "./module-types.ts";

export { resolveModules, SQL_MODULES } from "./registry.ts";

export { resolveModule } from "../config/blocks.ts";

export { BLOCK_OPTION_SCHEMAS } from "../blocks/options-registry.ts";

export type { BlockOptionsRegistry } from "../blocks/options-registry.ts";

export type { InstalledModule, ModuleUpgradePlan } from "./upgrade.ts";

export type {
  ModuleDeprecation,
  ModuleAccessProvider,
  ModuleFile,
  ModuleLayout,
  ModuleEntitlementsProvider,
  ModuleTestFile,
  ModuleUpgrade,
  SqlModule,
} from "./module-types.ts";

export type { ModuleExtension, ModulePermissionKey } from "./introspect.ts";

export type { ModuleIdType } from "./context.ts";

export type { ModuleTopic } from "./render.ts";

export {
  adoptedColumnProblems,
  type AdoptedTable,
  adoptedTables,
} from "./adopted-columns.ts";

export { auditRegistrations } from "./audit-registrations.ts";

export { expiredFlagsQuery } from "./flag-lifecycle.ts";

export { subjectColumns } from "./subject-registry.ts";

export type { AuditedTable } from "./audit-registrations.ts";

export {
  declaredTables,
  rlsTables,
  extensionSchema,
  policyGrants,
  type PolicyGrant,
} from "./schema-scan.ts";

export {
  resolveProviderSql,
  SCOPE_ID_TYPES,
  scopeProblems,
  templateFunctions,
} from "../core/access-sql.ts";

export { AUDIT_CATEGORIES, contractSignature } from "./context.ts";

export type {
  AuditCategory,
  ModuleAction,
  ModuleAudit,
  ModuleContext,
  ModuleContractFunction,
  ModuleEmit,
  ModuleNames,
  ModuleTableSpec,
} from "./context.ts";

export { moduleLayout } from "./layout.ts";

export { migrationOptionUses } from "./migration-options.ts";

export { sharedRolesProblems } from "./shared-roles.ts";

export type { MigrationOptionUse } from "./migration-options.ts";

export { compileReadSet, compileReadSets } from "./read-sets.ts";

export type { CompiledReadSet } from "./read-sets.ts";
