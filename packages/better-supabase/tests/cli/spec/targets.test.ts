import { describe, expect, it } from "vitest";

import { formatRegistry } from "../../../src/cli/spec/formats.ts";
import { TargetError, resolveTargets } from "../../../src/cli/spec/targets.ts";
import { defineDocumentFormat } from "../../../src/spec/format.ts";

const events = defineDocumentFormat({
  apiVersion: 1,
  id: "events",
  versions: { "1.0": { pin: "1.0.0", status: "stable" } },
  defaultVersion: "1.0",
  lower: () => ({ events: "1.0.0" }),
  fileName: () => "events.json",
});

const registry = formatRegistry([events]);

const error = (run: () => unknown): TargetError => {
  try {
    run();
  } catch (cause) {
    if (cause instanceof TargetError) {
      return cause;
    }
  }
  throw new Error("expected a TargetError");
};

describe("resolveTargets", () => {
  it("fills in the default version, file name and serialization", () => {
    expect(resolveTargets([{ format: "openapi" }], registry, {})).toEqual([
      expect.objectContaining({
        version: "3.1",
        output: "openapi.json",
        serialization: "json",
        overlays: [],
      }),
    ]);
    expect(
      resolveTargets(
        [{ format: "openapi", output: "api.yml", ui: "scalar" }],
        registry,
        {},
      ),
    ).toEqual([
      expect.objectContaining({ serialization: "yaml", ui: "scalar" }),
    ]);
    expect(
      resolveTargets([{ format: "openapi" }], registry, { yaml: true })[0]
        ?.output,
    ).toBe("openapi.yaml");
  });

  it("narrows by format and renders an unconfigured format on its own", () => {
    const outputs = [{ format: "openapi" }, { format: "events" }];
    expect(
      resolveTargets(outputs, registry, { format: "events" }),
    ).toHaveLength(1);
    expect(resolveTargets([], registry, { format: "events" })[0]?.output).toBe(
      "events.json",
    );
  });

  it("picks the configured output at a version, or writes a versioned file", () => {
    const outputs = [
      { format: "openapi", version: "3.0", output: "legacy.json" },
      { format: "openapi", version: "3.2", output: "next.json" },
    ];
    expect(
      resolveTargets(outputs, registry, { version: "3.0" })[0]?.output,
    ).toBe("legacy.json");
    expect(
      resolveTargets([{ format: "openapi" }], registry, { version: "3.2" })[0]
        ?.output,
    ).toBe("openapi-3.2.json");
    expect(
      resolveTargets([{ format: "openapi" }], registry, {
        version: "3.2",
        out: "x.json",
      })[0]?.output,
    ).toBe("x.json");
  });

  it("explains what it can't resolve", () => {
    expect(
      error(() => resolveTargets([{ format: "nope" }], registry, {})).code,
    ).toBe("format-unknown");
    expect(
      error(() =>
        resolveTargets([{ format: "openapi", version: "9" }], registry, {}),
      ).code,
    ).toBe("version-unknown");
    const both = [{ format: "openapi" }, { format: "events" }];
    expect(
      error(() => resolveTargets(both, registry, { version: "2.0" })).code,
    ).toBe("usage");
    expect(
      error(() => resolveTargets(both, registry, { out: "x.json" })).message,
    ).toContain("2 match");
    expect(
      error(() =>
        resolveTargets(
          [
            { format: "openapi", version: "3.0" },
            { format: "openapi", version: "3.2" },
          ],
          registry,
          {},
        ),
      ).message,
    ).toContain("Two outputs write openapi.json");
  });
});
