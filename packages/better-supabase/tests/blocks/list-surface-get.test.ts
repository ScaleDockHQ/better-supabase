import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";

import { createContacts } from "../../src/blocks/contacts/index.ts";
import { createContracts } from "../../src/blocks/contracts/index.ts";
import { createDeals } from "../../src/blocks/deals/index.ts";
import { createForecasts } from "../../src/blocks/forecasts/index.ts";
import { createMailSync } from "../../src/blocks/mail-sync/index.ts";
import { createPipelines } from "../../src/blocks/pipelines/index.ts";
import { createQuotes } from "../../src/blocks/quotes/index.ts";
import { createSegments } from "../../src/blocks/segments/index.ts";

// Every F3 get method answers a missing row with a `not_found` Result instead of
// throwing (architecture invariant 4).
const missing: BlockTransport = { call: () => Promise.resolve(null) };

const options = { transport: missing, tenant: "org-1" };
const ID = "00000000-0000-4000-8000-000000000001";

const contacts = createContacts(options);
const mailSync = createMailSync(options);

const GETS: readonly [string, () => PromiseLike<{ ok: boolean }>][] = [
  ["segments.getSegment", () => createSegments(options).getSegment(ID)],
  ["forecasts.get", () => createForecasts(options).get(ID)],
  ["pipelines.get", () => createPipelines(options).get(ID)],
  ["deals.get", () => createDeals(options).get(ID)],
  ["quotes.get", () => createQuotes(options).get(ID)],
  ["contracts.get", () => createContracts(options).get(ID)],
  ["contacts.companyById", () => contacts.companyById(ID)],
  ["contacts.personById", () => contacts.personById(ID)],
  ["mail-sync.getThread", () => mailSync.getThread(ID)],
  ["mail-sync.getAccount", () => mailSync.getAccount(ID)],
];

const NULL_ROW = new Set([
  "segments.getSegment",
  "contacts.companyById",
  "contacts.personById",
  "mail-sync.getThread",
  "mail-sync.getAccount",
]);

describe("F3 get methods", () => {
  it.each(GETS)(
    "%s returns a failed Result for a missing row",
    async (_label, run) => {
      const result = await run();

      expect(result.ok).toBe(false);
    },
  );

  it.each(GETS.filter(([label]) => NULL_ROW.has(label)))(
    "%s answers not_found when the function returns null",
    async (_label, run) => {
      expect(await run()).toMatchObject({ error: { kind: "not_found" } });
    },
  );
});
