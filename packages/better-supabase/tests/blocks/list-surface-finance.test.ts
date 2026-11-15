import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";
import type { EntityList } from "../../src/core/entity-list.ts";

import { createAccounting } from "../../src/blocks/accounting/index.ts";
import { createBanking } from "../../src/blocks/banking/index.ts";
import { createBillableTime } from "../../src/blocks/billable-time/index.ts";
import { createExpenses } from "../../src/blocks/expenses/index.ts";
import { createInvoices } from "../../src/blocks/invoices/index.ts";
import { createScores } from "../../src/blocks/scores/index.ts";
import { fieldsTransport } from "./fields-transport.ts";

interface Case {
  readonly label: string;
  readonly fn: string;
  readonly sort: string;
  readonly filter: string;
  readonly facet: string;
  /** Whether the entity declares `search`, so `q` is accepted. */
  readonly searchable?: boolean;
  readonly list: (transport: BlockTransport) => EntityList<unknown>;
}

const options = (transport: BlockTransport) => ({ transport, tenant: "org-1" });

// The finance blocks (family F4) page through the same client contract as the
// other lists; this file runs the shared checks over them.
const CASES: readonly Case[] = [
  {
    label: "accounting accounts",
    searchable: true,
    fn: "page_accounting_accounts",
    sort: "name",
    filter: "type",
    facet: "type",
    list: (transport) => {
      const client = createAccounting(options(transport));

      return {
        page: (page) =>
          client.accountPage({ ...page, organizationId: "org-1" }),
        facets: (facets) =>
          client.accountFacets({ ...facets, organizationId: "org-1" }),
        count: (count) =>
          client.accountCount({ ...count, organizationId: "org-1" }),
      };
    },
  },
  {
    label: "accounting entries",
    searchable: true,
    fn: "page_accounting_entries",
    sort: "createdAt",
    filter: "status",
    facet: "status",
    list: (transport) => {
      const client = createAccounting(options(transport));

      return {
        page: (page) => client.entryPage({ ...page, organizationId: "org-1" }),
        facets: (facets) =>
          client.entryFacets({ ...facets, organizationId: "org-1" }),
        count: (count) =>
          client.entryCount({ ...count, organizationId: "org-1" }),
      };
    },
  },
  {
    label: "bank accounts",
    searchable: true,
    fn: "page_bank_accounts",
    sort: "createdAt",
    filter: "currency",
    facet: "currency",
    list: (transport) => {
      const client = createBanking(options(transport));

      return {
        page: (page) => client.accountPage(page),
        facets: (facets) => client.accountFacets(facets),
        count: (count) => client.accountCount(count),
      };
    },
  },
  {
    label: "payment batches",
    searchable: true,
    fn: "page_payment_batches",
    sort: "executionOn",
    filter: "status",
    facet: "status",
    list: (transport) => {
      const client = createBanking(options(transport));

      return {
        page: (page) => client.batchPage(page),
        facets: (facets) => client.batchFacets(facets),
        count: (count) => client.batchCount(count),
      };
    },
  },
  {
    label: "time rates",
    searchable: true,

    fn: "page_time_rates",
    sort: "rate",
    filter: "currency",
    facet: "currency",
    list: (transport) => {
      const client = createBillableTime(options(transport));

      return {
        page: (page) => client.ratePage(page),
        facets: (facets) => client.rateFacets(facets),
        count: (count) => client.rateCount(count),
      };
    },
  },
  {
    label: "expense categories",
    searchable: true,
    fn: "page_expense_categories",
    sort: "createdAt",
    filter: "currency",
    facet: "currency",
    list: (transport) => {
      const client = createExpenses(options(transport));

      return {
        page: (page) => client.categoryPage(page),
        facets: (facets) => client.categoryFacets(facets),
        count: (count) => client.categoryCount(count),
      };
    },
  },
  {
    label: "expense reports",
    searchable: true,
    fn: "page_expense_reports",
    sort: "title",
    filter: "status",
    facet: "status",
    list: (transport) => {
      const client = createExpenses(options(transport));

      return {
        page: (page) => client.reportPage(page),
        facets: (facets) => client.reportFacets(facets),
        count: (count) => client.reportCount(count),
      };
    },
  },
  {
    label: "expenses",
    searchable: true,
    fn: "page_expenses",
    sort: "amount",
    filter: "status",
    facet: "status",
    list: (transport) => {
      const client = createExpenses(options(transport));

      return {
        page: (page) => client.expensePage(page),
        facets: (facets) => client.expenseFacets(facets),
        count: (count) => client.expenseCount(count),
      };
    },
  },
  {
    label: "invoices",
    searchable: true,
    fn: "page_invoices",
    sort: "dueOn",
    filter: "status",
    facet: "status",
    list: (transport) => {
      const client = createInvoices(options(transport));

      return {
        page: (page) => client.page(page),
        facets: (facets) => client.facets(facets),
        count: (count) => client.count(count),
      };
    },
  },
  {
    label: "score models",
    searchable: true,
    fn: "page_score_models",
    sort: "version",
    filter: "subjectType",
    facet: "subjectType",
    list: (transport) => {
      const client = createScores(options(transport));

      return {
        page: (page) => client.modelPage(page),
        facets: (facets) => client.modelFacets(facets),
        count: (count) => client.modelCount(count),
      };
    },
  },
];

