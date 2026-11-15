import { describe, expect, it } from "vitest";

import { createFilespace } from "../../../src/blocks/filespace/filespace.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult } from "../../../src/core/result.ts";

describe("filespace.bulkShare", () => {
  it("shares one node per principal and reports each as type:id", async () => {
    const shared: string[] = [];

    const drive = {
      share: ({ id, principal }: { id: string; principal: { id: string } }) => {
        shared.push(`${id}:${principal.id}`);

        return principal.id === "t1"
          ? AsyncResult.err(dbError("forbidden", "No"))
          : AsyncResult.ok({ id: "g" });
      },
    };

    const filespace = createFilespace({
      // SAFETY: the test fills only the part `bulkShare` reads.
      parts: { drive, "share-links": {} } as never,
    } as never);

    const report = await filespace
      .bulkShare({
        id: "n1",
        principals: [
          { principal: { type: "user", id: "u1" }, role: "viewer" },
          { principal: { type: "team", id: "t1" }, role: "editor" },
        ],
      })
      .orThrow();

    expect(shared).toEqual(["n1:u1", "n1:t1"]);
    expect(report.succeeded).toEqual(["user:u1"]);
    expect(report.failed.map((f) => f.id)).toEqual(["team:t1"]);
  });
});
