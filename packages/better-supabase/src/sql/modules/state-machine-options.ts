import type { SubjectsConfig } from "../../config/types/subjects.ts";
import type { EntityNames } from "../../core/entity-naming.ts";
import type { BlockSqlContext } from "../context.ts";

import { tenantColumnOf } from "../subject-registry.ts";

const NAME = /^[a-z][a-z0-9_]*$/;
const ID_TYPE = /^[a-z][a-z0-9_ ]{0,62}$/;

export interface Machine {
  readonly name: string;
  readonly table: string;
  readonly column: string;
  readonly idColumn: string;
  /** The id column's type, so lookups compare on the primary key's own type. */
  readonly idType?: string;
  readonly tenantColumn: string;
  readonly initial: string;
  readonly transitions: Readonly<Record<string, readonly string[]>>;
  /** Transitions only an approved request of the approvals module may make. */
  readonly requiresApproval: Readonly<Record<string, readonly string[]>>;
  /** Writes a timeline row (label snapshot, display order, cleared_at). */
  readonly stages: boolean;
  /** Keeps a `subject_lifecycles` row: pause, flags and the pinned version. */
  readonly lifecycle: boolean;
  /** The machine version a new record is pinned to. */
  readonly version: number;
  /** The statuses in display order, for `step` and `progress`. */
  readonly order: readonly string[];
  /** The flags `set_lifecycle_flag` accepts. */
  readonly flags: readonly string[];
  readonly history?: {
    readonly table: string;
    readonly id: string;
    readonly from: string;
    readonly to: string;
    readonly actor: string;
    readonly reason: string;
    readonly subject: string;
    readonly tenant: string;
    readonly createdAt: string;
  };
}

export function machines(ctx: BlockSqlContext): readonly Machine[] {
  const raw = ctx.option("machines");

  if (raw === undefined) {
    return [];
  }

  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new TypeError(
      "blocks.state-machine.options.machines must be an object",
    );
  }

  return Object.entries(raw).map(([name, entry]) =>
    machine(name, entry, ctx.subjects, ctx.naming),
  );
}

/**
 * The table keys of `config.subjects.<name>`, used when the machine names no
 * table.
 */
function registered(
  name: string,
  registry: SubjectsConfig,
  where: string,
  naming: EntityNames,
): Record<string, unknown> {
  const entry = Object.hasOwn(registry, name) ? registry[name] : undefined;

  if (entry === undefined) {
    return {};
  }

  if (entry.tenant === false) {
    throw new TypeError(
      `${where}: config.subjects.${name} has no tenant column, which a machine needs`,
    );
  }

  return {
    table: entry.table,
    ...(entry.id !== undefined && { id: entry.id }),
    ...(entry.idType !== undefined && { idType: entry.idType }),
    tenant: entry.tenant ?? naming.rename("organization_id"),
  };
}

