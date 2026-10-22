import { describe, expect, it } from "vitest";

import * as client from "../../../../src/blocks/messaging/react/index.ts";
import * as server from "../../../../src/blocks/messaging/react/server.ts";

describe("messaging react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from every hook", () => {
    expect(() => server.useMessages({ conversationId: null })).toThrow(
      "useMessages() runs in Client Components only",
    );
    expect(() => server.useConversations()).toThrow(
      "useConversations() runs in Client Components only",
    );
  });
});
