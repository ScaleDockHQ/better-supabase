import { describe, expect, it } from "vitest";

import * as client from "../../../../src/blocks/inbox/react/index.ts";
import * as server from "../../../../src/blocks/inbox/react/server.ts";
import * as chatClient from "../../../../src/chat-sdk/react/index.ts";
import * as chatServer from "../../../../src/chat-sdk/react/server.ts";

const load = async () => [];

describe("inbox react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
    expect(Object.keys(chatServer).toSorted()).toEqual(
      Object.keys(chatClient).toSorted(),
    );
  });

  it("throws from every hook", () => {
    expect(() => server.useInbox({ organizationId: null, load })).toThrow(
      "useInbox() runs in Client Components only",
    );
    expect(() =>
      server.useConversation({ conversationId: null, load }),
    ).toThrow("useConversation() runs in Client Components only");
    expect(() =>
      server.useInboxWidget({
        open: async () => "",
        send: async () => undefined,
        load,
      }),
    ).toThrow("useInboxWidget() runs in Client Components only");
  });
});
