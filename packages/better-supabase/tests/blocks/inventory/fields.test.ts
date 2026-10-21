import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { createInventory } from "../../../src/blocks/inventory/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const Fields = v.object({ timezone: v.pipe(v.string(), v.minLength(3)) });

describe("inventory fields", () => {
  it("sends a location's fields and parses them back", async () => {
    const t = fieldsTransport({
      save_location: () => ({
        id: "l1",
        code: "WH-1",
        active: true,
        fields: { timezone: "Europe/Amsterdam" },
      }),
    });

    const inventory = createInventory({ transport: t, fields: Fields });

    const saved = await inventory
      .saveLocation("o", {
        code: "WH-1",
        name: "Main",
        fields: { timezone: "Europe/Amsterdam" },
      })
      .orThrow();

    expect(saved.fields?.timezone).toBe("Europe/Amsterdam");
    expect(t.calls[0]?.[1]["fields"]).toEqual({ timezone: "Europe/Amsterdam" });
  });

  it("refuses a bad field before the call", async () => {
    const t = fieldsTransport({});

    const saved = await createInventory({
      transport: t,
      fields: Fields,
    }).saveLocation("o", {
      code: "WH-1",
      name: "Main",
      fields: { timezone: "" },
    });

    expect(saved.ok ? undefined : saved.error.kind).toBe("validation");
    expect(t.calls).toEqual([]);
  });
});
