/**
 * How the people and code that call the block may change an entity: `editable`
 * has an update, `append-only` is created and never changed, `state-machine`
 * changes only through named transitions (`approve`, `close`), and `read-only`
 * is written by the block itself or by another block.
 */
export type EntityMutability =
  | "editable"
  | "append-only"
  | "state-machine"
  | "read-only";

/** Every `EntityMutability`, for checks and the generated matrix. */
export const ENTITY_MUTABILITIES: readonly EntityMutability[] = [
  "editable",
  "append-only",
  "state-machine",
  "read-only",
];

/** The methods whose event a manifest can declare with `emits`. */
export type EntityMethod =
  | "create"
  | "update"
  | "delete"
  | "archive"
  | "restore"
  | "purge";

/** Every `EntityMethod`, in the order the matrix lists them. */
export const ENTITY_METHODS: readonly EntityMethod[] = [
  "create",
  "update",
  "delete",
  "archive",
  "restore",
  "purge",
];

/**
 * What an erasure request does to the rows of an entity that holds personal
 * data: `delete` removes them, `anonymize` blanks the `personalData` columns
 * and keeps the row (for rows an audit trail or a ledger points at), and `keep`
 * leaves them because a legal duty requires the record (ADR 0899).
 */
export type EntityErase = "delete" | "anonymize" | "keep";

/** Every `EntityErase`, for checks. */
export const ENTITY_ERASES: readonly EntityErase[] = [
  "delete",
  "anonymize",
  "keep",
];

/** How often a partitioned entity table starts a new partition. */
export type EntityPartitionEvery = "month" | "quarter" | "year";

/** Every `EntityPartitionEvery`, for checks. */
export const ENTITY_PARTITION_EVERY: readonly EntityPartitionEvery[] = [
  "month",
  "quarter",
  "year",
];

/**
 * The archive policy of an entity table that grows without bound (ADR 0900):
 * the column the table is partitioned by, how long each partition spans, and
 * what happens to a partition once it is past its retention class.
 */
export interface EntityPartition {
  /** The timestamp column the table is partitioned by, as the client names it. */
  readonly by: string;
  readonly every: EntityPartitionEvery;
  /** `detach` keeps an old partition as a table, `drop` removes it. */
  readonly archive?: "detach" | "drop";
}

/**
 * One entity's declared surface (ADR 0689). Every field is optional so a block
 * can declare what it knows today; later lanes read these fields to generate
 * pages, permission keys and checks.
 */
export interface EntitySurface {
  /** Whether and how the entity changes after it is created. */
  readonly mutability?: EntityMutability;
  /** The columns a list sorts by, by the names the client uses. */
  readonly sorts?: readonly string[];
  /** The columns a list counts distinct values of. */
  readonly facets?: readonly string[];
  /** The columns `page` filters by, each with a list of values (ADR 0749). */
  readonly filters?: readonly string[];
  /** `true` when the entity registers for search, or the searched columns. */
  readonly search?: boolean | readonly string[];
  /**
   * The permission key each verb checks, by verb, as `<block>.<entity>.<verb>`
   * (`{ read: "risks.risk.read" }`). The verbs are `read`, `create`, `update`,
   * `archive`, `delete`, `export`, `import` and `manage`, plus named domain
   * verbs. `gen` adds each key to the permission catalog and grants it to the
   * default roles (ADR 0799).
   */
  readonly permissions?: Readonly<Record<string, string>>;
  /**
   * `"team"` when the entity's rows are visible by record team (ADR 0134), so a
   * list filters by the caller's teams by declaration.
   */
  readonly recordAccess?: "team";
  /** The columns that hold personal data. */
  readonly personalData?: readonly string[];
  /**
   * The column that names the person a row is about, as the client names it.
   * `subjectAccessPlan` reads it with `personalData` (ADR 0899).
   */
  readonly subjectColumn?: string;
  /**
   * What an erasure does to the entity's rows. Absent means `delete` for an
   * entity with `personalData`; an append-only entity must say `anonymize` or
   * `keep` so an erasure never breaks the audit trail (ADR 0899).
   */
  readonly erase?: EntityErase;
  /**
   * The retention class the entity's rows follow: a kind of the
   * `data-lifecycle` retention policies (`audit`, `outbox`, `trash`) or the
   * app's own (ADR 0901).
   */
  readonly retention?: string;
  /** `true` when a legal hold on the retention class stops the entity's purge. */
  readonly legalHold?: boolean;
  /**
   * The column history of the entity, kept by the `field-history` block, so a
   * page shows a history tab by declaration (ADR 0902). `true` for every
   * column, or the columns whose changes are kept.
   */
  readonly history?: boolean | readonly string[];
  /** The archive policy of a table that grows without bound. */
  readonly partition?: EntityPartition;
  /** `true` when the entity's changes reach clients through realtime. */
  readonly realtime?: boolean;
  /** `true` when the entity is available offline. */
  readonly offline?: boolean;
  /** `true` when every change keeps a version. */
  readonly versioned?: boolean;
  /**
   * `true` when `update` takes an `expectedVersion` (the row's `updatedAt`) and
   * refuses a stale one with a `STALE_WRITE` conflict (ADR 0809).
   */
  readonly expectedVersion?: boolean;
  /**
   * The client methods that take an `idempotencyKey` and claim it through the
   * idempotency block (ADR 0809), such as `["create"]`.
   */
  readonly idempotent?: readonly string[];
  /**
   * The feature flag that turns the entity on (ADR 0922). With `createBlocks({
   * flags })`, each method in `methods` returns `not_found` while the flag is
   * off, so the entity's routes, which call those methods, disappear with it.
   */
  readonly flag?: string;
  /**
   * The client methods that belong to the entity, by name. `flag` gates exactly
   * these; an entity with a `flag` and no `methods` gates nothing and fails the
   * conformance test.
   */
  readonly methods?: readonly string[];
  /** The meter each write counts against. */
  readonly meter?: string;
  /** The plan limit the entity's count is held to. */
  readonly limit?: string;
  /**
   * `bulk(ids, action)` on the entity (ADR 0854): the most ids one call takes,
   * and the actions it accepts. `limit` defaults to 500.
   */
  readonly bulk?: {
    readonly limit?: number;
    readonly actions?: readonly string[];
  };
  /**
   * `export(options)` on the entity (ADR 0855): the CSV streams the rows of
   * `page` under the same filters. `columns` fixes the header and `maxRows`
   * caps the file.
   */
  readonly export?:
    | true
    | { readonly columns?: readonly string[]; readonly maxRows?: number };
  /**
   * Whether each method records an event. `false` marks a mutating method that
   * records none; the conformance test keeps the list of those from growing.
   */
  readonly emits?: Readonly<Partial<Record<EntityMethod, boolean>>>;
}

/** A block's entity surfaces, by entity key (its default singular noun). */
export type BlockEntities = Readonly<Record<string, EntitySurface>>;
