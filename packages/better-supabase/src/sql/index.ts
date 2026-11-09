export {
  customContracts,
  moduleBody,
  moduleTopics,
  renderBlocks,
} from "./render.ts";

export {
  LEGACY_OPTION,
  legacyOptionTables,
  legacyOptionTarget,
} from "./legacy-options.ts";

export { moduleContext, redundantNulls } from "./module-context.ts";

export { isBlockSqlIdType, moduleIdType, MODULE_ID_TYPES } from "./context.ts";

export { moduleDeprecations, upgradePlan } from "./upgrade.ts";

export {
  appColumnsOf,
  buildModel,
  conflicts,
  duplicatePolicies,
  ownerOf,
  parseDeclared,
  setParseStore,
  type Declaration,
  type ParseStore,
  type SchemaModel,
} from "./pipeline/model.ts";

export {
  moduleRenderStats,
  setModuleRenderStore,
  type ModuleRenderEntry,
  type ModuleRenderStore,
} from "./pipeline/module-cache.ts";

export { renderKey } from "./pipeline/render-key.ts";

export { splitStatements, type SqlStatement } from "./pipeline/split.ts";

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

export { moduleSource, resolveBlocks, SQL_MODULES } from "./registry.ts";

export { seedDefaultsFunctions } from "./seed-functions.ts";

export type { SeedDefaultsFunction } from "./seed-functions.ts";

export {
  blockTables,
  type BlockTable,
  type BlockTables,
} from "./block-tables.ts";

export { instanceFunctions } from "./instance-functions.ts";

export { DEFAULT_ROLES } from "./modules/permissions-model.ts";

export {
  APP_TABLES_MARKER,
  APP_TABLES_MODULE,
  appTablesFiles,
} from "./modules/app-tables.ts";

export { PRELUDE_FUNCTIONS, PRELUDE_MODULE } from "./pipeline/prelude.ts";

export { UNSCOPED_MODULE } from "./pipeline/unscoped.ts";

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
  OwnView,
} from "./module-types.ts";

export type { BlockSqlExtension, BlockSqlPermissionKey } from "./introspect.ts";

export type { BlockSqlIdType } from "./context.ts";

export type { BlockSqlTopic } from "./render.ts";

export {
  adoptedColumnProblems,
  type AdoptedTable,
  adoptedTables,
  type AdoptedView,
  adoptedViews,
  moduleWritesText,
} from "./adopted-columns.ts";

export {
  clearMemo,
  memoStats,
  memoized,
  setMemoBackend,
} from "./result-memo.ts";

export type { MemoBackend } from "./result-memo.ts";

export { auditRegistrations } from "./audit-registrations.ts";

export { excludedColumns, resolveExposeColumns } from "./expose-columns.ts";

export { type DeclaredForeignKey, sameTenantLayout } from "./foreign-keys.ts";

export { type OwnedColumn, ownedColumns } from "./owned-columns.ts";

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

export { blockReadRoles } from "./read-roles.ts";

export type { ReadRolesModule } from "./read-roles.ts";

export {
  type CheckValues,
  checkValues,
  declaredCheckValues,
  type TableCheckValues,
} from "./check-values.ts";

export {
  appValues,
  checkedValueMaps,
  type ValueMap,
  type ValueMaps,
} from "./value-maps.ts";

export { writtenValues } from "./written-values.ts";

export { duplicateObjects, type DuplicateObject } from "./duplicate-objects.ts";

export {
  addedColumnTypes,
  declaredColumnTypes,
  declaredIndexes,
  type OwnIndex,
  declaredTableColumns,
  declaredTables,
  declaredUpdatedAtTriggers,
  declaredViews,
  type DeclaredView,
  rlsTables,
  extensionSchema,
  policyGrants,
  type PolicyGrant,
} from "./schema-scan.ts";

export {
  resolveProviderSql,
  SCOPE_ID_TYPES,
  scopeProblems,
  sameTemplateFunction,
  templateFunctions,
} from "../core/access-sql.ts";

export { AUDIT_CATEGORIES } from "./audit-actions.ts";

export type {
  AuditCategory,
  BlockSqlAction,
  BlockSqlAudit,
  BlockSqlEmit,
} from "./audit-actions.ts";

export { contractSignature } from "./context.ts";

export type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlNames,
  BlockSqlTableSpec,
} from "./context.ts";

export { moduleLayout } from "./layout.ts";

export { migrationOptionUses } from "./migration-options.ts";

export { sharedRolesProblems } from "./shared-roles.ts";

export type { MigrationOptionUse } from "./migration-options.ts";

export { compileReadSet, compileReadSets } from "./read-sets.ts";

export type { CompiledReadSet } from "./read-sets.ts";

export { hasColumnAccess } from "../config/app-access.ts";

export { scopePolicyName } from "./modules/app-table-enrich.ts";

export { notNullCheckName } from "./shared.ts";

export { TENANT_SCOPE_NAMES, TENANT_SCOPE_POLICY } from "./tenant-scope.ts";

export {
  appTablePolicyNotes,
  declaredPolicies,
  widenedCommands,
} from "./policy-cover.ts";

export { bsbPolicyName } from "./policy-names.ts";

export {
  catalogPolicy,
  maskSql,
  policy,
  readGrants,
  readPolicies,
  readPolicy,
  renderPolicy,
} from "./policy.ts";

export type {
  Grant,
  Policy,
  PolicyCommand,
  PolicyInput,
  ReadPolicy,
  RenderPolicyOptions,
} from "./policy.ts";

export {
  disallowedPolicyCalls,
  isRule,
  POLICY_FUNCTIONS,
  policyFunctionsSql,
  readRulePolicies,
  renderRule,
  renderRulePolicy,
  rulePolicy,
} from "./policy-rule.ts";

export type {
  PolicyFunctionsOptions,
  ReadRulePolicy,
  Rule,
  RuleOperator,
  RulePolicy,
  RulePolicyInput,
  RuleValue,
} from "./policy-rule.ts";

export {
  commentOnTableSql,
  formatBsbComment,
  parseBsbComment,
  setBsbTag,
} from "./bsb-tags.ts";

export type { BsbComment, BsbTag } from "./bsb-tags.ts";

export {
  createsTable,
  isTableFeature,
  setFeatureStatement,
  setTableFeature,
  TABLE_FEATURES,
  tableFeatures,
  tableTagComments,
} from "./table-features.ts";

export type { TableFeature } from "./table-features.ts";

export { declareRead, readArgSource, readArgSqlType } from "./reads.ts";

export type {
  BlockSqlRead,
  BlockSqlReadArg,
  BlockSqlReadArgType,
} from "./reads.ts";

export {
  type AutoEmbeddingConfig,
  renderAutoEmbedding,
} from "./auto-embeddings.ts";
