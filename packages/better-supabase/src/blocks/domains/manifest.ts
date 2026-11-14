import type { BlockOf } from "../define-block.ts";
import type { DomainsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createDomains } from "./domains.ts";
import { domainsEvents } from "./events.ts";
import { hostnameListSurface } from "./lists.ts";
import { domainsSqlOptions } from "./options.ts";

/** The `domains` block's manifest (ADR 0029). */
export const domainsBlock: BlockOf<
  "domains",
  typeof createDomains,
  DomainsEvents
> = defineBlock({
  name: "domains",
  sql: ["domains"],
  options: { domains: domainsSqlOptions },
  events: domainsEvents,
  create: createDomains,
  category: "tenancy",
  entities: {
    hostname: {
      ...hostnameListSurface,
      mutability: "state-machine",
      emits: { create: true, delete: true },
    },
  },
  description:
    "Hostnames an organization serves its app on: custom domains verified by a DNS TXT record, subdomains of the platform domain, one primary per organization, and resolve_hostname() for the proxy.",
});
