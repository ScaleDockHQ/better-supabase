import { describe, expect, it } from "vitest";

import {
  OPEN_BADGES_CONTEXT,
  openBadgeCredential,
} from "../../src/blocks/courses/open-badges.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

describe(`Open Badges ${SPEC_PINS.openBadges}`, () => {
  it("uses the VC 2.0 and Open Badges 3.0 contexts in order", async () => {
    expect(OPEN_BADGES_CONTEXT[0]).toBe("https://www.w3.org/ns/credentials/v2");
    expect(OPEN_BADGES_CONTEXT[1]).toContain(
      `context-${SPEC_PINS.openBadges}.json`,
    );

    const credential = await openBadgeCredential({
      id: "urn:uuid:1",
      issuer: { id: "https://i.example", name: "I" },
      achievement: {
        id: "https://i.example/a",
        name: "A",
        description: "d",
        criteria: "c",
      },
      recipient: { email: "a@example.com" },
      awardedAt: new Date("2026-01-01T00:00:00Z"),
    });

    expect(credential.type).toContain("OpenBadgeCredential");
    expect(credential.issuer["type"]).toEqual(["Profile"]);
    expect(credential.credentialSubject["type"]).toEqual([
      "AchievementSubject",
    ]);
  });
});