describe.each(CASES)("list surface client of $label", (spec) => {
  it("pages with a sort, a list filter and a cursor", async () => {
    const transport = fieldsTransport({
      [spec.fn]: () => ({ items: [], hasMore: true, nextCursor: ["a", "b"] }),
    });

    const page = await spec
      .list(transport)
      .page({
        limit: 5,
        after: ["x", "y"],
        sort: { by: spec.sort, direction: "asc" },
        filters: { [spec.filter]: ["one", "two"] },
      })
      .orThrow();

    expect(page).toEqual({
      items: [],
      hasMore: true,
      nextCursor: ["a", "b"],
      sorted: { applied: [{ by: spec.sort, direction: "asc" }], ignored: [] },
    });

    expect(transport.calls).toEqual([
      [
        spec.fn,
        {
          tenant: "org-1",
          filters: {
            sort: spec.sort,
            direction: "asc",
            [spec.filter]: ["one", "two"],
            after: ["x", "y"],
            limit: 5,
            paged: true,
          },
        },
      ],
    ]);
  });

  it("counts a facet under the page filters", async () => {
    const transport = fieldsTransport({
      [spec.fn]: () => ({
        facet: spec.facet,
        values: [{ value: "a", count: { value: 2, exact: true } }],
      }),
    });

    await expect(
      spec
        .list(transport)
        .facets({ facets: [spec.facet], filters: { [spec.filter]: ["one"] } })
        .orThrow(),
    ).resolves.toEqual([
      {
        facet: spec.facet,
        values: [{ value: "a", count: { value: 2, exact: true } }],
      },
    ]);

    expect(transport.calls).toEqual([
      [
        spec.fn,
        {
          tenant: "org-1",
          filters: { [spec.filter]: ["one"], facet: spec.facet },
        },
      ],
    ]);
  });

  it("sends the text search of a searchable entity", async () => {
    if (spec.searchable !== true) {
      return;
    }

    const transport = fieldsTransport({
      [spec.fn]: () => ({ items: [], hasMore: false }),
    });

    await spec.list(transport).page({ q: "text" }).orThrow();

    expect(transport.calls[0]?.[1]).toMatchObject({
      filters: { search: "text" },
    });
  });

  it("counts the rows that match", async () => {
    const transport = fieldsTransport({
      [spec.fn]: () => ({ value: 7, exact: false }),
    });

    await expect(
      spec
        .list(transport)
        .count({ filters: { [spec.filter]: ["one"] } })
        .orThrow(),
    ).resolves.toEqual({ value: 7, exact: false });

    expect(transport.calls).toEqual([
      [
        spec.fn,
        { tenant: "org-1", filters: { [spec.filter]: ["one"], count: true } },
      ],
    ]);
  });

  it("rejects a sort, filter, facet or text the entity does not declare", async () => {
    const transport = fieldsTransport({});
    const list = spec.list(transport);

    const results = [
      await list.page({ sort: { by: "colour" } }),
      await list.page({ filters: { colour: ["red"] } }),
      await list.facets({ facets: ["colour"] }),
      ...(spec.searchable === true ? [] : [await list.page({ q: "text" })]),
    ];

    for (const result of results) {
      expect(result.ok).toBe(false);
      expect(result.error?.kind).toBe("invalid_input");
    }

    expect(transport.calls).toEqual([]);
  });
});
