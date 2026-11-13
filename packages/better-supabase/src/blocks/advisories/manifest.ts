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
  entities: {
    advisory: {
      mutability: "editable",
      emits: { create: true, update: true },
      permissions: {
        read: "advisories.read",
        create: "advisories.write",
        update: "advisories.write",
        publish: "advisories.publish",
      },
    },
    advisory_product: {
      mutability: "editable",
      emits: { create: true, update: true },
    },
    advisory_product_version: {
      mutability: "append-only",
      emits: { create: true },
    },
    sbom_component: { mutability: "state-machine" },
    vulnerability: {
      mutability: "editable",
      emits: { create: true, update: false },
    },
    vex_statement: { mutability: "editable", emits: { update: true } },
    advisory_vulnerability: { mutability: "read-only" },
  },
  description:
    "Security advisories for a software vendor: products and versions with CycloneDX components, vulnerabilities enriched from OSV, EPSS and the CISA KEV catalog on a schedule, OpenVEX statements per version, and CSAF 2.0 advisories with a /.well-known/csaf handler, linked to incidents and risks through relations.",
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
