import { describe, expect, it } from "vitest";

import { careConnector } from "../src/care-sync.ts";

const unused = (): never => {
  throw new Error("not called");
};

describe("care sync", () => {
  it("builds a connector with a rejected store", async () => {
    const connector = careConnector({
      endpoint: "https://powersync.example.com",
      supabase: {
        auth: {
          getSession: () =>
            Promise.resolve({ data: { session: null }, error: null }),
        },
      },
      powersync: { getAll: unused, getOptional: unused } as never,
      activities: { log: unused, update: unused, remove: unused } as never,
      observations: { record: unused } as never,
      medications: {} as never,
    });

    expect(await connector.fetchCredentials()).toBeNull();
    expect(connector.rejected).toBeDefined();
  });
});
