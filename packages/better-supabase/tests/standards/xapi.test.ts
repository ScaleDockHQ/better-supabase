import { describe, expect, it } from "vitest";

import {
  XAPI_VERBS,
  XAPI_VERSION,
  xapiStatement,
} from "../../src/blocks/courses/xapi.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

describe(`xAPI ${SPEC_PINS.xapi}`, () => {
  it("sends the pinned version and ADL verb IRIs", () => {
    expect(XAPI_VERSION).toBe(SPEC_PINS.xapi);
    expect(
      Object.values(XAPI_VERBS).every((iri) =>
        iri.startsWith("http://adlnet.gov/expapi/verbs/"),
      ),
    ).toBe(true);
  });

  it("writes the required statement properties", () => {
    const result = xapiStatement({
      actor: { homePage: "https://app.example", name: "u" },
      verb: "completed",
      object: { id: "https://app.example/c" },
    });

    expect(result.ok && Object.keys(result.data).toSorted()).toEqual([
      "actor",
      "id",
      "object",
      "timestamp",
      "verb",
    ]);
    expect(result.ok && result.data.actor["objectType"]).toBe("Agent");
    expect(result.ok && result.data.object["objectType"]).toBe("Activity");
  });
});
