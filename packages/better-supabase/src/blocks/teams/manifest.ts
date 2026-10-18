import type { BlockOf } from "../define-block.ts";
import type { TeamsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { teamsEvents } from "./events.ts";
import { teamsSqlOptions } from "./options.ts";
import { createTeams } from "./teams.ts";

/** The `teams` block's manifest (ADR 0029). */
export const teamsBlock: BlockOf<"teams", typeof createTeams, TeamsEvents> =
  defineBlock({
    name: "teams",
    sql: ["teams"],
    options: {
      teams: teamsSqlOptions,
    },
    events: teamsEvents,
    create: createTeams,
    category: "tenancy",
    recipes: ["team-picker"],
  });
