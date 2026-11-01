import { describe, expect, it } from "vitest";

import { PRESET_CATALOG } from "../../src/preset/catalog.generated.ts";
import { presetConfig } from "../../src/preset/config.ts";
import { presetOf } from "../../src/preset/index.ts";
import { PRESETS } from "../../src/preset/presets.ts";
import { resolvePreset } from "../../src/preset/resolve.ts";
import closures from "./preset-closures.json" with { type: "json" };

const composites = new Set(
  PRESET_CATALOG.manifests
    .filter((manifest) => manifest.composes !== undefined)
    .map((manifest) => manifest.name),
);

/**
 * What a composite adds because its part is a whole block: `support` installs
 * `inbox` with the `chat-sdk-state` module it ships, which the preset listed by
 * module name did not. `field-service` lists `service`, which also installs
 * maintenance plans, cases and SLAs.
 */
const ADDED: Readonly<Record<string, readonly string[]>> = {
  helpdesk: ["chat-sdk-state"],
  // The `service` composite adds maintenance plans, cases and SLAs to dispatch.
  "field-service": ["cases", "maintenance", "pipelines", "sla"],
};

const closureOf = (name: keyof typeof PRESETS): string[] =>
  resolvePreset(presetOf(name), PRESET_CATALOG)
    .blocks.map((block) => block.name)
    .filter((block) => !composites.has(block))
    .toSorted();

describe("named presets that list composites", () => {
  // The fixture is each preset's closure from before the presets listed
  // composites (ADR 0177). Changing a preset's closure is a breaking change,
  // so it needs a new fixture and a changeset, not a quiet edit.
  it.each(
    (Object.keys(PRESETS) as (keyof typeof PRESETS)[]).filter(
      (name) => name !== "everything",
    ),
  )("%s resolves to the same blocks", (name) => {
    expect(closureOf(name)).toEqual(
      [
        ...((closures as Record<string, string[]>)[name] ?? []),
        ...(ADDED[name] ?? []),
      ].toSorted(),
    );
  });
});

describe("composite defaults in the config", () => {
  const blocksOf = (name: keyof typeof PRESETS): Record<string, unknown> =>
    // SAFETY: the config's block entries are plain objects keyed by block name.
    presetConfig(resolvePreset(presetOf(name), PRESET_CATALOG)).blocks;

  it("names tickets through support", () => {
    expect(blocksOf("helpdesk")["tasks"]).toEqual({
      entities: { task: "ticket", project: "issue" },
    });
  });

  it("sets the record team of care's clients through care", () => {
    expect(blocksOf("care")["contacts"]).toEqual({
      entities: {
        person: { auditReads: true, team: { actions: ["read", "write"] } },
      },
    });
  });

  it("serves public media through cms and keeps the preset's own option", () => {
    const blocks = blocksOf("cms");

    expect(blocks["attachments"]).toEqual({
      options: { publicBuckets: ["attachments"], requireScan: false },
    });
    expect(blocks["content"]).toEqual({ options: { requireApproval: true } });
  });
});
