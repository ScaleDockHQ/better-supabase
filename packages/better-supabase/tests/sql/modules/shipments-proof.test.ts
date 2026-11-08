import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const sqlOf = (names: readonly string[]): string =>
  renderBlocks([...names])
    .filter((file) => file.module === "shipments")
    .map((file) => file.contents)
    .join("\n");

describe("proof of delivery", () => {
  const sql = sqlOf(["shipments"]);

  it("adds the proof columns and a set-once function", () => {
    for (const fragment of [
      'add column "delivered_to" text',
      'add column "proof_recorded_at" timestamptz',
      '"record_delivery_proof"',
      "SHIPMENT_NOT_DELIVERED",
      "SHIPMENT_PROOF_RECORDED",
    ]) {
      expect(sql).toContain(fragment);
    }
  });

  it("refuses edits and deletes of tracking events", () => {
    expect(sql).toContain("SHIPMENT_EVENTS_APPEND_ONLY");
    expect(sql).toContain("before update or delete on");
  });
});
