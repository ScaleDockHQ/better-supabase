import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  isRecord,
  nullableText,
  oneOf,
  optionalText,
  recordOf,
  recordsOf,
  stringsOf,
  textOf,
} from "../shared.ts";

export interface TeamsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockOptions {
  /**
   * A Standard Schema for the team's extra columns (columns the app's schema
   * files add to the table), keyed by database name. It types and parses them
   * on reads, and validates them on `create` and `update`.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Teams<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

export type TeamStatus = "active" | "archived";

const TEAM_STATUSES: readonly TeamStatus[] = ["active", "archived"];

/** A team. `F` types the extra columns the `fields` schema describes. */
export interface Team<F extends object = Record<never, never>> {
  readonly id: string;
  readonly name: string;
  readonly slug: string;
  readonly description: string | null;
  /** `archived` teams stay in `list` until `restore` or `delete`. */
  readonly status: TeamStatus;
  /** The members' user ids, oldest first. Empty on `create` and `update`. */
  readonly memberIds: readonly string[];
  /**
   * The members' employee ids, oldest first. Empty without the employees block,
   * and on `create` and `update`.
   */
  readonly memberEmployeeIds: readonly string[];
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

/** What `teams.create` takes besides the name and description. */
export interface CreateTeamOptions {
  /**
   * The slug, lowercase letters and digits joined by single hyphens. Derived
   * from the name when left out.
   */
  readonly slug?: string;
}

/**
 * What `teams.update` changes besides the name. A key that is left out keeps
 * its value; `description: null` clears it.
 */
export interface UpdateTeamOptions {
  readonly slug?: string;
  readonly description?: string | null;
}

export interface Teams<F extends object = Record<never, never>> {
  /** Creates a team; `fields` sets its extra columns. */
  create(
    input: {
      organizationId: string;
      name: string;
      description?: string | undefined;
      fields?: Partial<F> | undefined;
    } & CreateTeamOptions,
  ): AsyncResult<Team<F>>;
  /**
   * Renames a team, sets the extra columns `fields` names, and changes the slug
   * or description `options` names.
   */
  update(input: {
    id: string;
    name: string;
    description?: string | undefined;
    fields?: Partial<F> | undefined;
    options?: UpdateTeamOptions | undefined;
  }): AsyncResult<Team<F>>;
  archive(id: string): AsyncResult<boolean>;
  /** Makes an archived team active again. */
  restore(id: string): AsyncResult<boolean>;
  delete(id: string): AsyncResult<boolean>;
  /** Adds a user, or with the employees block an employee, to a team. */
  addMember(input: TeamMemberInput): AsyncResult<boolean>;
  /** Removes a user or an employee; a row with both goes as a whole. */
  removeMember(input: TeamMemberInput): AsyncResult<boolean>;
  list(
    organizationId: string,
    options?: { readonly limit?: number },
  ): AsyncResult<readonly Team<F>[]>;
  /**
   * Makes `userIds` the team's user members and `employeeIds` its employee
   * members: it adds the missing ones and removes the others, and returns what
   * changed. A list left out stays as it is. It reads `list` to find the
   * current members (again before the employees), then calls `addMember` and
   * `removeMember`, so their hooks see each step. A failure stops the loop; run
   * it again to finish.
   */
  setMembers(input: {
    organizationId: string;
    teamId: string;
    userIds?: readonly string[] | undefined;
    employeeIds?: readonly string[] | undefined;
  }): AsyncResult<{
    readonly added: readonly string[];
    readonly removed: readonly string[];
    readonly addedEmployees?: readonly string[];
    readonly removedEmployees?: readonly string[];
  }>;
  /** `archive` when `archived` is true, otherwise `restore`. */
  setArchived(input: {
    teamId: string;
    archived: boolean;
  }): AsyncResult<boolean>;
}

/** A team and a user, or with the employees block an employee. */
type TeamMemberInput =
  | { readonly teamId: string; readonly userId: string }
  | { readonly teamId: string; readonly employeeId: string };

const memberArgs = (input: TeamMemberInput): Record<string, string> =>
  "employeeId" in input
    ? { team: input.teamId, employee: input.employeeId }
    : { team: input.teamId, member: input.userId };

function teamOf(value: unknown): Team {
  const row = recordOf(value, "team");

  return {
    id: textOf(row["id"]),
    name: optionalText(row["name"]) ?? "",
    slug: optionalText(row["slug"]) ?? "",
    description: nullableText(row["description"]),
    status: oneOf(row["status"], TEAM_STATUSES, "active"),
    memberIds: stringsOf(row["member_ids"]),
    memberEmployeeIds: stringsOf(row["member_employee_ids"]),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
  };
}

/** The `teams` SQL module as typed calls. */
export function createTeams<S extends StandardSchemaV1 | undefined = undefined>(
  options: TeamsOptions<S>,
): Teams<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "team fields");

