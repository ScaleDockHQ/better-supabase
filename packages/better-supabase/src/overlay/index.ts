export { applyOverlay, applyOverlays } from "./apply.ts";
export { defineOverlay, expandReusableActions } from "./define.ts";
export type { DefinedOverlay, OverlayInput } from "./define.ts";
export { overlayFromDiff } from "./diff.ts";
export type { OverlayFromDiffOptions } from "./diff.ts";
export { loadJsonPath } from "./load.ts";
export type {
  ApplyOverlayOptions,
  Extensions,
  JsonPathEngine,
  Overlay,
  Overlay10,
  Overlay11,
  Overlay12,
  OverlayAction,
  OverlayAction10,
  OverlayInfo,
  OverlayResult,
  OverlayVersion,
  ReusableAction,
  ReusableActionFields,
  ReusableActionReference,
} from "./types.ts";
export type { SpecDiagnostic } from "../spec/format.ts";
