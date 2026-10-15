import type { BlockOf } from "../define-block.ts";
import type { TeamsEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { teamsEvents } from "./events.ts";
import { createTeams } from "./teams.ts";

/** The `teams` block's manifest (ADR 0029). */
export const teamsBlock: BlockOf<"teams", typeof createTeams, TeamsEvents> =
  defineBlock({
    name: "teams",
    sql: ["teams"],
    options: {
      teams: optionKeys(["teamIdType"]),
    },
    events: teamsEvents,
    create: createTeams,
    category: "foundation",
  });
