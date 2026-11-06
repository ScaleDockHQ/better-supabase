import type { BlockSqlNameMigration } from "./context.ts";
import type { ResolvedNames } from "./resolved-names.ts";

/** One module table's default name before and after 0.47. */
export interface TableRename {
  readonly from: string;
  readonly to: string;
}

const tables = (
  entries: Readonly<Record<string, readonly [string, string]>>,
): Readonly<Record<string, TableRename>> =>
  Object.freeze(
    Object.fromEntries(
      Object.entries(entries).map(([logical, [from, to]]) => [
        logical,
        Object.freeze({ from, to }),
      ]),
    ),
  );

/**
 * Module tables whose default name follows the convention since 0.47 (a table
 * is its entity's plural, or starts with its entity's singular), by module and
 * logical table. `upgrade` renames installed tables; tables the app maps
 * through `blocks.<name>.tables`, and tables of an install that names the
 * entity, keep their names.
 */
export const TABLE_RENAMES: Readonly<
  Record<string, Readonly<Record<string, TableRename>>>
> = Object.freeze({
  activities: tables({ engagements: ["engagements", "activities"] }),
  automations: tables({
    defaults: ["rule_defaults", "automation_defaults"],
    evaluations: ["rule_evaluations", "automation_evaluations"],
    fields: ["rule_fields", "automation_fields"],
    rules: ["rules", "automations"],
    versions: ["rule_versions", "automation_versions"],
  }),
  catalog: tables({
    categories: ["categories", "catalog_categories"],
    priceLists: ["price_lists", "catalog_price_lists"],
    storefronts: ["storefronts", "catalog_storefronts"],
  }),
  collections: tables({ favorites: ["favorites", "collection_favorites"] }),
  compliance: tables({ policies: ["policies", "compliance_policies"] }),
  domains: tables({ hostnames: ["organization_hostnames", "hostnames"] }),
  goals: tables({ targets: ["targets", "goals"] }),
  idempotency: tables({ leases: ["leases", "idempotency_leases"] }),
  inbox: tables({
    deliveries: ["message_deliveries", "inbox_message_deliveries"],
    events: ["conversation_events", "inbox_conversation_events"],
    inbound: ["inbound_events", "inbox_inbound_events"],
    templates: ["message_templates", "inbox_message_templates"],
  }),
  incidents: tables({
    components: ["status_components", "incident_status_components"],
    history: ["status_component_history", "incident_status_component_history"],
    pages: ["status_pages", "incident_status_pages"],
  }),
  leases: tables({ leases: ["lease_agreements", "leases"] }),
  memory: tables({
    messageEmbeddings: ["ai_message_embeddings", "memory_message_embeddings"],
  }),
  orders: tables({
    fulfillmentLines: ["fulfillment_lines", "order_fulfillment_lines"],
    fulfillments: ["fulfillments", "order_fulfillments"],
    kitchenRoutes: ["kitchen_routes", "order_kitchen_routes"],
    kitchenStations: ["kitchen_stations", "order_kitchen_stations"],
    shippingRates: ["shipping_rates", "order_shipping_rates"],
  }),
  sso: tables({
    domains: ["organization_domains", "sso_domains"],
    providers: ["organization_sso_providers", "sso_providers"],
  }),
  tasks: tables({
    assignees: ["work_item_assignees", "task_assignees"],
    checklist: ["work_item_checklist_items", "task_checklist_items"],
    items: ["work_items", "tasks"],
  }),
  timeline: tables({ activity: ["activity_entries", "timeline_entries"] }),
});

/**
 * `module`'s 0.47 table renames (`TABLE_RENAMES`) as `NAMES.migrations`
 * entries, run on installs below version `from + 1`.
 */
export function tableMoves(
  module: string,
  from: number,
): readonly BlockSqlNameMigration[] {
  return Object.entries(TABLE_RENAMES[module] ?? {}).map(([table, rename]) => ({
    from,
    description: `The ${rename.from} table is ${rename.to} (ADR 0130).`,
    table,
    was: rename.from,
    objects: true,
  }));
}

const taken = new Set(
  Object.values(TABLE_RENAMES).flatMap((renames) =>
    Object.values(renames).map((rename) => rename.to),
  ),
);

/**
 * Whether `module` moves a table off a name another module's move takes, as
 * idempotency frees `leases` for the leases block. Its upgrade runs first.
 */
export const freesTableName = (module: string): boolean =>
  Object.values(TABLE_RENAMES[module] ?? {}).some((rename) =>
    taken.has(rename.from),
  );

/** Whether 0.47 renamed `module`'s logical `table`. */
const movedTable = (module: string, table: string): boolean =>
  Object.hasOwn(TABLE_RENAMES[module] ?? {}, table);

/**
 * The default name of a logical table before the config's renames. A table 0.47
 * renamed after an entity's new singular (`tasks`) starts from its old noun
 * (`work_items`) on an install that names the entity, so the install keeps its
 * table, as it keeps its function names.
 */
export const tableBase = (
  resolved: ResolvedNames,
  logical: string,
  name: string,
): string =>
  movedTable(resolved.module, logical)
    ? resolved.functionNouns.rename(name)
    : name;

/**
 * The renamer for a logical column's default name. A column a migration renamed
 * after an entity's new singular (`task_id`) starts from the old noun
 * (`work_item_id`) on an install that names the entity, as its table does.
 */
export const columnRenamer =
  (
    resolved: ResolvedNames,
    migrations: readonly BlockSqlNameMigration[] | undefined,
    table: string,
    logical: string,
  ): ((name: string) => string) =>
  (name) =>
    resolved.naming.rename(
      migrations?.some(
        (move) => move.table === table && move.columns?.[logical] !== undefined,
      )
        ? resolved.functionNouns.rename(name)
        : name,
    );
