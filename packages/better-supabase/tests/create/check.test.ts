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
    const expected = { ok: true, design: DESIGN, fitsUrl: true, code };

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
          code: "unknown_key",
          path: "/tables",
          table: "design",
          message:
            'design: unknown key "tables"; a design has appTables, extraColumns and positions',
        },
      ],
    });
    expect(await checkDesign("hello", SAAS)).toMatchObject({
      ok: false,
      issues: [{ code: "invalid_code", path: "", table: "design" }],
    });
    expect(await checkDesign(DESIGN, "not-a-preset")).toMatchObject({
      ok: false,
      issues: [{ code: "invalid_preset", path: "", table: "preset" }],
    });
  });

  it("points a parse issue at the app table it is in", async () => {
    expect(
      await checkDesign(
        { appTables: { tasks: { columns: { title: { type: "money" } } } } },
        SAAS,
      ),
    ).toMatchObject({
      ok: false,
      issues: [
        {
          code: "invalid_app_table",
          path: "/appTables/tasks/columns/title/type",
          table: "tasks",
        },
      ],
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
    expect(result.ok ? [] : result.issues).toEqual([
      {
        code: "table_name_taken",
        path: "/appTables/profiles",
        table: "profiles",
        message: "A block already creates a profiles table. Rename this one.",
      },
      {
        code: "missing_reference",
        path: "/appTables/tasks/columns/booking_id/references",
        table: "tasks",
        message:
          "tasks.booking_id references bookings.bookings, which the preset does not install.",
      },
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
          code: "block_not_installed",
          path: "/extraColumns/organizations",
          table: "organizations",
          message: expect.stringContaining(
            "the preset doesn't install the organizations block",
          ),
        },
      ],
    });
  });

  it("passes a design too long for a URL with fitsUrl false", async () => {
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
      fitsUrl: false,
      code: null,
    });
  });
});
