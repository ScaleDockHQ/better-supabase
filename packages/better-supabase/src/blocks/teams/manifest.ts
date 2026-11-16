import type { BlockOf } from "../define-block.ts";
import type { TeamsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { teamsEvents } from "./events.ts";
import { teamListSurface } from "./lists.ts";
import { teamsSqlOptions } from "./options.ts";
import { createTeams } from "./teams.ts";

/** The `teams` block's manifest (ADR 0029). */
export const teamsBlock: BlockOf<"teams", typeof createTeams, TeamsEvents> =
  defineBlock({
    name: "teams",
    sql: ["teams"],
    options: { teams: teamsSqlOptions },
    events: teamsEvents,
    create: createTeams,
    category: "tenancy",
    entities: {
      team: {
        ...teamListSurface,
        mutability: "editable",
        offline: { scope: "tenant" },
        emits: { create: true, update: true, purge: true },
      },
    },
    concerns: ["lifecycle"],
    description:
      "Tenant teams and their members. Inbox assignment uses these rows instead of its own team tables.",
    recipes: ["team-picker"],
  });
