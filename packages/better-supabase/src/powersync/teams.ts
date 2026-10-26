import type { BlockTransport } from "../core/block-transport.ts";
import type { Result } from "../core/result.ts";
import type { UploadFunction } from "./connector.ts";
import type { PowerSyncDatabaseLike } from "./executor.ts";

import { quoteSqliteIdent } from "../compile/sqlite.ts";
import { dbError } from "../core/errors.ts";
import { err, ok } from "../core/result.ts";
import { compositeKey } from "./memberships.ts";

/** The team functions the local transport answers from SQLite. */
export type LocalTeamFunction =
  | "list_teams"
  | "update_team"
  | "archive_team"
  | "restore_team"
  | "add_team_member"
  | "remove_team_member";

const FUNCTIONS: readonly LocalTeamFunction[] = [
  "list_teams",
  "update_team",
  "archive_team",
  "restore_team",
  "add_team_member",
  "remove_team_member",
];

export interface PowerSyncTeamsOptions {
  /** Where every other function goes: `rpcTransport(supabase)`. */
  readonly server: BlockTransport;
  /**
   * The synced table names, as `powersync streams` wrote them into the client
   * schema. Default `teams` and `team_members`.
   */
  readonly tables?: { readonly teams?: string; readonly members?: string };
  /**
   * The tenant column of both tables, when `config.tenancy` renames it. Default
   * `tenant_id`.
   */
  readonly tenantColumn?: string;
  /** Function names, when the instance renames them (`blocks.<name>.entities`). */
  readonly functions?: Partial<Record<LocalTeamFunction, string>>;
}

type Row = Readonly<Record<string, unknown>>;

const isRow = (value: unknown): value is Row =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/**
 * A block transport for the teams block on PowerSync: listing teams, renaming,
 * archiving and restoring them, and adding and removing members run on the
 * synced `teams` and `team_members` tables, so they work offline. The writes go
 * into PowerSync's upload queue, which `teamsRoute` and `teamMembersRoute`
 * replay on the server. Creating and deleting a team go to `server`, which
 * picks the id and slug and checks the permission.
 *
 * ```ts
 * const teams = createTeams({
 *   transport: powersyncTeamsTransport(powersync, {
 *     server: rpcTransport(supabase),
 *   }),
 * });
 * ```
 *
 * The synced teams are the ones the signed-in user belongs to (the `powersync
 * streams` query filters by `auth.user_id()`), so `list` offline returns those,
 * not every team the user may read.
 */
