import { describe, expect, it } from "vitest";

import {
  MAX_SBOM_COMPONENTS,
  parseCycloneDx,
} from "../../../src/blocks/advisories/cyclonedx.ts";

const SERIAL = "urn:uuid:3e671687-395b-41f5-a30f-a58921a69b79";

const bom = (extra: Record<string, unknown> = {}) => ({
  bomFormat: "CycloneDX",
  specVersion: "1.6",
  ...extra,
});

describe("parseCycloneDx", () => {
  it("reads a JSON string with nested components", () => {
    const result = parseCycloneDx(
      JSON.stringify(
        bom({
          serialNumber: SERIAL,
          components: [
            {
              type: "application",
              name: " app ",
              "bom-ref": "a",
              version: "1",
              group: "g",
              purl: "pkg:npm/app@1",
              cpe: "cpe:2.3:a",
              supplier: { name: "Acme" },
              licenses: [
                { expression: "MIT OR Apache-2.0" },
                { license: { id: "MIT" } },
                { license: { name: "Custom" } },
                { license: {} },
                { license: "x" },
                "nope",
              ],
              hashes: [
                { alg: "SHA-256", content: "abc" },
                { alg: "SHA-1" },
                "nope",
              ],
              components: [{ name: "child" }, { version: "1" }, "skip"],
            },
          ],
        }),
      ),
    );

    expect(result.data?.serialNumber).toBe(SERIAL);
    expect(result.data?.components).toHaveLength(2);
    expect(result.data?.components[0]).toMatchObject({
      name: "app",
      supplier: "Acme",
      licenses: ["MIT OR Apache-2.0", "MIT", "Custom"],
      hashes: [{ alg: "SHA-256", content: "abc" }],
    });
    expect(result.data?.components[1]).toMatchObject({
      type: "library",
      supplier: undefined,
      licenses: [],
      hashes: [],
    });
  });

  it("accepts a parsed BOM without components", () => {
    expect(parseCycloneDx(bom()).data).toEqual({
      specVersion: "1.6",
      serialNumber: undefined,
      components: [],
    });
    expect(parseCycloneDx(bom({ components: "x" })).data?.components).toEqual(
      [],
    );
  });

  it("refuses invalid input", () => {
    expect(parseCycloneDx("{").error?.message).toMatch(/JSON/u);
    expect(parseCycloneDx(5).error?.message).toMatch(/bomFormat/u);
    expect(parseCycloneDx({ bomFormat: "SPDX" }).error?.message).toMatch(
      /bomFormat/u,
    );
    expect(parseCycloneDx(bom({ specVersion: "1.3" })).error?.message).toMatch(
      /specVersion/u,
    );
    expect(
      parseCycloneDx(bom({ specVersion: undefined })).error?.message,
    ).toMatch(/specVersion/u);
    expect(parseCycloneDx(bom({ serialNumber: "x" })).error?.message).toMatch(
      /urn:uuid/u,
    );
  });

  it("refuses deep nesting", () => {
    let node: Record<string, unknown> = { name: "leaf" };

    for (let i = 0; i < 40; i += 1) {
      node = { name: `n${String(i)}`, components: [node] };
    }

    expect(parseCycloneDx(bom({ components: [node] })).error?.message).toMatch(
      /32 levels/u,
    );
  });

  it("refuses too many components", () => {
    const components = Array.from(
      { length: MAX_SBOM_COMPONENTS + 1 },
      (_, i) => ({ name: `c${String(i)}` }),
    );

    expect(parseCycloneDx(bom({ components })).error?.message).toMatch(
      /at most/u,
    );
  });
});
