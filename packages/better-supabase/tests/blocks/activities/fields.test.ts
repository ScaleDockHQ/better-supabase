import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { createActivities } from "../../../src/blocks/activities/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const ROW = {
  id: "e1",
  tenant_id: "o",
  type: "call",
  title: "Intro",
  subjects: [{ type: "deal", id: "d1" }],
  overdue: false,
  created_at: "2026-10-01T09:00:00Z",
  fields: { sentiment: "positive" },
};

const Fields = v.object({
  sentiment: v.picklist(["positive", "neutral", "negative"]),
});

describe("engagements fields", () => {
  it("sends the extra fields under fields and parses every read", async () => {
    const t = fieldsTransport({
      log_activity: () => ROW,
      activities_of: () => [ROW, ROW],
      next_activity: () => null,
    });

    const engagements = createActivities({ transport: t, fields: Fields });

    const logged = await engagements
      .log(
        "o",
        { type: "call", title: "Intro", fields: { sentiment: "positive" } },
        [{ type: "deal", id: "d1" }],
      )
      .orThrow();

    expect(logged.fields.sentiment).toBe("positive");
    expect(t.calls[0]?.[1]["attrs"]).toEqual({
      type: "call",
      title: "Intro",
      fields: { sentiment: "positive" },
    });
    const list = await engagements.of({ type: "deal", id: "d1" }).orThrow();
    expect(list.map((entry) => entry.fields.sentiment)).toEqual([
      "positive",
      "positive",
    ]);
    expect(
      await engagements.next({ type: "deal", id: "d1" }).orThrow(),
    ).toBeUndefined();
  });

  it("refuses a bad field before the call", async () => {
    const t = fieldsTransport({ update_activity: () => ROW });

    const updated = await createActivities({
      transport: t,
      fields: Fields,
    }).update("e1", { fields: { sentiment: "angry" as never } });

    expect(updated.ok ? undefined : updated.error.kind).toBe("validation");
    expect(t.calls).toEqual([]);
  });
});
