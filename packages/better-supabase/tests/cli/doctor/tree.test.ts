import { describe, expect, it } from "vitest";

import {
  callsAny,
  findLine,
  firstCallLine,
  hasDirective,
  hasWiredProperty,
  isCallOf,
  isMemberCall,
  isMethodCall,
  isModuleOf,
  isStringProperty,
  mentionsExactly,
  mentionsName,
  moduleSpecifiers,
} from "../../../src/cli/doctor/tree.ts";

describe("moduleSpecifiers", () => {
  it("lists imports, re-exports and dynamic imports, not comments or strings", () => {
    const text = [
      'import a from "./a";',
      '// import b from "./b";',
      'export * from "./c";',
      "const note = \"from './d'\";",
      'const load = () => import("./e");',
    ].join("\n");

    expect(moduleSpecifiers(text)).toEqual([
      { specifier: "./a", line: 1 },
      { specifier: "./c", line: 3 },
      { specifier: "./e", line: 5 },
    ]);
  });
});

describe("hasDirective", () => {
  it("reads the directive prologue only", () => {
    expect(hasDirective('"use strict";\n"use client";\n', "use client")).toBe(
      true,
    );
    expect(hasDirective('// "use client"\nexport {};', "use client")).toBe(
      false,
    );
    expect(
      hasDirective('import a from "a";\n"use client";', "use client"),
    ).toBe(false);
  });
});

describe("call helpers", () => {
  it("finds a call by name, with or without a receiver", () => {
    expect(firstCallLine("\nx.f();", "f")).toBe(2);
    expect(firstCallLine("// f()\nconst s = 'f()';", "f")).toBeUndefined();
    expect(callsAny("a.g();", ["g"])).toBe(true);
    expect(callsAny("a.g();", ["g"], true)).toBe(false);
    expect(callsAny("g();", ["g"], true)).toBe(true);
  });

  it("matches member calls and method calls", () => {
    const line = (text: string, test: Parameters<typeof findLine>[1]) =>
      findLine(text, test);

    expect(
      line("c.functions.invoke('a');", (n) =>
        isMemberCall(n, "functions", "invoke"),
      ),
    ).toBe(1);
    expect(
      line("functions().invoke('a');", (n) =>
        isMemberCall(n, "functions", "invoke"),
      ),
    ).toBe(1);
    expect(
      line("invoke('a');", (n) => isMethodCall(n, "invoke")),
    ).toBeUndefined();
    expect(line("a.invoke();", (n) => isMethodCall(n, "invoke"))).toBe(1);
    expect(line("admin();", (n) => isCallOf(n, "admin"))).toBe(1);
  });

  it("matches a string property and a module", () => {
    expect(
      findLine("f({\n  auth: `user`,\n});", (n) =>
        isStringProperty(n, "auth", "user"),
      ),
    ).toBe(2);
    expect(
      findLine("f({ auth: 'admin' });", (n) =>
        isStringProperty(n, "auth", "user"),
      ),
    ).toBeUndefined();
    expect(findLine('export * from "x";', (n) => isModuleOf(n, "x"))).toBe(1);
  });
});

describe("names", () => {
  it("counts identifiers and strings, not comments", () => {
    expect(mentionsName("const KEY_A = 1;", "KEY_A")).toBe(true);
    expect(mentionsName("f(`x KEY_A y`);", "KEY_A")).toBe(true);
    expect(mentionsName("// KEY_A", "KEY_A")).toBe(false);
    expect(mentionsExactly("run(blockTickHandler);", "blockTickHandler")).toBe(
      true,
    );
    expect(
      mentionsExactly("f('a blockTickHandler');", "blockTickHandler"),
    ).toBe(false);
  });

  it("finds a wired provider property", () => {
    expect(
      hasWiredProperty("x = { leads: blocks.leads.with({}) };", ["leads"]),
    ).toBe(true);
    expect(hasWiredProperty("x = { leads: make().with({}) };", ["leads"])).toBe(
      false,
    );
    expect(
      hasWiredProperty('x = { "mail-sync": blocks["mail-sync"].using(f) };', [
        "mail-sync",
      ]),
    ).toBe(true);
  });
});
