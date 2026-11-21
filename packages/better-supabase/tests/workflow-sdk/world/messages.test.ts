import { describe, expect, it } from "vitest";

import {
  backoffSeconds,
  byPrefix,
  isStoredMessage,
  runIdOf,
  serialize,
} from "../../../src/workflow-sdk/world/messages.ts";

describe("serialize", () => {
  it("writes a Uint8Array as a tagged base64 object", () => {
    expect(
      JSON.parse(serialize({ data: new Uint8Array([1, 2, 3]) }).toString()),
    ).toEqual({ data: { __type: "Uint8Array", data: "AQID" } });
  });
});

describe("isStoredMessage and runIdOf", () => {
  const message = {
    queueName: "q",
    messageId: "m",
    attempt: 1,
    body: Buffer.from('{"runId":"wrun_1"}').toString("base64"),
  };

  it("accepts only a complete stored message", () => {
    expect(isStoredMessage(message)).toBe(true);
    expect(isStoredMessage({ ...message, attempt: "1" })).toBe(false);
    expect(isStoredMessage(null)).toBe(false);
  });

  it("reads the run the body names", () => {
    expect(runIdOf(message)).toBe("wrun_1");
    expect(runIdOf({ ...message, body: "!!" })).toBeUndefined();
  });
});

describe("backoffSeconds", () => {
  it("grows as e to the attempt and stops at attempt 10", () => {
    expect(backoffSeconds(1)).toBe(3);
    expect(backoffSeconds(10)).toBe(backoffSeconds(40));
  });
});

describe("byPrefix", () => {
  it("picks the longest prefix the queue name starts with", () => {
    const entries = new Map([
      ["__wkf_workflow_" as never, "flow"],
      ["__wkf_workflow_special_" as never, "special"],
    ]);

    expect(byPrefix(entries, "__wkf_workflow_special_a")).toBe("special");
    expect(byPrefix(entries, "__wkf_workflow_a")).toBe("flow");
    expect(byPrefix(entries, "__other")).toBeUndefined();
  });
});
