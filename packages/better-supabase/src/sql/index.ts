export {
  customContracts,
  moduleBody,
  moduleTopics,
  renderBlocks,
} from "./render.ts";

export { isBlockSqlIdType, moduleIdType, MODULE_ID_TYPES } from "./context.ts";

export { moduleDeprecations, upgradePlan } from "./upgrade.ts";

export {
  BLOCK_RENAMES,
  currentBlockName,
  formerBlockName,
  renamedBlock,
} from "./block-renames.ts";

export { entityRenamePlan } from "./entity-upgrade.ts";

export { moduleDataDir, moduleFilePaths } from "./paths.ts";

export {
  blockFileState,
  isModuleDataFile,
  moduleFileVersion,
  sameBlockFile,
} from "./markers.ts";

export {
  modulePermissionKeys,
  moduleEventTriggers,
  moduleHidingColumns,
  moduleSchemaExtensions,
} from "./introspect.ts";

export { blockSqlVersion } from "./module-types.ts";

export { resolveBlocks, SQL_MODULES } from "./registry.ts";

export { instanceFunctions } from "./instance-functions.ts";

export { DEFAULT_ROLES } from "./modules/permissions-model.ts";

export {
  APP_TABLES_MARKER,
  APP_TABLES_MODULE,
  appTablesFiles,
} from "./modules/app-tables.ts";

export { resolveBlock } from "../config/blocks.ts";

export { appTableEventTypes } from "../config/app-tables.ts";

export { BLOCK_OPTION_SCHEMAS } from "../blocks/options-registry.ts";

export type { BlockOptionsRegistry } from "../blocks/options-registry.ts";

export type { InstalledBlock, BlockSqlUpgradePlan } from "./upgrade.ts";

export type { EntityRenamePlan, EntityRenameStep } from "./entity-upgrade.ts";

export type {
  BlockSqlDeprecation,
  BlockSqlAccessProvider,
  BlockSqlFile,
  BlockSqlLayout,
  BlockSqlEntitlementsProvider,
  BlockSqlTestFile,
  BlockSqlUpgrade,
  BlockSql,
} from "./module-types.ts";

export type { BlockSqlExtension, BlockSqlPermissionKey } from "./introspect.ts";

export type { BlockSqlIdType } from "./context.ts";

export type { BlockSqlTopic } from "./render.ts";

export {
  adoptedColumnProblems,
  type AdoptedTable,
  adoptedTables,
} from "./adopted-columns.ts";

export { auditRegistrations } from "./audit-registrations.ts";

export { excludedColumns, resolveExposeColumns } from "./expose-columns.ts";

export { type DeclaredForeignKey, sameTenantLayout } from "./foreign-keys.ts";

export {
  type DataExportPlan,
  dataExportPlan,
  SECRET_COLUMNS,
} from "./modules/data-lifecycle-secrets.ts";

export { sameTenantColumn, sameTenantTrigger } from "./modules/tenant-same.ts";

export { expiredFlagsQuery } from "./flag-lifecycle.ts";

export { tenantsQuery, type TenantQuery } from "./tenant-query.ts";

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
  BlockSqlAction,
  BlockSqlAudit,
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEmit,
  BlockSqlNames,
  BlockSqlTableSpec,
} from "./context.ts";

export { moduleLayout } from "./layout.ts";

export { migrationOptionUses } from "./migration-options.ts";

export { sharedRolesProblems } from "./shared-roles.ts";

export type { MigrationOptionUse } from "./migration-options.ts";

export { compileReadSet, compileReadSets } from "./read-sets.ts";

export type { CompiledReadSet } from "./read-sets.ts";
