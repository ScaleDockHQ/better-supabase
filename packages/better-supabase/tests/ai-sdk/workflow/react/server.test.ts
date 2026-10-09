import { describe, expect, it } from "vitest";

import * as client from "../../../../src/ai-sdk/workflow/react/index.ts";
import * as server from "../../../../src/ai-sdk/workflow/react/server.ts";

describe("ai-sdk/workflow/react react-server build", () => {
  it("exports the client entry's runtime names", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("explains that the durable hooks run in Client Components only", () => {
    const hint = /Client Components only/;
    expect(() =>
      server.durableTransport({
        api: "/api/chat",
        model: undefined,
        body: undefined,
        headers: undefined,
      }),
    ).toThrow(hint);
    expect(() => server.useDurableAssistant({ id: "c1" })).toThrow(hint);
  });
});
