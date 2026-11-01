import { describe, expect, it } from "vitest";

import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { createCdsHooksServer } from "../../src/fhir/cds-hooks.ts";

describe(`CDS Hooks ${SPEC_PINS.cdsHooks}`, () => {
  it("answers discovery with hook, id and description, and cards with the required fields", async () => {
    const handle = createCdsHooksServer({
      services: [
        {
          apiVersion: 1,
          id: "s",
          hook: "patient-view",
          description: "d",
          handle: async () => ({
            cards: [
              { summary: "x", indicator: "info", source: { label: "src" } },
            ],
          }),
        },
      ],
    });

    const discovery = (await (
      await handle(new Request("https://c.example/cds-services"))
    ).json()) as { services: Record<string, unknown>[] };

    expect(Object.keys(discovery.services[0] ?? {}).toSorted()).toEqual([
      "description",
      "hook",
      "id",
    ]);

    const response = await handle(
      new Request("https://c.example/cds-services/s", {
        method: "POST",
        body: JSON.stringify({
          hook: "patient-view",
          hookInstance: "i",
          context: {},
        }),
      }),
    );

    expect(response.headers.get("content-type")).toBe("application/json");
    expect(await response.json()).toEqual({
      cards: [{ summary: "x", indicator: "info", source: { label: "src" } }],
    });
  });
});