export function powersyncTeamsTransport(
  database: PowerSyncDatabaseLike,
  options: PowerSyncTeamsOptions,
): BlockTransport {
  const teams = quoteSqliteIdent(options.tables?.teams ?? "teams");
  const members = quoteSqliteIdent(options.tables?.members ?? "team_members");
  const tenant = quoteSqliteIdent(options.tenantColumn ?? "tenant_id");

  const byName = new Map<string, LocalTeamFunction>(
    FUNCTIONS.map((fn) => [options.functions?.[fn] ?? fn, fn]),
  );

  const status = async (team: unknown, value: string): Promise<boolean> => {
    await database.execute(
      `UPDATE ${teams} SET status = ?, updated_at = ? WHERE id = ?`,
      [value, new Date().toISOString(), team],
    );

    return true;
  };

  const local = async (fn: LocalTeamFunction, args: Row): Promise<unknown> => {
    switch (fn) {
      case "list_teams": {
        const rows = await database.getAll<Row>(
          `SELECT id, name, slug, status FROM ${teams} WHERE ${tenant} = ? ORDER BY name`,
          [args["tenant"]],
        );

        return rows;
      }

      case "update_team": {
        const patch: Row = isRow(args["patch"]) ? args["patch"] : {};

        const sets: string[] = [];
        const values: unknown[] = [];

        const set = (column: string, value: unknown): void => {
          sets.push(`${quoteSqliteIdent(column)} = ?`);
          values.push(value);
        };

        const name = patch["name"] ?? args["name"];

        if (typeof name === "string") {
          set("name", name);
        }

        if ("slug" in patch) {
          set("slug", patch["slug"]);
        }

        if ("description" in patch) {
          set("description", patch["description"]);
        } else if (typeof args["description"] === "string") {
          set("description", args["description"]);
        }

        set("updated_at", new Date().toISOString());

        await database.execute(
          `UPDATE ${teams} SET ${sets.join(", ")} WHERE id = ?`,
          [...values, args["team"]],
        );

        const [row] = await database.getAll<Row>(
          `SELECT id, name, slug FROM ${teams} WHERE id = ?`,
          [args["team"]],
        );

        return row ?? { id: args["team"] };
      }

      case "archive_team": {
        return status(args["team"], "archived");
      }

      case "restore_team": {
        return status(args["team"], "active");
      }

      case "add_team_member": {
        const [team] = await database.getAll<Row>(
          `SELECT ${tenant} AS tenant FROM ${teams} WHERE id = ?`,
          [args["team"]],
        );

        await database.execute(
          `INSERT OR IGNORE INTO ${members} (id, team_id, user_id, ${tenant}, created_at) VALUES (?, ?, ?, ?, ?)`,
          [
            `${String(args["team"])}:${String(args["member"])}`,
            args["team"],
            args["member"],
            team?.["tenant"] ?? null,
            new Date().toISOString(),
          ],
        );

        return true;
      }

      case "remove_team_member": {
        await database.execute(
          `DELETE FROM ${members} WHERE team_id = ? AND user_id = ?`,
          [args["team"], args["member"]],
        );

        return true;
      }

      default: {
        const unhandled: never = fn;

        throw new TypeError(`Unhandled team function ${String(unhandled)}`);
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

/** The upload routes' teams client: the server one, not the local transport. */
export interface TeamWrites {
  update(
    id: string,
    name: string,
    description?: string,
    fields?: never,
    options?: { readonly slug?: string; readonly description?: string | null },
  ): PromiseLike<Result<unknown>>;
  archive(id: string): PromiseLike<Result<unknown>>;
  restore(id: string): PromiseLike<Result<unknown>>;
  delete(id: string): PromiseLike<Result<unknown>>;
  addMember(teamId: string, userId: string): PromiseLike<Result<unknown>>;
  removeMember(teamId: string, userId: string): PromiseLike<Result<unknown>>;
}

/**
 * The upload route for `teams`: replays a local rename, slug or description
 * change with `update`, a `status` change with `archive` or `restore`, and a
 * `DELETE` with `delete`. A `PATCH` carries only the changed columns, so the
 * route reads the team's current name from `database` when the name stayed. A
 * `PUT` is refused: create teams on the server.
 *
 * ```ts
 * createUploadConnector({
 *   tables: {
 *     teams: teamsRoute(serverTeams, powersync),
 *     team_members: teamMembersRoute(serverTeams),
 *   },
 * });
 * ```
 */
export function teamsRoute(
  teams: TeamWrites,
  database: PowerSyncDatabaseLike,
  table = "teams",
): UploadFunction {
  return async (entry) => {
    switch (entry.op) {
      case "DELETE": {
        return teams.delete(entry.id);
      }

      case "PATCH": {
        const data = entry.opData ?? {};

        if (data["status"] === "archived" || data["status"] === "active") {
          const changed =
            data["status"] === "archived"
              ? await teams.archive(entry.id)
              : await teams.restore(entry.id);

          if (!changed.ok) {
            return changed;
          }
        }

        const updates = ["name", "slug", "description"].filter(
          (column) => data[column] !== undefined,
        );

        if (updates.length === 0) {
          return ok(null);
        }

        const name =
          typeof data["name"] === "string"
            ? data["name"]
            : (
                await database.getAll<{ name: unknown }>(
                  `SELECT name FROM ${quoteSqliteIdent(table)} WHERE id = ?`,
                  [entry.id],
                )
              )[0]?.name;

        if (typeof name !== "string") {
          return err(
            dbError(
              "not_found",
              `team ${entry.id} is not in the local database`,
            ),
          );
        }

        return teams.update(entry.id, name, undefined, undefined, {
          ...(typeof data["slug"] === "string" ? { slug: data["slug"] } : {}),
          ...(data["description"] === undefined
            ? {}
            : {
                description:
                  typeof data["description"] === "string"
                    ? data["description"]
                    : null,
              }),
        });
      }

      default: {
        return err(
          dbError(
            "unsupported",
            `teams takes updates and deletes only, not ${entry.op}; create teams on the server`,
          ),
        );
      }
    }
  };
}

/**
 * The upload route for `team_members`: replays a local add (a `PUT`) with
 * `addMember` and a removal (a `DELETE`) with `removeMember`. `powersync
 * streams` keys a row as `<team>:<user>`.
 */
export function teamMembersRoute(teams: TeamWrites): UploadFunction {
  return async (entry) => {
    const key = compositeKey(entry.id);

    if (key === undefined) {
      return err(
        dbError(
          "unsupported",
          `team_members row ${entry.id} is not keyed <team>:<user>`,
        ),
      );
    }

    const [teamId, userId] = key;

    switch (entry.op) {
      case "PUT": {
        return teams.addMember(teamId, userId);
      }

      case "DELETE": {
        return teams.removeMember(teamId, userId);
      }

      default: {
        return ok(null);
      }
    }
  };
}
