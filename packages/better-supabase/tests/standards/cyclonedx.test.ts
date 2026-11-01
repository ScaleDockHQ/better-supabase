import { describe, expect, it } from "vitest";

import {
  MAX_SBOM_COMPONENTS,
  parseCycloneDx,
} from "../../src/blocks/advisories/index.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

const bom = {
  bomFormat: "CycloneDX",
  specVersion: "1.6",
  serialNumber: "urn:uuid:3e671687-395b-41f5-a30f-a58921a69b79",
  components: [
    {
      "bom-ref": "pkg:npm/left-pad@1.3.0",
      type: "library",
      group: "",
      name: "left-pad",
      version: "1.3.0",
      purl: "pkg:npm/left-pad@1.3.0",
      licenses: [{ license: { id: "MIT" } }],
      hashes: [{ alg: "SHA-256", content: "abc" }],
      components: [{ type: "library", name: "nested", version: "0.1.0" }],
    },
    { type: "library", version: "1.0.0" },
  ],
};

describe("parseCycloneDx", () => {
  it("flattens the component tree and keeps what matching needs", () => {
    const parsed = parseCycloneDx(bom);

    expect(parsed.ok).toBe(true);

    if (!parsed.ok) {
      return;
    }

    expect(parsed.data.specVersion).toBe("1.6");
    expect(parsed.data.serialNumber).toBe(bom.serialNumber);
    expect(parsed.data.components.map((component) => component.name)).toEqual([
      "left-pad",
      "nested",
    ]);
    expect(parsed.data.components[0]).toMatchObject({
      bomRef: "pkg:npm/left-pad@1.3.0",
      purl: "pkg:npm/left-pad@1.3.0",
      licenses: ["MIT"],
      hashes: [{ alg: "SHA-256", content: "abc" }],
    });
  });

  it("reads a JSON string", () => {
    expect(parseCycloneDx(JSON.stringify(bom)).ok).toBe(true);
  });

  it("refuses what is not a CycloneDX 1.4 to 1.7 BOM", () => {
    expect(parseCycloneDx("{").ok).toBe(false);
    expect(parseCycloneDx({ ...bom, bomFormat: "SPDX" }).ok).toBe(false);
    expect(parseCycloneDx({ ...bom, specVersion: "1.3" }).ok).toBe(false);
    expect(parseCycloneDx({ ...bom, specVersion: "1.8" }).ok).toBe(false);
    expect(parseCycloneDx({ ...bom, serialNumber: "x" }).ok).toBe(false);
  });

  it("refuses a BOM with too many components", () => {
    const components = Array.from({ length: MAX_SBOM_COMPONENTS + 1 }, () => ({
      type: "library",
      name: "x",
    }));

    expect(parseCycloneDx({ ...bom, components }).ok).toBe(false);
  });
});

describe("cyclonedx spec pin", () => {
  it("names the version the code follows", () => {
    expect(SPEC_PINS.cyclonedx).toBe("1.7");
  });
});
