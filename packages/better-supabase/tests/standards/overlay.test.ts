import { describe, expect, it } from "vitest";

import type { Overlay } from "../../src/overlay/types.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import {
  applyOverlay,
  defineOverlay,
  expandReusableActions,
  loadJsonPath,
  overlayFromDiff,
} from "../../src/overlay/index.ts";
import { defineApi } from "../../src/spec/api.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { problems, validatorFor } from "./validator.ts";

const SCHEMAS = {
  [SPEC_PINS.overlay10]: "overlay-1.0.json",
  [SPEC_PINS.overlay11]: "overlay-1.1.json",
  [SPEC_PINS.overlay12]: "overlay-1.2.json",
} as const;

const valid = (overlay: Overlay) =>
  problems(
    validatorFor(SCHEMAS[overlay.overlay]),
    JSON.parse(JSON.stringify(overlay)),
  );

const base = defineApi(defineSupabase(schema), {
  info: { title: "CRM", version: "1.0.0" },
  resources: { notes: { operations: ["list", "get"] } },
}).openapi().document;

const info = { title: "Public API", version: "1.0.0" };

describe(`Overlay ${SPEC_PINS.overlay10}`, () => {
  const overlay = defineOverlay({
    overlay: SPEC_PINS.overlay10,
    info,
    actions: [
      { target: "$.info", update: { description: "Public" } },
      { target: "$.paths['/notes/{id}']", remove: true },
    ],
  });

  it("writes SPEC_PINS.overlay10 and validates against the 1.0 schema", () => {
    expect(overlay.overlay).toBe(SPEC_PINS.overlay10);
    expect(valid(overlay)).toEqual([]);
  });

  it("overlayFromDiff writes a valid 1.0 overlay", () => {
    const enriched = {
      ...base,
      info: { ...base.info, description: "Changed" },
    };

    const diff = overlayFromDiff(base, enriched, {
      version: SPEC_PINS.overlay10,
    });

    expect(diff.overlay).toBe(SPEC_PINS.overlay10);
    expect(valid(diff)).toEqual([]);
  });
});

describe(`Overlay ${SPEC_PINS.overlay11}`, () => {
  const overlay = defineOverlay({
    info: { ...info, description: "CommonMark" },
    extends: "https://api.test/openapi.json",
    actions: [
      { target: "$.info", update: { description: "Public" } },
      { target: "$.info.summary", copy: "$.info.title" },
      { target: "$.paths[?@.get.deprecated == true]", remove: true },
    ],
  });

  it("is the default version and validates against the 1.1 schema", () => {
    expect(overlay.overlay).toBe(SPEC_PINS.overlay11);
    expect(valid(overlay)).toEqual([]);
  });

  it("applies to a rendered OpenAPI document with RFC 9535 targets", async () => {
    const jsonpath = await loadJsonPath();

    const { document, diagnostics } = applyOverlay(
      base,
      defineOverlay({
        info,
        actions: [{ target: "$.info", update: { description: "Public" } }],
      }),
      { jsonpath },
    );

    expect(diagnostics).toEqual([]);
    expect(document.info.description).toBe("Public");
    expect(base.info.description).toBeUndefined();
  });

  it("is rejected by the schema without actions", () => {
    expect(valid({ ...overlay, actions: [] })).not.toEqual([]);
  });
});

describe(`Overlay ${SPEC_PINS.overlay12}`, () => {
  const overlay = defineOverlay({
    info,
    $self: "https://api.test/public.overlay.json",
    components: {
      actions: {
        hide: {
          description: "Hide an operation",
          fields: { remove: true },
        },
      },
    },
    actions: [
      { $ref: "#/components/actions/hide", target: "$.paths['/notes/{id}']" },
      { target: "$.info", update: { description: "Public" } },
    ],
  });

  it("uses 1.2 for reusable actions and validates against the 1.2 schema", () => {
    expect(overlay.overlay).toBe(SPEC_PINS.overlay12);
    expect(valid(overlay)).toEqual([]);
  });

  it("expands reusable actions into a valid 1.1 overlay", () => {
    const { overlay: expanded, diagnostics } = expandReusableActions(overlay);
    expect(diagnostics).toEqual([]);
    expect(expanded.overlay).toBe(SPEC_PINS.overlay11);
    expect(valid(expanded)).toEqual([]);
  });
});
