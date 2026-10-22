import { describe, expect, it } from "vitest";

import type { StandardSchemaV1 } from "../../src/core/standard.ts";

import {
  SUBJECT_PRESENCE_TEMPLATE,
  subjectPresence,
  subjectPresenceTopic,
  subjectPresenceValues,
} from "../../src/realtime/index.ts";

const state: StandardSchemaV1<unknown, { name: string }> = {
  "~standard": {
    version: 1,
    vendor: "test",
    validate: (value) => ({ value: value as { name: string } }),
  },
};

describe("subject presence", () => {
  it("names one presence topic per record", () => {
    expect(SUBJECT_PRESENCE_TEMPLATE).toBe(
      "presence:{subjectType}:{subjectId}",
    );
    expect(
      subjectPresence.topic({ subjectType: "conversation", subjectId: "c1" }),
    ).toBe("presence:conversation:c1");
    expect(subjectPresence.presence).toBe(true);
    expect(subjectPresence.presenceSchema).toBeUndefined();
  });

  it("validates the tracked states with a schema", () => {
    const topic = subjectPresenceTopic(state);

    expect(topic.presence).toBe(true);
    expect(topic.presenceSchema).toBe(state);
  });

  it("turns a subject into topic values, and none into null", () => {
    expect(subjectPresenceValues({ type: "deal", id: "d1" })).toEqual({
      subjectType: "deal",
      subjectId: "d1",
    });
    expect(subjectPresenceValues(null)).toBeNull();
    expect(subjectPresenceValues(undefined)).toBeNull();
  });
});
