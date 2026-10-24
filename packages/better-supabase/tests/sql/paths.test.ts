import { describe, expect, it } from "vitest";

import { modulePath } from "../../src/sql/paths.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";

const path = (name: string): string => modulePath(SQL_MODULES[name]!, {});

const schemaModules = Object.values(SQL_MODULES).filter(
  (module) => module.target !== "test",
);

describe("modulePath", () => {
  it("pads positions to 3 digits", () => {
    for (const module of schemaModules) {
      expect(path(module.name)).toMatch(
        /^supabase\/schemas\/900_better_supabase_\d{3}_[a-z0-9_]+\.sql$/,
      );
    }
  });

  it("sorts modules that share a position by name, ahead of their before module", () => {
    const ahead = schemaModules.filter((module) => module.before !== undefined);

    expect(ahead.length).toBeGreaterThan(0);

    expect(
      ahead.filter((module) => path(module.name) > path(module.before!)),
    ).toEqual([]);

    const shared = ahead.filter((module) => module.before === "comments");

    expect(shared.map((module) => module.name).toSorted()).toEqual([
      "drive",
      "guests",
    ]);
    expect(path("drive") < path("guests")).toBe(true);
  });
});
