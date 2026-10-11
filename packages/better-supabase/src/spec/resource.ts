import type { AnyAuthorizer } from "../core/authorizer.ts";
import type { SchemaMeta, TableMeta } from "../schema/types.ts";
import type {
  JsonObject,
  ResourceOperation,
  SecurityRequirement,
} from "./model.ts";
import type { StandardLike } from "./schemas.ts";

export type ResourcePagination = "offset" | "cursor";

export type ActionMethod = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";

/** A custom endpoint on a resource, documented next to its CRUD operations. */
export interface ResourceActionSpec<Ref = string> {
  readonly method: ActionMethod;
  /**
   * Relative to the collection: `/{id}/send` acts on one row (the key
   * parameter is the table's primary key), `/export` on the table.
   */
  readonly path: string;
  /** The JSON body. */
  readonly input?: StandardLike;
  /** The query parameters, as an object schema. */
  readonly query?: StandardLike;
  /** The JSON response. Without it the action answers 204. */
  readonly output?: StandardLike;
  /** Success status. Defaults to 200 with an output, 204 without. */
  readonly status?: number;
  readonly summary?: string;
  readonly description?: string;
  readonly deprecated?: boolean;
  readonly permission?: Ref;
  /** Names of the events the action emits, for AsyncAPI. */
  readonly emits?: readonly string[];
}

/** One shared error response: its component name, status and description. */
export interface ErrorResponse {
  readonly name: string;
  readonly status: number;
  readonly description: string;
}

/**
 * What a resource serves and documents. `defineResource` and `defineApi`
 * read the same object, so the routes and the spec cannot drift.
 */
export interface ResourceDescription<Ref = string> {
  /** Defaults to every operation for tables, `list` and `get` for views. */
  readonly operations?: readonly ResourceOperation[];
  /** Filters, search and sorts for `list`, from `defineListQuery`. */
  readonly list?: {
    readonly openapi: readonly unknown[];
    readonly pagination?: ResourcePagination;
  };
  /** Paging of the default list. Defaults to `offset`. */
  readonly pagination?: ResourcePagination;
  /** Largest page of the default list. Defaults to 200. */
  readonly maxPageSize?: number;
  /** Path of the collection in the spec. Defaults to `/<table>`. */
  readonly path?: string;
  readonly tag?: string;
  readonly description?: string;
  /** Validates request bodies; their JSON Schema replaces the table's in the spec. */
  readonly input?: {
    readonly create?: StandardLike;
    readonly update?: StandardLike;
  };
  /** The response shape of an operation whose hooks change it. */
  readonly output?: Partial<Readonly<Record<ResourceOperation, StandardLike>>>;
  readonly actions?: Readonly<Record<string, ResourceActionSpec<Ref>>>;
  /**
   * The permission of each operation. `true` asks the authorizer
   * (`forOperation`) for every enabled operation.
   */
  readonly permissions?:
    | true
    | Partial<Readonly<Record<ResourceOperation, Ref>>>;
  /** Overrides the model's security for this resource; `[]` makes it public. */
  readonly security?: readonly SecurityRequirement[];
  /** The shared error responses. Defaults to the API's `errors`. */
  readonly errors?: readonly ErrorResponse[];
  /** Deep-merged into the lowered operation, by operation or action name (`*` for all). */
  readonly extend?: Readonly<Record<string, JsonObject>>;
}

export interface PlannedAction<Ref = string> extends ResourceActionSpec<Ref> {
  readonly name: string;
  /** The `{name}` segments of `path`. */
  readonly params: readonly string[];
  /** The path split into segments; `{name}` segments are params. */
  readonly segments: readonly string[];
}

/** A resolved `ResourceDescription`. */
export interface ResourcePlan<Ref = string> {
  readonly table: string;
  readonly meta: TableMeta;
  readonly operations: readonly ResourceOperation[];
  /** Name of the key parameter, or `undefined` for tables without a single-column key. */
  readonly keyParam: string | undefined;
  readonly pagination: ResourcePagination;
  readonly maxPageSize: number;
  readonly description: ResourceDescription<Ref>;
  readonly actions: readonly PlannedAction<Ref>[];
  /** The permission reference of each operation and action that has one. */
  readonly permissions: Readonly<Record<string, Ref>>;
}