  const client: Teams<F> = {
    create: ({
      organizationId,
      name,
      description,
      fields: extra,
      ...settings
    }) =>
      fields
        .args(extra)
        .andThen((checked) =>
          call(
            "create_team",
            {
              tenant: organizationId,
              name,
              description: description ?? null,
              ...(settings.slug === undefined ? {} : { slug: settings.slug }),
              fields: checked,
            },
            (value) => ({
              ...teamOf(value),
              name,
              description: description ?? null,
            }),
          ).andThen(fields.row),
        ),
    update: ({ id, name, description, fields: extra, options: settings }) =>
      fields
        .args(extra)
        .andThen((checked) =>
          call(
            "update_team",
            {
              team: id,
              name,
              description: description ?? null,
              ...(settings === undefined ||
              (settings.slug === undefined &&
                settings.description === undefined)
                ? {}
                : {
                    patch: {
                      ...(settings.slug === undefined
                        ? {}
                        : { slug: settings.slug }),
                      ...(settings.description === undefined
                        ? {}
                        : { description: settings.description }),
                    },
                  }),
              fields: checked,
            },
            teamOf,
          ).andThen(fields.row),
        ),
    archive: (id) =>
      call("archive_team", { team: id }, (value) => value === true),
    restore: (id) =>
      call("restore_team", { team: id }, (value) => value === true),
    delete: (id) =>
      call("delete_team", { team: id }, (value) => value === true),
    addMember: (input) =>
      call("add_team_member", memberArgs(input), (value) => value === true),
    removeMember: (input) =>
      call("remove_team_member", memberArgs(input), (value) => value === true),
    list: (organizationId, options) =>
      call("list_teams", { tenant: organizationId }, (value) => {
        const rows = recordsOf(value, "list_teams").map(teamOf);

        return options?.limit === undefined
          ? rows
          : rows.slice(0, options.limit);
      }).andThen(fields.rows),
    setMembers: ({ organizationId, teamId, userIds, employeeIds }) =>
      AsyncResult.from(async () => {
        const current = async (key: "memberIds" | "memberEmployeeIds") => {
          const teams = await hooked.list(organizationId);

          if (!teams.ok) {
            return teams;
          }

          const team = teams.data.find((each) => each.id === teamId);

          return team === undefined
            ? err(dbError("not_found", "No team in this organization"))
            : ok(team[key]);
        };

        const sync = async (
          wanted: readonly string[],
          key: "memberIds" | "memberEmployeeIds",
          member: (id: string) => TeamMemberInput,
        ) => {
          const now = await current(key);

          if (!now.ok) {
            return now;
          }

          const want = new Set(wanted);
          const have = new Set(now.data);
          const added = [...want].filter((id) => !have.has(id));
          const removed = [...have].filter((id) => !want.has(id));

          for (const id of added) {
            const result = await hooked.addMember(member(id));

            if (!result.ok) {
              return result;
            }
          }

          for (const id of removed) {
            const result = await hooked.removeMember(member(id));

            if (!result.ok) {
              return result;
            }
          }

          return ok({ added, removed });
        };

        const users =
          userIds === undefined
            ? ok({ added: [], removed: [] })
            : await sync(userIds, "memberIds", (userId) => ({
                teamId,
                userId,
              }));

        if (!users.ok || employeeIds === undefined) {
          return users;
        }

        const people = await sync(
          employeeIds,
          "memberEmployeeIds",
          (employeeId) => ({ teamId, employeeId }),
        );

        return people.ok
          ? ok({
              ...users.data,
              addedEmployees: people.data.added,
              removedEmployees: people.data.removed,
            })
          : people;
      }),
    setArchived: ({ teamId, archived }) =>
      archived ? hooked.archive(teamId) : hooked.restore(teamId),
  };

  // Helpers call the hooked client, so app hooks see each step.
  const hooked: Teams<F> = withBlockHooks(client, options.hooks, {
    block: "teams",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
