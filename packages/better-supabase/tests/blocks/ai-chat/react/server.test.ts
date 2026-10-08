import { describe, expect, it } from "vitest";

import * as client from "../../../../src/blocks/ai-chat/react/index.ts";
import * as server from "../../../../src/blocks/ai-chat/react/server.ts";

describe("ai-chat react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from every hook", () => {
    expect(() => server.useAiChats()).toThrow(
      "useAiChats() runs in Client Components only",
    );
    expect(() => server.useAiChatTree("c1")).toThrow(
      "useAiChatTree() runs in Client Components only",
    );
    expect(() => server.useAiModels()).toThrow(
      "useAiModels() runs in Client Components only",
    );
    expect(() => server.useAiShare("c1")).toThrow(
      "useAiShare() runs in Client Components only",
    );
  });
});
