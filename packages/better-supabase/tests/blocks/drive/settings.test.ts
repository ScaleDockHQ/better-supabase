import { describe, expect, it } from "vitest";

import {
  driveSettings,
  driveSharingSchema,
} from "../../../src/blocks/drive/index.ts";

describe("driveSettings", () => {
  const validate = (value: unknown) =>
    driveSharingSchema["~standard"].validate(value);

  it("declares drive.sharing with its default and JSON Schema", () => {
    const entry = driveSettings.schemas.organization["drive.sharing"];
    expect(entry.default).toEqual({ guests: true, links: "anyone" });
    expect(driveSharingSchema["~standard"].jsonSchema.input()).toMatchObject({
      type: "object",
      required: ["guests", "links"],
    });
    expect(driveSharingSchema["~standard"].jsonSchema.output()).toMatchObject({
      properties: { links: { enum: ["anyone", "organization", "none"] } },
    });
  });

  it("accepts a sharing policy and rejects anything else", () => {
    expect(validate({ guests: false, links: "none", extra: 1 })).toEqual({
      value: { guests: false, links: "none" },
    });

    for (const value of [
      null,
      { guests: "no", links: "anyone" },
      { guests: true, links: "public" },
    ]) {
      expect(validate(value)).toHaveProperty("issues");
    }
  });
});
