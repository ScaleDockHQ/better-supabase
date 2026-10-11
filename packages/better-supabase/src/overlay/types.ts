import type { SpecDiagnostic } from "../spec/format.ts";

/** The Overlay versions `applyOverlay` reads. Patch versions are ignored (Overlay § 4.1). */
export type OverlayVersion = "1.0.0" | "1.1.0" | "1.2.0";

/** Specification extensions: fields that start with `x-` (Overlay 1.2 § 4.7). */
export type Extensions = { readonly [key: `x-${string}`]: unknown };

export type OverlayInfo = {
  /** The purpose of the overlay. */
  readonly title: string;
  /** The overlay's own version, not the Overlay Specification version. */
  readonly version: string;
  /** CommonMark (1.1 and later). */
  readonly description?: string;
} & Extensions;

/** Fields every action kind shares. */
interface ActionFields {
  readonly description?: string;
  /** Merged into objects, concatenated or appended to arrays, or replaces primitives. */
  readonly update?: unknown;
  /** When `true`, every selected node is removed. Wins over `update` and `copy`. */
  readonly remove?: boolean;
  /**
   * Accept a target that selects nothing. Without it, `applyOverlay`
   * reports `overlay-no-match` as an error.
   */
  readonly "x-better-supabase-allow-empty"?: boolean;
}

/** An Overlay 1.0 Action Object. */
export type OverlayAction10 = ActionFields & {
  /** An RFC 9535 JSONPath query. */
  readonly target: string;
} & Extensions;

/** An Overlay 1.1 and 1.2 Action Object, which adds `copy`. */
export type OverlayAction = OverlayAction10 & {
  /** A JSONPath query that selects one node whose value is used like `update`. */
  readonly copy?: string;
};

/** The fields of a reusable action (1.2): an Action Object without `target`. */
export type ReusableActionFields = Omit<OverlayAction, "target">;

/** A Reusable Action Object (Overlay 1.2 § 4.5.5). */
export type ReusableAction = {
  readonly description?: string;
  readonly fields?: ReusableActionFields;
} & Extensions;

/**
 * A Reusable Action Reference Object (Overlay 1.2 § 4.5.6). Its own action
 * fields override the referenced ones for this use.
 */
export type ReusableActionReference = Partial<Omit<OverlayAction, "target">> & {
  /** `#/components/actions/<name>`, with the name escaped per RFC 6901. */
  readonly $ref: `#/components/actions/${string}`;
  readonly target: string;
};

interface OverlayBase {
  readonly info: OverlayInfo;
  /** URI of the target document, without a fragment. */
  readonly extends?: string;
}

export type Overlay10 = OverlayBase & {
  readonly overlay: "1.0.0";
  readonly actions: readonly OverlayAction10[];
} & Extensions;

export type Overlay11 = OverlayBase & {
  readonly overlay: "1.1.0";
  readonly actions: readonly OverlayAction[];
} & Extensions;

export type Overlay12 = OverlayBase & {
  readonly overlay: "1.2.0";
  /** URI of this overlay and its base URI, without a fragment. */
  readonly $self?: string;
  readonly actions: readonly (OverlayAction | ReusableActionReference)[];
  readonly components?: {
    readonly actions?: Readonly<Record<string, ReusableAction>>;
  } & Extensions;
} & Extensions;

/** An Overlay document of any supported version. */
export type Overlay = Overlay10 | Overlay11 | Overlay12;

/**
 * The JSONPath engine `applyOverlay` runs targets with. `paths` returns the
 * RFC 9535 normalized paths (`$['paths']['/a'][0]`) of the selected nodes
 * and throws for an invalid query. `loadJsonPath()` returns the
 * `jsonpath-rfc9535` engine; any RFC 9535 implementation fits.
 */
export interface JsonPathEngine {
  paths(document: unknown, expression: string): readonly string[];
}

export interface ApplyOverlayOptions {
  readonly jsonpath: JsonPathEngine;
  /** Accept targets that select nothing in every action. Default `false`. */
  readonly allowEmpty?: boolean;
}

export interface OverlayResult<T> {
  /** A new document; the input is never changed. */
  readonly document: T;
  /** Errors, warnings and notes, in action order. Callers decide what fails a build. */
  readonly diagnostics: readonly SpecDiagnostic[];
}
