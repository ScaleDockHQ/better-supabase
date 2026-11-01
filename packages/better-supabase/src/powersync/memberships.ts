import type { BlockTransport } from "../core/block-transport.ts";
import type { Result } from "../core/result.ts";
import type { UploadFunction } from "./connector.ts";
import type { PowerSyncDatabaseLike } from "./executor.ts";

import { quoteSqliteIdent } from "../compile/sqlite.ts";
import { dbError } from "../core/errors.ts";
import { err, ok } from "../core/result.ts";

/** The organization functions the local transport answers from SQLite. */
export type LocalMembershipFunction =
  | "list_my_organizations"
  | "leave_organization";

const FUNCTIONS: readonly LocalMembershipFunction[] = [
  "list_my_organizations",
  "leave_organization",
];

export interface PowerSyncMembershipsOptions {
  /** Where every other function goes: `rpcTransport(supabase)`. */
  readonly server: BlockTransport;
  /**
   * The synced table names, as `powersync streams` wrote them into the client
   * schema. Default `memberships` and `organizations`.
   */
  readonly tables?: {
    readonly memberships?: string;
    readonly organizations?: string;
  };
  /**
   * The tenant column of the memberships table, when `config.tenancy` renames
   * it. Default `organization_id`.
   */
  readonly tenantColumn?: string;
  /** Function names, when the instance renames them (`blocks.<name>.entities`). */
  readonly functions?: Partial<Record<LocalMembershipFunction, string>>;
}

type Row = Readonly<Record<string, unknown>>;

/**
 * A block transport for the organizations block on PowerSync: the organization
 * switcher's list (`organizations.mine()`) and leaving an organization run on
 * the synced `memberships` and `organizations` tables, so the switcher works
 * offline. A leave goes into PowerSync's upload queue, which `membershipsRoute`
 * replays on the server. Every other function (switching, members, invitations)
 * goes to `server`.
 *
 * ```ts
 * const organizations = createOrganizations({
 *   transport: powersyncMembershipsTransport(powersync, {
 *     server: rpcTransport(supabase),
 *   }),
 * });
 * ```
 *
 * The synced memberships are the signed-in user's only (the `powersync streams`
 * query filters by `auth.user_id()`). A row has its `role`; with
 * `blocks.memberships.options.roles.many` the other roles and the
 * organization's attribute columns come from the server.
 */
export function powersyncMembershipsTransport(
  database: PowerSyncDatabaseLike,
  options: PowerSyncMembershipsOptions,
): BlockTransport {
  const memberships = quoteSqliteIdent(
    options.tables?.memberships ?? "memberships",
  );

  const organizations = quoteSqliteIdent(
    options.tables?.organizations ?? "organizations",
  );

  const tenant = quoteSqliteIdent(options.tenantColumn ?? "organization_id");

  const byName = new Map<string, LocalMembershipFunction>(
    FUNCTIONS.map((fn) => [options.functions?.[fn] ?? fn, fn]),
  );

  const local = async (
    fn: LocalMembershipFunction,
    args: Row,
  ): Promise<unknown> => {
    switch (fn) {
      case "list_my_organizations": {
        const rows = await database.getAll<Row>(
          `SELECT o.*, m.role AS role FROM ${memberships} m JOIN ${organizations} o ON o.id = m.${tenant}`,
        );

        return rows
          .filter(
            (row) =>
              (row["deleted_at"] ?? null) === null &&
              (row["disabled_at"] ?? null) === null,
          )
          .map(
            ({ deleted_at: _deleted, disabled_at: _disabled, ...row }) => row,
          )
          .toSorted((left, right) =>
            String(left["name"]).localeCompare(String(right["name"])),
          );
      }

      case "leave_organization": {
        await database.execute(
          `DELETE FROM ${memberships} WHERE ${tenant} = ?`,
          [args["organization"]],
        );

        return null;
      }

      default: {
        const unhandled: never = fn;

        throw new TypeError(
          `Unhandled membership function ${String(unhandled)}`,
        );
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

/**
 * The upload route's organizations client: the server one, not the local
 * transport.
 */
export interface MembershipWrites {
  updateMemberRole(input: {
    organizationId: string;
    userId: string;
    role: string;
  }): PromiseLike<Result<unknown>>;
  leave(organizationId: string): PromiseLike<Result<unknown>>;
}

/**
 * The two keys a synced row's `id` joins: `powersync streams` keys a row
 * without an `id` column as `<first>:<second>`, such as
 * `<organization>:<user>`.
 */
export function compositeKey(
  id: string,
): readonly [string, string] | undefined {
  const at = id.lastIndexOf(":");

  return at <= 0 || at === id.length - 1
    ? undefined
    : [id.slice(0, at), id.slice(at + 1)];
}

/**
 * The upload route for `memberships`: replays a local leave (a `DELETE`) with
 * `leave` and a role change (a `PATCH` to `role`) with `updateMemberRole`,
 * whose server functions check the caller may make them. A `PUT` is refused: a
 * user joins through an invitation. Pass an organizations client on
 * `rpcTransport(supabase)`; one on `powersyncMembershipsTransport` would write
 * the change locally again.
 *
 * ```ts
 * createUploadConnector({
 *   tables: { memberships: membershipsRoute(serverOrganizations) },
 * });
 * ```
 */
export function membershipsRoute(
  organizations: MembershipWrites,
): UploadFunction {
  return async (entry) => {
    const key = compositeKey(entry.id);

    if (key === undefined) {
      return err(
        dbError(
          "unsupported",
          `memberships row ${entry.id} is not keyed <organization>:<user>`,
        ),
      );
    }

    const [organizationId, userId] = key;

    switch (entry.op) {
      case "DELETE": {
        return organizations.leave(organizationId);
      }

      case "PATCH": {
        const role = entry.opData?.["role"];

        return typeof role === "string"
          ? organizations.updateMemberRole({ organizationId, userId, role })
          : ok(null);
      }

      default: {
        return err(
          dbError(
            "unsupported",
            `memberships takes role changes and leaves only, not ${entry.op}`,
          ),
        );
      }
    }
  };
}
