import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { PageOptions } from "../../src/core/block-helpers.ts";
import type { Result } from "../../src/core/result.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createContracts } from "../../src/blocks/contracts/index.ts";
import {
  contractListSurface,
  obligationListSurface,
} from "../../src/blocks/contracts/lists.ts";
import { createDeals } from "../../src/blocks/deals/index.ts";
import { dealListSurface } from "../../src/blocks/deals/lists.ts";
import { createForecasts } from "../../src/blocks/forecasts/index.ts";
import { forecastSnapshotListSurface } from "../../src/blocks/forecasts/lists.ts";
import { createMailSync } from "../../src/blocks/mail-sync/index.ts";
import {
  mailAccountListSurface,
  mailThreadListSurface,
} from "../../src/blocks/mail-sync/lists.ts";
import { createPipelines } from "../../src/blocks/pipelines/index.ts";
import { pipelineListSurface } from "../../src/blocks/pipelines/lists.ts";
import { createQuotes } from "../../src/blocks/quotes/index.ts";
import { quoteListSurface } from "../../src/blocks/quotes/lists.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "queue",
  "subjects",
  "versions",
  "signatures",
  "reminders",
  "state-machine",
  "rank",
  "contacts",
  "activities",
  "pipelines",
  "deals",
  "forecasts",
  "mail-sync",
  "contracts",
  "catalog",
  "inventory",
  "quotes",
  "orders",
];

const layout: BlockSqlLayout = {
  subjects: withBlockSubjects({}, ["contacts", "deals", "contracts"], {}),
};

const MISSING = "00000000-0000-4000-8000-000000000000";

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.kind);

describe.skipIf(!live)("every F3 list function runs", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("pages, facets and counts an empty organization and misses a get", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("crm-run-owner");
      await s.install(MODULES, layout);
      const org = await s.organization(owner);
      await s.as(owner);

      const transport = sqlTransport(s.sql);
      const options = { transport, tenant: org };
      const tenant = { organizationId: org };

      const lists = {
        deals: createDeals(options),
        quotes: createQuotes(options),
        pipelines: createPipelines(options),
        forecasts: createForecasts(options),
        contracts: createContracts(options),
        mail: createMailSync(options),
      };

      const reads = [
        lists.deals.page(),
        lists.deals.facets(),
        lists.deals.count(),
        lists.quotes.page(),
        lists.quotes.facets(),
        lists.quotes.count(),
        lists.pipelines.page(tenant),
        lists.pipelines.facets(tenant),
        lists.pipelines.count(tenant),
        lists.forecasts.page(tenant),
        lists.forecasts.facets(tenant),
        lists.forecasts.count(tenant),
        lists.contracts.page(tenant),
        lists.contracts.facets(tenant),
        lists.contracts.count(tenant),
        lists.contracts.obligationPage(tenant),
        lists.contracts.obligationFacets(tenant),
        lists.contracts.obligationCount(tenant),
        lists.mail.threadPage(tenant),
        lists.mail.threadFacets(tenant),
        lists.mail.threadCount(tenant),
        lists.mail.accountPage(tenant),
        lists.mail.accountFacets(tenant),
        lists.mail.accountCount(tenant),
      ];

      const surfaces = [
        [dealListSurface, (o: PageOptions) => lists.deals.page(o)],
        [quoteListSurface, (o: PageOptions) => lists.quotes.page(o)],
        [
          pipelineListSurface,
          (o: PageOptions) => lists.pipelines.page({ ...o, ...tenant }),
        ],
        [
          forecastSnapshotListSurface,
          (o: PageOptions) => lists.forecasts.page({ ...o, ...tenant }),
        ],
        [
          contractListSurface,
          (o: PageOptions) => lists.contracts.page({ ...o, ...tenant }),
        ],
        [
          obligationListSurface,
          (o: PageOptions) =>
            lists.contracts.obligationPage({ ...o, ...tenant }),
        ],
        [
          mailThreadListSurface,
          (o: PageOptions) => lists.mail.threadPage({ ...o, ...tenant }),
        ],
        [
          mailAccountListSurface,
          (o: PageOptions) => lists.mail.accountPage({ ...o, ...tenant }),
        ],
      ] as const;

      for (const [surface, page] of surfaces) {
        for (const by of surface.sorts ?? []) {
          for (const direction of ["asc", "desc"] as const) {
            const q = surface.search === undefined ? {} : { q: "x" };

            expect(hint(await page({ sort: { by, direction }, ...q }))).toBe(
              "ok",
            );
          }
        }
      }

      for (const read of reads) {
        expect(hint(await read)).toBe("ok");
      }

      const misses = [
        await lists.deals.get(MISSING),
        await lists.quotes.get(MISSING),
        await lists.pipelines.get(MISSING),
      ];

      for (const miss of misses) {
        expect(miss.ok).toBe(false);
      }
    } finally {
      await s.close();
    }
  });
});
