import { describe, expect, it } from "vitest";

import { checkDesign } from "../../src/create/index.ts";
import {
  type CreateDesign,
  encodeDesign,
  encodePreset,
  namedPreset,
} from "../../src/preset/index.ts";

const SAAS = encodePreset(namedPreset("saas"));

const DESIGN: CreateDesign = {
  appTables: {
    projects: { columns: { title: { type: "text", nullable: false } } },
  },
};

describe("checkDesign", () => {
  it("accepts a design object, a code and a /create URL alike", async () => {
    const code = await encodeDesign(DESIGN);
    const expected = { ok: true, design: DESIGN, code };

    expect(await checkDesign(DESIGN, SAAS)).toEqual(expected);
    expect(await checkDesign(code, SAAS)).toEqual(expected);
    expect(
      await checkDesign(
        `https://app.bettersupabase.com/create?preset=${SAAS}&design=${code}`,
        "saas",
      ),
    ).toEqual(expected);
  });

  it("reports a malformed design or preset as an issue", async () => {
    expect(await checkDesign({ tables: {} }, SAAS)).toEqual({
      ok: false,
      issues: [
        {
          table: "design",
          message:
            'design: unknown key "tables"; a design has appTables, extraColumns and positions',
        },
      ],
    });
    expect(await checkDesign("hello", SAAS)).toMatchObject({
      ok: false,
      issues: [{ table: "design" }],
    });
    expect(await checkDesign(DESIGN, "not-a-preset")).toMatchObject({
      ok: false,
      issues: [{ table: "preset" }],
    });
  });

  it("reports what the canvas and sql sync refuse", async () => {
    const result = await checkDesign(
      {
        appTables: {
          profiles: { columns: { bio: { type: "text" } } },
          tasks: {
            columns: {
              booking_id: {
                type: "uuid",
                references: { block: "bookings", table: "bookings" },
              },
            },
          },
        },
      },
      SAAS,
    );

    expect(result.ok).toBe(false);
    expect(
      result.ok ? [] : result.issues.map((issue) => issue.message),
    ).toEqual([
      "A block already creates a profiles table. Rename this one.",
      "tasks.booking_id references bookings.bookings, which the preset does not install.",
    ]);
  });

  it("reports extra columns for a block the preset doesn't install", async () => {
    expect(
      await checkDesign(
        { extraColumns: { organizations: { tier: "text" } } },
        "minimal",
      ),
    ).toMatchObject({
      ok: false,
      issues: [
        {
          table: "design",
          message: expect.stringContaining(
            "the preset doesn't install the organizations block",
          ),
        },
      ],
    });
  });

  it("passes a design too long for a URL with a null code", async () => {
    let seed = 11;

    const word = (): string => {
      seed = (seed * 48_271) % 2_147_483_647;

      return seed.toString(36);
    };

    const appTables = Object.fromEntries(
      Array.from({ length: 100 }, (_, index) => [
        `table_${String(index)}_${word()}_${word()}`,
        {
          columns: Object.fromEntries(
            Array.from({ length: 6 }, (__, column) => [
              `c${String(column)}_${word()}${word()}`,
              { type: "text" as const },
            ]),
          ),
        },
      ]),
    );

    expect(await checkDesign({ appTables }, SAAS)).toMatchObject({
      ok: true,
      code: null,
    });
  });
});
