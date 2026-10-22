import { describe, expect, it } from "vitest";

import * as client from "../../../../src/blocks/attachments/react/index.ts";
import * as server from "../../../../src/blocks/attachments/react/server.ts";

describe("attachments react-server build", () => {
  it("exports the same names as the client build", () => {
    expect(Object.keys(server).toSorted()).toEqual(
      Object.keys(client).toSorted(),
    );
  });

  it("throws from useAttachmentUpload", () => {
    expect(() =>
      server.useAttachmentUpload({ subject: { type: "customer", id: "c1" } }),
    ).toThrow("useAttachmentUpload() runs in Client Components only");
  });
});
