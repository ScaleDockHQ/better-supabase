import { readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";

import { parseBlock, readBlocks, renderBindings, typeArgs } from "./render.ts";

describe("block bindings", () => {
  it("are up to date with the controllers (pnpm --filter better-supabase gen:bindings)", async () => {
    for (const file of await renderBindings()) {
      expect({
        path: file.path,
        contents: await readFile(file.path, "utf-8"),
      }).toEqual({ path: file.path, contents: file.contents });
    }
  });

  it("cover every controller factory", async () => {
    const hooks = (await readBlocks()).flatMap((block) =>
      block.controllers.map((binding) => binding.hook),
    );
    expect(hooks).toContain("useUndoStack");
    expect(hooks).toContain("useOnboarding");
    expect(new Set(hooks).size).toBe(hooks.length);
  });

  it("reads generics, env use and type sources", () => {
    const parsed = parseBlock(
      "probe",
      `import type { Scope } from "./scope.ts";
import type { Port } from "../../ports.ts";
export interface ProbeOptions<T extends Scope> extends BaseOptions {
  readonly value: T;
}
export interface BaseOptions {
  readonly auth: Port;
}
export interface ProbeSnapshot<T> {
  readonly value: T;
}
export type ProbeActions = object;
export type ProbeController<T extends Scope> = Controller<
  ProbeSnapshot<T>,
  ProbeActions
>;
export function createProbeController<
  T extends Scope,
>(options: ProbeOptions<T>): ProbeController<T> {
`,
    );
    expect(parsed.controllers).toEqual([
      {
        factory: "createProbeController",
        hook: "useProbe",
        generics: "<T extends Scope>",
        options: "ProbeOptions<T>",
        snapshot: "ProbeSnapshot<T>",
        actions: "ProbeActions",
        env: true,
      },
    ]);
    expect([...parsed.types]).toEqual([
      ["Scope", "../scope.ts"],
      ["ProbeOptions", "../client.ts"],
      ["ProbeSnapshot", "../client.ts"],
      ["ProbeActions", "../client.ts"],
    ]);
    expect(typeArgs("<T extends Scope, U>")).toBe("<T, U>");
    expect(typeArgs("")).toBe("");
    expect(() =>
      parseBlock(
        "lost",
        "export type LostController = Controller<Missing, object>;\nexport function createLostController(\n  options: LostOptions,\n): LostController {\n",
      ),
    ).toThrow(/can.t find where LostOptions comes from/);
    expect(() =>
      parseBlock(
        "bad",
        "export function createBadController(\n  options: BadOptions,\n): Bad {\n",
      ),
    ).toThrow(/not a Controller alias/);
  });
});
