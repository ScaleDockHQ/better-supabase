import type { BlockTransport } from "../core/block-transport.ts";
import type { Result } from "../core/result.ts";
import type { UploadFunction } from "./connector.ts";
import type { PowerSyncDatabaseLike } from "./executor.ts";

import { quoteSqliteIdent } from "../compile/sqlite.ts";
import { dbError } from "../core/errors.ts";
import { err, ok } from "../core/result.ts";
import { postgrestTimestamp } from "./executor.ts";

/** The profile functions the local transport answers from SQLite. */
export type LocalProfileFunction = "my_profile" | "update_my_profile";

const FUNCTIONS: readonly LocalProfileFunction[] = [
  "my_profile",
  "update_my_profile",
];

/**
 * Columns a user can't set on their own profile: the key, the email from Auth,
 * the active organization and team (set by switching) and the stamps.
 */
const PROTECTED = new Set([
  "id",
  "email",
  "active_organization_id",
  "active_team_id",
  "disabled_at",
  "created_at",
  "updated_at",
]);

const JSON_COLUMNS = new Set(["onboarding"]);
const TIMESTAMP_COLUMNS = new Set(["disabled_at", "created_at", "updated_at"]);

export interface PowerSyncProfilesOptions {
  /** Where every other function goes: `rpcTransport(supabase)`. */
  readonly server: BlockTransport;
  /**
   * The synced table name, as `powersync streams` wrote it into the client
   * schema. Default `profiles`.
   */
  readonly table?: string;
  /** Function names, when the instance renames them (`blocks.<name>.entities`). */
  readonly functions?: Partial<Record<LocalProfileFunction, string>>;
  /**
   * The signed-in user's id, such as `() => session?.user.id`. The local reads
   * pick that user's row, so a row another user left behind before the next
   * sync is never returned. Without it, the transport reads the first row.
   */
  readonly userId?: () =>
    | string
    | null
    | undefined
    | PromiseLike<string | null | undefined>;
}

type Row = Readonly<Record<string, unknown>>;

const isRow = (value: unknown): value is Row =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/**
 * A block transport for the profiles block on PowerSync: `profiles.mine()` and
 * `profiles.updateMine()` run on the synced `profiles` row, so the user's
 * profile reads and edits work offline. An edit goes into PowerSync's upload
 * queue, which `profilesRoute` replays on the server.
 *
 * ```ts
 * const profiles = createProfiles({
 *   transport: powersyncProfilesTransport(powersync, {
 *     server: rpcTransport(supabase),
 *     userId: async () =>
 *       (await supabase.auth.getSession()).data.session?.user.id,
 *   }),
 * });
 * ```
 *
 * The synced row is the signed-in user's only (the `powersync streams` query
 * filters by `auth.user_id()`). `updateMine` writes the columns the local row
 * has, except the ones only the server sets (`email`, the active organization
 * and team, and the stamps).
 */
export function powersyncProfilesTransport(
  database: PowerSyncDatabaseLike,
  options: PowerSyncProfilesOptions,
): BlockTransport {
  const table = quoteSqliteIdent(options.table ?? "profiles");

  const byName = new Map<string, LocalProfileFunction>(
    FUNCTIONS.map((fn) => [options.functions?.[fn] ?? fn, fn]),
  );

  const mine = async (): Promise<Row | undefined> => {
    if (options.userId === undefined) {
      return (await database.getAll<Row>(`SELECT * FROM ${table} LIMIT 1`))[0];
    }

    const id = await options.userId();

    return id === null || id === undefined
      ? undefined
      : (
          await database.getAll<Row>(`SELECT * FROM ${table} WHERE id = ?`, [
            id,
          ])
        )[0];
  };

  const local = async (
    fn: LocalProfileFunction,
    args: Row,
  ): Promise<unknown> => {
    switch (fn) {
      case "my_profile": {
        const row = await mine();

        return row === undefined ? null : fromSqlite(row);
      }

      case "update_my_profile": {
        const row = await mine();
        const attrs = isRow(args["attrs"]) ? args["attrs"] : {};

        if (row === undefined) {
          return false;
        }

        const columns = Object.keys(attrs).filter(
          (column) => column in row && !PROTECTED.has(column),
        );

        if (columns.length === 0) {
          return true;
        }

        const stamped = "updated_at" in row;

        await database.execute(
          `UPDATE ${table} SET ${[...columns, ...(stamped ? ["updated_at"] : [])].map((column) => `${quoteSqliteIdent(column)} = ?`).join(", ")} WHERE id = ?`,
          [
            ...columns.map((column) => toSqlite(column, attrs[column])),
            ...(stamped ? [new Date().toISOString()] : []),
            row["id"],
          ],
        );

        return true;
      }

      default: {
        const unhandled: never = fn;

        throw new TypeError(`Unhandled profile function ${String(unhandled)}`);
      }
    }
  };

  return {
    call(schema, fn, args) {
      const handled = byName.get(fn);

      return handled === undefined
        ? options.server.call(schema, fn, args)
        : local(handled, args);
    },
  };
}

function fromSqlite(row: Row): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(row).map(([column, value]) => {
      if (typeof value !== "string") {
        return [column, value];
      }

      if (JSON_COLUMNS.has(column)) {
        try {
          return [column, JSON.parse(value)];
        } catch {
          return [column, value];
        }
      }

      return [
        column,
        TIMESTAMP_COLUMNS.has(column) ? postgrestTimestamp(value) : value,
      ];
    }),
  );
}

function toSqlite(column: string, value: unknown): unknown {
  return JSON_COLUMNS.has(column) && value !== null && value !== undefined
    ? JSON.stringify(value)
    : (value ?? null);
}

/** The upload route's profiles client: the server one, not the local transport. */
export interface ProfileWrites {
  updateMine(
    attrs: Readonly<Record<string, unknown>>,
  ): PromiseLike<Result<unknown>>;
}

/**
 * The upload route for `profiles`: replays a local edit (a `PATCH`) with
 * `updateMine`, which writes only the columns the profiles block lets a user
 * change. A `PUT` or `DELETE` is refused: the server creates and removes
 * profiles with the user.
 *
 * ```ts
 * createUploadConnector({
 *   tables: { profiles: profilesRoute(serverProfiles) },
 * });
 * ```
 */
export function profilesRoute(profiles: ProfileWrites): UploadFunction {
  return async (entry) => {
    if (entry.op !== "PATCH") {
      return err(
        dbError("unsupported", `profiles takes updates only, not ${entry.op}`),
      );
    }

    const attrs = Object.fromEntries(
      Object.entries(entry.opData ?? {})
        .filter(([column]) => !PROTECTED.has(column))
        .map(([column, value]) => [
          column,
          JSON_COLUMNS.has(column) && typeof value === "string"
            ? parsed(value)
            : value,
        ]),
    );

    return Object.keys(attrs).length === 0
      ? ok(null)
      : profiles.updateMine(attrs);
  };
}

function parsed(value: string): unknown {
  try {
    return JSON.parse(value);
  } catch {
    return value;
  }
}
