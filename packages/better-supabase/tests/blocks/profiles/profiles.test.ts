import * as v from "valibot";
import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/blocks/profiles/index.ts";

import { createProfiles } from "../../../src/blocks/profiles/index.ts";
import { dbError } from "../../../src/core/errors.ts";

function fake(results: Record<string, unknown>): BlockTransport {
  return {
    call(_schema, fn) {
      const value = results[fn];
      return value instanceof Error
        ? Promise.reject(value)
        : Promise.resolve(value ?? null);
    },
  };
}

describe("createProfiles", () => {
  it("reads and updates the caller's profile", async () => {
    const profiles = createProfiles({
      transport: fake({
        my_profile: { full_name: "Ada", email: "ada@example.com" },
        update_my_profile: true,
      }),
    });
    expect(await profiles.mine().orThrow()).toEqual({
      full_name: "Ada",
      email: "ada@example.com",
    });
    expect(
      await profiles.updateMine({ full_name: "Ada Lovelace" }).orThrow(),
    ).toBe(true);
  });

  it("types, parses and validates the fields the app adds", async () => {
    const calls: unknown[] = [];
    const profiles = createProfiles({
      transport: {
        call(_schema, fn, args) {
          calls.push([fn, args]);
          return Promise.resolve(
            fn === "my_profile"
              ? { id: "u1", locale: "nl", marketing_opt_in: "true" }
              : true,
          );
        },
      },
      fields: v.object({
        locale: v.picklist(["en", "nl"]),
        marketing_opt_in: v.pipe(
          v.picklist(["true", "false"]),
          v.transform((value) => value === "true"),
        ),
      }),
    });
    const mine = await profiles.mine().orThrow();
    expect(mine).toEqual({ id: "u1", locale: "nl", marketing_opt_in: true });
    expect(mine?.locale).toBe("nl");

    const bad = await profiles.updateMine({ locale: "fr" as "en" });
    expect(bad).toMatchObject({ ok: false, error: { kind: "validation" } });
    expect(calls).toHaveLength(1);

    expect(await profiles.updateMine({ locale: "en" }).orThrow()).toBe(true);
    expect(calls[1]).toEqual([
      "update_my_profile",
      { attrs: { locale: "en" } },
    ]);
  });

  it("runs hooks around its methods", async () => {
    const profiles = createProfiles({
      transport: fake({ update_my_profile: true }),
      hooks: {
        updateMine: {
          before: ([attrs]) =>
            "email" in attrs
              ? dbError("forbidden", "Change the email through auth")
              : undefined,
        },
      },
    });
    expect(
      await profiles.updateMine({ email: "new@example.com" }),
    ).toMatchObject({ ok: false, error: { kind: "forbidden" } });
  });
});
