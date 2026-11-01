import { describe, expect, it } from "vitest";

import { ltiHasRole } from "../../src/blocks/courses/lti.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

describe(`IMS LTI ${SPEC_PINS.lti}`, () => {
  it("accepts the 1.3 role vocabulary, long and short", () => {
    expect(SPEC_PINS.lti).toBe("1.3");
    expect(
      ltiHasRole(
        ["http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"],
        "Instructor",
      ),
    ).toBe(true);
    expect(
      ltiHasRole(
        [
          "http://purl.imsglobal.org/vocab/lis/v2/institution/person#Administrator",
        ],
        "Administrator",
      ),
    ).toBe(true);
    expect(ltiHasRole(["Learner"], "Learner")).toBe(true);
    expect(
      ltiHasRole(
        ["http://purl.imsglobal.org/vocab/lis/v2/membership#Mentor"],
        "Learner",
      ),
    ).toBe(false);
  });
});