function machine(
  name: string,
  entry: unknown,
  registry: SubjectsConfig,
  naming: EntityNames,
): Machine {
  const where = `blocks.state-machine.options.machines.${name}`;

  if (!NAME.test(name)) {
    throw new TypeError(`${where} has an invalid name`);
  }

  if (typeof entry !== "object" || entry === null || Array.isArray(entry)) {
    throw new TypeError(`${where} must be an object`);
  }

  const own: Record<string, unknown> = {};

  for (const [key, value] of Object.entries(entry)) {
    own[key] = value;
  }

  const record =
    own["table"] === undefined
      ? { ...registered(name, registry, where, naming), ...own }
      : own;

  const table = record["table"];
  const column = record["column"];
  const initial = record["initial"];
  const transitions = record["transitions"];

  if (typeof table !== "string" || typeof column !== "string") {
    throw new TypeError(`${where} needs table and column`);
  }

  if (!NAME.test(column)) {
    throw new TypeError(`${where}.column must be a column name`);
  }

  if (typeof initial !== "string") {
    throw new TypeError(`${where}.initial must be a status`);
  }

  if (
    typeof transitions !== "object" ||
    transitions === null ||
    Array.isArray(transitions)
  ) {
    throw new TypeError(
      `${where}.transitions must be an object of status to statuses`,
    );
  }

  const edges = edgesOf(transitions, `${where}.transitions`);

  const gated = edgesOf(
    record["requiresApproval"] ?? {},
    `${where}.requiresApproval`,
  );

  for (const [from, to] of Object.entries(gated)) {
    for (const status of to) {
      if (!edges[from]?.includes(status)) {
        throw new TypeError(
          `${where}.requiresApproval.${from}: ${status} is not an allowed transition`,
        );
      }
    }
  }

  const idType = record["idType"];

  if (
    idType !== undefined &&
    (typeof idType !== "string" || !ID_TYPE.test(idType))
  ) {
    throw new TypeError(`${where}.idType must be a type name such as uuid`);
  }

  const lifecycle = record["lifecycle"] ?? false;

  if (typeof lifecycle !== "boolean") {
    throw new TypeError(`${where}.lifecycle must be true or false`);
  }

  const version = record["version"] ?? 1;

  if (
    typeof version !== "number" ||
    !Number.isInteger(version) ||
    version < 1
  ) {
    throw new TypeError(`${where}.version must be a positive integer`);
  }

  const flags = namesOf(record["flags"], `${where}.flags`);

  if (!lifecycle && (record["version"] !== undefined || flags.length > 0)) {
    throw new TypeError(`${where}: version and flags need lifecycle: true`);
  }

  const statuses = new Set([
    initial,
    ...Object.keys(edges),
    ...Object.values(edges).flat(),
  ]);

  const order = statusList(record["order"], `${where}.order`);

  for (const status of order) {
    if (!statuses.has(status)) {
      throw new TypeError(`${where}.order: ${status} is not a status`);
    }
  }

  const tenantColumn =
    typeof record["tenant"] === "string"
      ? record["tenant"]
      : tenantColumnOf(table, registry, naming);

  if (tenantColumn === undefined) {
    throw new TypeError(
      `${where}: ${table} has no tenant column in config.subjects, which a machine needs`,
    );
  }

  const history = historyOf(record["history"], where, tenantColumn);

  return {
    name,
    table,
    column,
    idColumn: typeof record["id"] === "string" ? record["id"] : "id",
    ...(idType === undefined ? {} : { idType }),
    tenantColumn,
    initial,
    transitions: edges,
    requiresApproval: gated,
    stages: record["stages"] === true,
    lifecycle,
    version,
    order,
    flags,
    ...(history === undefined ? {} : { history }),
  };
}

function edgesOf(
  value: unknown,
  where: string,
): Record<string, readonly string[]> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new TypeError(`${where} must be an object of status to statuses`);
  }

  const edges: Record<string, readonly string[]> = {};

  for (const [from, to] of Object.entries(value)) {
    if (!Array.isArray(to) || to.some((item) => typeof item !== "string")) {
      throw new TypeError(`${where}.${from} must be a list of statuses`);
    }

    edges[from] = to;
  }

  return edges;
}

/** A list of distinct strings, or an empty list when unset. */
function statusList(value: unknown, where: string): readonly string[] {
  if (value === undefined) {
    return [];
  }

  if (
    !Array.isArray(value) ||
    value.some((item) => typeof item !== "string") ||
    new Set(value).size !== value.length
  ) {
    throw new TypeError(`${where} must be a list of distinct statuses`);
  }

  return value.map(String);
}

function namesOf(value: unknown, where: string): readonly string[] {
  const list = statusList(value, where);

  for (const item of list) {
    if (!NAME.test(item)) {
      throw new TypeError(
        `${where}: ${item} must be lowercase letters, digits and underscores`,
      );
    }
  }

  return list;
}

function historyOf(
  value: unknown,
  where: string,
  tenant: string,
): Machine["history"] | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new TypeError(`${where}.history must be an object`);
  }

  const record: Record<string, unknown> = {};

  for (const [key, item] of Object.entries(value)) {
    record[key] = item;
  }

  const text = (key: string, fallback: string): string => {
    const item = record[key];

    if (item === undefined) {
      return fallback;
    }

    if (typeof item !== "string" || !NAME.test(item)) {
      throw new TypeError(`${where}.history.${key} must be a column name`);
    }

    return item;
  };

  const table = record["table"];

  if (typeof table !== "string") {
    throw new TypeError(`${where}.history.table is required`);
  }

  return {
    table,
    id: text("id", "id"),
    from: text("from", "from_status"),
    to: text("to", "to_status"),
    actor: text("actor", "actor_user_id"),
    reason: text("reason", "reason"),
    subject: text("subject", "subject_id"),
    tenant: text("tenant", tenant),
    createdAt: text("createdAt", "created_at"),
  };
}
