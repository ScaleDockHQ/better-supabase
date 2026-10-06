import { describe, expect, it } from "vitest";

import * as client from "../../../../src/blocks/announcements/react/index.ts";
import * as server from "../../../../src/blocks/announcements/react/server.ts";

describe("announcements react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from useAnnouncements", () => {
    expect(() => server.useAnnouncements()).toThrow(
      "useAnnouncements() runs in Client Components only",
    );
  });
});
