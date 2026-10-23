import { describe, expect, it } from "vitest";

import { migrateCliCall, movedCommand } from "../../../src/cli/core/moved.ts";

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
    ).toEqual(["gen", "--only=types,client", "--out", "src/lib"]);
    expect(
      migrateCliCall(["skills", "install", "--agent", "cursor,claude"]),
    ).toEqual(["skills", "install", "--for", "cursor,claude"]);
    expect(migrateCliCall(["sql", "add", "tenant", "--force"])).toEqual([
      "add",
      "tenant",
      "--force",
    ]);
  });

  it("expands a flag that became a flag and a value", () => {
    expect(migrateCliCall(["doctor", "--strict"])).toEqual([
      "doctor",
      "--fail-on",
      "warning",
    ]);
    expect(migrateCliCall(["env", "--print"])).toEqual([
      "dev",
      "env",
      "--out",
      "-",
    ]);
  });

  it("folds the 0.15 commands into add, upgrade, gen, db and dev", () => {
    expect(migrateCliCall(["apply", "--preset", "saas"])).toEqual([
      "add",
      "--preset",
      "saas",
    ]);
    expect(migrateCliCall(["adopt", "teams", "--from", "a"])).toEqual([
      "add",
      "--adopt",
      "teams",
      "--tables",
      "a",
    ]);
    expect(migrateCliCall(["sql", "sync", "--check"])).toEqual([
      "upgrade",
      "--check",
    ]);
    expect(migrateCliCall(["introspect", "--format", "snapshot"])).toEqual([
      "gen",
      "--save-snapshot",
      "--kind",
      "snapshot",
    ]);
    expect(migrateCliCall(["stack", "prune"])).toEqual([
      "dev",
      "stack",
      "prune",
    ]);
  });

  it("leaves current calls and flags after -- alone", () => {
    expect(migrateCliCall(["doctor", "--fail-on", "warning"])).toBeUndefined();
    expect(migrateCliCall(["gen", "--only", "types"])).toBeUndefined();
    expect(migrateCliCall(["exec", "--", "--strict"])).toBeUndefined();
    expect(migrateCliCall(["--cwd", "app", "doctor"])).toBeUndefined();
  });
});

describe("movedCommand", () => {
  it("names what replaces a removed command", () => {
    const error = movedCommand(["scaffold", "screens", "tasks"]);

    expect(error?.code).toBe("unknown_command");
    expect(error?.message).toContain('"scaffold screens" was removed in 0.15');
    expect(movedCommand(["scaffold", "api"])).toBeUndefined();
  });
});
