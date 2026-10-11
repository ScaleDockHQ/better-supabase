import { describe, expect, it } from "vitest";

import {
  documentText,
  parseAs,
  parseDocumentText,
  serializationOf,
} from "../../../src/cli/spec/text.ts";

describe("spec text", () => {
  it("picks the serialization from the extension", () => {
    expect(serializationOf("openapi.yaml")).toBe("yaml");
    expect(serializationOf("openapi.YML")).toBe("yaml");
    expect(serializationOf("openapi.json")).toBe("json");
  });

  it("writes JSON and YAML in the same key order, without anchors", () => {
    const shared = { type: "string" };
    const document = { openapi: "3.1.2", a: shared, b: shared, on: "yes" };
    expect(documentText(document, "json")).toBe(
      `${JSON.stringify(document, null, 2)}\n`,
    );
    const yaml = documentText(document, "yaml");
    expect(yaml).not.toContain("&");
    expect(yaml.split("\n")[0]).toBe("openapi: 3.1.2");
    expect(parseAs("yaml", yaml)).toEqual(document);
  });

  it("parses overlays as JSON or YAML", () => {
    expect(
      parseDocumentText("o.yaml", "overlay: 1.1.0\nactions: []\n"),
    ).toEqual({
      overlay: "1.1.0",
      actions: [],
    });
    expect(parseDocumentText("o.json", '{"overlay":"1.1.0"}')).toEqual({
      overlay: "1.1.0",
    });
  });
});