const ACTION_NAME = /^[A-Za-z][A-Za-z0-9_]*$/u;
const RESERVED: ReadonlySet<string> = new Set([
  "list",
  "get",
  "create",
  "update",
  "delete",
]);

function planAction<Ref>(
  table: string,
  name: string,
  action: ResourceActionSpec<Ref>,
  keyParam: string | undefined,
): PlannedAction<Ref> {
  if (!ACTION_NAME.test(name) || RESERVED.has(name)) {
    throw new TypeError(
      `${table}.actions.${name}: use a name of letters, digits and "_" that is not an operation`,
    );
  }
  if (!action.path.startsWith("/") || action.path === "/") {
    throw new TypeError(
      `${table}.actions.${name}: the path must start with "/" and name a segment, e.g. "/{id}/send"`,
    );
  }
  const segments = action.path.slice(1).split("/");
  const params: string[] = [];
  for (const segment of segments) {
    const match = /^\{(\w+)\}$/u.exec(segment);
    if (match) params.push(match[1]!);
    else if (segment === "" || /[{}]/u.test(segment)) {
      throw new TypeError(
        `${table}.actions.${name}: "${action.path}" has an invalid segment`,
      );
    }
  }
  if (params.some((param) => param !== keyParam)) {
    throw new TypeError(
      `${table}.actions.${name}: the only path parameter is the key ${keyParam ? `"{${keyParam}}"` : "(this table has none)"}`,
    );
  }
  return { ...action, name, params, segments };
}

/**
 * Resolves what a resource serves: the operations, the key, paging,
 * actions and permissions. Shared by `defineResource` and the API model.
 */
export function planResource<Ref = string>(
  schema: SchemaMeta,
  table: string,
  description: ResourceDescription<Ref> = {},
  authorizer?: AnyAuthorizer,
): ResourcePlan<Ref> {
  const meta = schema.tables[table];
  if (!meta) throw new TypeError(`Unknown table "${table}"`);
  const operations: readonly ResourceOperation[] =
    description.operations ??
    (meta.kind === "view"
      ? ["list", "get"]
      : ["list", "get", "create", "update", "delete"]);
  const keyParam =
    meta.primaryKey.length === 1 ? meta.primaryKey[0] : undefined;
  const pagination = description.list
    ? (description.list.pagination ?? "offset")
    : (description.pagination ?? "offset");
  const actions = Object.entries(description.actions ?? {}).map(
    ([name, action]) => planAction(table, name, action, keyParam),
  );
  const permissions: Record<string, Ref> = {};
  if (description.permissions === true) {
    if (!authorizer?.forOperation) {
      throw new TypeError(
        `${table}: permissions: true needs an authorizer with forOperation()`,
      );
    }
    for (const operation of operations) {
      // SAFETY: forOperation returns the authorizer's own reference type, Ref.
      const ref = authorizer.forOperation(table, operation) as Ref | undefined;
      if (ref !== undefined) permissions[operation] = ref;
    }
  } else if (description.permissions) {
    for (const [operation, ref] of Object.entries(description.permissions)) {
      if (ref !== undefined) permissions[operation] = ref;
    }
  }
  for (const action of actions) {
    if (action.permission !== undefined)
      permissions[action.name] = action.permission;
  }
  return {
    table,
    meta,
    operations,
    keyParam,
    pagination,
    maxPageSize: description.maxPageSize ?? 200,
    description,
    actions,
    permissions,
  };
}

/** The action whose method and segments match, with its params. */
export function matchAction<Ref>(
  plan: ResourcePlan<Ref>,
  method: string,
  segments: readonly string[],
):
  | {
      readonly action: PlannedAction<Ref>;
      readonly params: Readonly<Record<string, string>>;
    }
  | "method"
  | undefined {
  let wrongMethod = false;
  for (const action of plan.actions) {
    if (action.segments.length !== segments.length) continue;
    const params: Record<string, string> = {};
    const fits = action.segments.every((segment, index) => {
      const value = segments[index]!;
      if (segment.startsWith("{")) {
        params[segment.slice(1, -1)] = value;
        return value !== "";
      }
      return segment === value;
    });
    if (!fits) continue;
    if (action.method === method) return { action, params };
    wrongMethod = true;
  }
  return wrongMethod ? "method" : undefined;
}
