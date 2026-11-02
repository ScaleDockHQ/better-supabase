import { describe, expect, it } from "vitest";

import {
  C2PA_AI_SOURCE_TYPES,
  c2paIsAiGenerated,
} from "../../src/blocks/dam/c2pa.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

describe(`C2PA ${SPEC_PINS.c2pa}`, () => {
  it("treats the IPTC digital source types of generated media as AI", () => {
    expect(SPEC_PINS.c2pa).toBe("2.2");
    expect(
      C2PA_AI_SOURCE_TYPES.every((iri) =>
        iri.startsWith("http://cv.iptc.org/newscodes/digitalsourcetype/"),
      ),
    ).toBe(true);

    for (const digitalSourceType of C2PA_AI_SOURCE_TYPES) {
      expect(
        c2paIsAiGenerated({
          valid: true,
          validationErrors: [],
          ingredients: [],
          actions: [{ action: "c2pa.created", digitalSourceType }],
        }),
      ).toBe(true);
    }

    expect(
      c2paIsAiGenerated({
        valid: true,
        validationErrors: [],
        ingredients: [],
        actions: [
          {
            action: "c2pa.created",
            digitalSourceType:
              "http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture",
          },
        ],
      }),
    ).toBe(false);
  });
});
