import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";

import {
  blockCall,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";

export interface TeamsOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface Team {
  readonly id: string;
  readonly name: string;
  readonly slug: string;
}

export interface Teams {
  create(
    organizationId: string,
    name: string,
    description?: string,
  ): AsyncResult<Team>;
  update(id: string, name: string, description?: string): AsyncResult<Team>;
  archive(id: string): AsyncResult<boolean>;
  delete(id: string): AsyncResult<boolean>;
  addMember(teamId: string, userId: string): AsyncResult<boolean>;
  removeMember(teamId: string, userId: string): AsyncResult<boolean>;
  list(organizationId: string): AsyncResult<readonly Team[]>;
}

function teamOf(value: unknown): Team {
  const row = recordOf(value, "team");
  return {
    id: textOf(row["id"]),
    name: optionalText(row["name"]) ?? "",
    slug: optionalText(row["slug"]) ?? "",
  };
}

export function createTeams(options: TeamsOptions): Teams {
  const call = blockCall(options.transport, options.schema, options.mappers);
  return {
    create: (organizationId, name, description) =>
      call(
        "create_team",
        { tenant: organizationId, name, description: description ?? null },
        (value) => ({ ...teamOf(value), name }),
      ),
    update: (id, name, description) =>
      call(
        "update_team",
        { team: id, name, description: description ?? null },
        (value) => ({ ...teamOf(value), name, slug: "" }),
      ),
    archive: (id) =>
      call("archive_team", { team: id }, (value) => value === true),
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
      ),
  };
}
