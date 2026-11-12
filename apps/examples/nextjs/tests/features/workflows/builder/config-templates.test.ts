import { describe, expect, it } from "vitest";

import {
  readTemplatePath,
  resolveTemplates,
  templatePaths,
} from "@/features/workflows/builder/config-templates";

const scope = {
  input: { name: "Ada", items: ["a", "b"] },
  results: { fetch: { count: 2 } },
};

describe("config templates", () => {
  it("reads input and result paths", () => {
    expect(readTemplatePath(scope, "input.name")).toBe("Ada");
    expect(readTemplatePath(scope, "results.fetch.count")).toBe(2);
    expect(readTemplatePath(scope, "other.x")).toBeUndefined();
  });

  it("keeps the type of a whole-value marker", () => {
    expect(resolveTemplates("{{input.items}}", scope)).toEqual(["a", "b"]);
  });

  it("turns markers inside text into text", () => {
    expect(
      resolveTemplates("Hi {{input.name}}, {{results.fetch.count}}", scope),
    ).toBe("Hi Ada, 2");
  });

  it("resolves objects and lists deeply", () => {
    expect(resolveTemplates({ to: ["{{input.name}}"], n: 1 }, scope)).toEqual({
      to: ["Ada"],
      n: 1,
    });
  });

  it("lists the paths a config reads", () => {
    expect(
      templatePaths({ a: "{{input.name}}", b: ["x {{results.fetch.count}}"] }),
    ).toEqual(["input.name", "results.fetch.count"]);
  });
});
