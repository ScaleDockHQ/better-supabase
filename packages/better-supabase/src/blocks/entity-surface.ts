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
  /** The retention class the entity's rows follow. */
  readonly retention?: string;
  /** `true` when the entity's changes reach clients through realtime. */
  readonly realtime?: boolean;
  /** `true` when the entity is available offline. */
  readonly offline?: boolean;
  /** `true` when every change keeps a version. */
  readonly versioned?: boolean;
  /** The feature flag that turns the entity on. */
  readonly flag?: string;
  /** The meter each write counts against. */
  readonly meter?: string;
  /** The plan limit the entity's count is held to. */
  readonly limit?: string;
  /**
   * Whether each method records an event. `false` marks a mutating method that
   * records none; the conformance test keeps the list of those from growing.
   */
  readonly emits?: Readonly<Partial<Record<EntityMethod, boolean>>>;
}

/** A block's entity surfaces, by entity key (its default singular noun). */
export type BlockEntities = Readonly<Record<string, EntitySurface>>;
