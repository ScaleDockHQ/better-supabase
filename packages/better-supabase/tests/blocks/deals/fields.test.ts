import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { createDeals } from "../../../src/blocks/deals/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const ROW = {
  id: "d1",
  tenant_id: "o",
  number: 1,
  identifier: "DEAL-1",
  name: "Growth",
  amount: 0,
  existing_amount: 0,
  currency: "EUR",
  value_period: "one_time",
  amount_source: "manual",
  outcome: "open",
  opened_on: "2026-10-01",
  expected_close_on: "2026-11-30",
  push_count: 0,
  flags: [],
  locked: false,
  rank: "V",
  archived_at: null,
  created_at: "2026-10-01T09:00:00Z",
  updated_at: "2026-10-01T09:00:00Z",
  contacts: [],
  members: [],
  region: "emea",
};

const Fields = v.object({ region: v.picklist(["emea", "amer", "apac"]) });

describe("deals fields", () => {
  it("writes the extra fields by column name and parses them back", async () => {
    const t = fieldsTransport({ create_deal: () => ROW });
    const deals = createDeals({ transport: t, fields: Fields });
    const deal = await deals
      .create("o", {
        name: "Growth",
        closeOn: Temporal.PlainDate.from("2026-11-30"),
        fields: { region: "emea" },
      })
      .orThrow();
    expect(deal.fields.region).toBe("emea");
    expect(t.calls[0]?.[1]["attrs"]).toEqual({
      name: "Growth",
      closeOn: "2026-11-30",
      region: "emea",
    });
  });

  it("checks extra-column cell edits and leaves the built-in ones to the database", async () => {
    const t = fieldsTransport({
      update_deals: () => ({ accepted: [], rejected: [] }),
    });
    const deals = createDeals({ transport: t, fields: Fields });
    const refused = await deals.update([
      { dealId: "d1", field: "region", value: "mars" },
    ]);
    expect(refused.ok ? undefined : refused.error.kind).toBe("validation");
    expect(t.calls).toEqual([]);
    await deals
      .update([
        { dealId: "d1", field: "region", value: "apac" },
        { dealId: "d1", field: "name", value: "Renamed" },
      ])
      .orThrow();
    expect(t.calls[0]?.[0]).toBe("update_deals");
  });

  it("returns a validation error for a stored value the schema refuses", async () => {
    const t = fieldsTransport({ reopen_deal: () => ({ ...ROW, region: "x" }) });
    const reopened = await createDeals({ transport: t, fields: Fields }).reopen(
      "d1",
    );
    expect(reopened.ok ? undefined : reopened.error.kind).toBe("validation");
  });
});
