import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
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
   * A Standard Schema for the team's extra columns
   * (`blocks.teams.options.extraColumns`), keyed by database name. It types and
   * parses them on reads, and validates them on `create` and `update`.
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
    organizationId: string,
    name: string,
    description?: string,
    fields?: Partial<F>,
    options?: CreateTeamOptions,
  ): AsyncResult<Team<F>>;
  /**
   * Renames a team, sets the extra columns `fields` names, and changes the slug
   * or description `options` names.
   */
  update(
    id: string,
    name: string,
    description?: string,
    fields?: Partial<F>,
    options?: UpdateTeamOptions,
  ): AsyncResult<Team<F>>;
  archive(id: string): AsyncResult<boolean>;
  /** Makes an archived team active again. */
  restore(id: string): AsyncResult<boolean>;
  delete(id: string): AsyncResult<boolean>;
  addMember(teamId: string, userId: string): AsyncResult<boolean>;
  removeMember(teamId: string, userId: string): AsyncResult<boolean>;
  list(organizationId: string): AsyncResult<readonly Team<F>[]>;
}

function teamOf(value: unknown): Team {
  const row = recordOf(value, "team");

  return {
    id: textOf(row["id"]),
    name: optionalText(row["name"]) ?? "",
    slug: optionalText(row["slug"]) ?? "",
    description: nullableText(row["description"]),
    status: oneOf(row["status"], TEAM_STATUSES, "active"),
    memberIds: stringsOf(row["member_ids"]),
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
    create: (organizationId, name, description, extra, settings) =>
      fields
        .args(extra)
        .andThen((checked) =>
          call(
            "create_team",
            {
              tenant: organizationId,
              name,
              description: description ?? null,
              ...(settings?.slug === undefined ? {} : { slug: settings.slug }),
              fields: checked,
            },
            (value) => ({
              ...teamOf(value),
              name,
              description: description ?? null,
            }),
          ).andThen(fields.row),
        ),
    update: (id, name, description, extra, settings) =>
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
    addMember: (teamId, userId) =>
      call(
        "add_team_member",
        { team: teamId, member: userId },
        (value) => value === true,
      ),
    removeMember: (teamId, userId) =>
      call(
        "remove_team_member",
        { team: teamId, member: userId },
        (value) => value === true,
      ),
    list: (organizationId) =>
      call("list_teams", { tenant: organizationId }, (value) =>
        recordsOf(value, "list_teams").map(teamOf),
      ).andThen(fields.rows),
  };

  return withBlockHooks(client, options.hooks, {
    block: "teams",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
