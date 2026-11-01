import type { BlockOf } from "../define-block.ts";
import type { AdvisoriesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createAdvisories } from "./advisories.ts";
import { advisoriesEvents } from "./events.ts";

/** The `advisories` block's manifest (ADR 0188). */
export const advisoriesBlock: BlockOf<
  "advisories",
  typeof createAdvisories,
  AdvisoriesEvents
> = defineBlock({
  name: "advisories",
  sql: ["advisories"],
  events: advisoriesEvents,
  create: createAdvisories,
  category: "work",
  providers: [
    {
      option: "feed",
      type: "VulnerabilityFeed",
      from: "better-supabase/blocks/advisories",
      required: false,
      description:
        "Reads OSV, EPSS and the CISA KEV catalog. Defaults to the public endpoints over fetch.",
      example: "publicVulnerabilityFeed()",
    },
  ],
  schedules: [
    {
      name: "enrich",
      cron: "0 * * * *",
      runs: "enrichDue()",
      description:
        "Fills new and stale vulnerabilities from OSV, EPSS and the CISA KEV catalog.",
    },
  ],
});
