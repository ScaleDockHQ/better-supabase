import { describe, expect, it } from "vitest";

import { migrateCliCall } from "../../../src/cli/core/moved.ts";

describe("migrateCliCall", () => {
  it("moves openapi into spec emit and spec check into emit --check", () => {
    expect(migrateCliCall(["openapi", "emit", "--out", "api.json"])).toEqual([
      "spec",
      "emit",
      "openapi",
      "--out",
      "api.json",
    ]);
    expect(migrateCliCall(["spec", "check"])).toEqual([
      "spec",
      "emit",
      "--check",
    ]);
  });

  it("renames every moved flag of a command, keeping values", () => {
    expect(
      migrateCliCall(["gen", "--tasks=types,client", "--out", "src/lib"]),
    ).toEqual(["gen", "--only=types,client", "--out-dir", "src/lib"]);
    expect(
      migrateCliCall(["skills", "install", "--agent", "cursor,claude"]),
    ).toEqual(["skills", "install", "--for", "cursor,claude"]);
    expect(migrateCliCall(["sql", "add", "tenant", "--force"])).toEqual([
      "sql",
      "add",
      "tenant",
      "--allow-hook-overlap",
    ]);
  });

  it("expands a flag that became a flag and a value", () => {
    expect(migrateCliCall(["doctor", "--strict"])).toEqual([
      "doctor",
      "--fail-on",
      "warning",
    ]);
    expect(migrateCliCall(["env", "--print"])).toEqual(["env", "--out", "-"]);
  });

  it("leaves current calls and flags after -- alone", () => {
    expect(migrateCliCall(["doctor", "--fail-on", "warning"])).toBeUndefined();
    expect(migrateCliCall(["gen", "--only", "types"])).toBeUndefined();
    expect(migrateCliCall(["exec", "--", "--strict"])).toBeUndefined();
    expect(migrateCliCall(["--cwd", "app", "doctor"])).toBeUndefined();
  });
});
