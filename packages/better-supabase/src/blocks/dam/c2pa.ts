import type { Result } from "../../core/result.ts";

import { dbError } from "../../core/errors.ts";
import { err, ok } from "../../core/result.ts";

/** IPTC digital source types that mark generated or composited media. */
export const C2PA_AI_SOURCE_TYPES: readonly string[] = [
  "http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia",
  "http://cv.iptc.org/newscodes/digitalsourcetype/compositeWithTrainedAlgorithmicMedia",
  "http://cv.iptc.org/newscodes/digitalsourcetype/algorithmicMedia",
];

/** One action of a manifest's `c2pa.actions` assertion. */
export interface C2paAction {
  /** `c2pa.created`, `c2pa.edited`, `c2pa.published` and so on. */
  readonly action: string;
  readonly digitalSourceType?: string;
  readonly softwareAgent?: string;
  readonly when?: string;
}

export interface C2paIngredient {
  readonly title?: string;
  readonly format?: string;
  /** `parentOf`, `componentOf` or `inputTo`. */
  readonly relationship?: string;
}

/** What a reader reports about the active manifest. */
export interface C2paManifest {
  readonly claimGenerator?: string;
  readonly title?: string;
  /** The signer's common name from the signing certificate. */
  readonly signer?: string;
  readonly signedAt?: string;
  readonly actions: readonly C2paAction[];
  readonly ingredients: readonly C2paIngredient[];
  /**
   * Whether the reader validated the signature, the certificate chain and the
   * content hashes. A reader that cannot check a trust list reports `false` for
   * an untrusted signer.
   */
  readonly valid: boolean;
  /**
   * The reader's validation status codes, such as
   * `assertion.dataHash.mismatch`.
   */
  readonly validationErrors: readonly string[];
}

/**
 * Reads the C2PA manifest store of a file. Versioned: a breaking change ships a
 * new `apiVersion`. Implement it over c2pa-rs, c2pa-node or a hosted verifier;
 * better-supabase bundles none. Return `undefined` for a file with no
 * manifest.
 */
export interface C2paReader {
  readonly apiVersion: 1;
  /** Identifies the reader in logs, such as `"c2pa-node"`. */
  readonly name: string;
  read(input: {
    readonly bytes: Uint8Array;
    readonly mimeType: string;
  }): Promise<C2paManifest | undefined>;
}

/** Checks a reader's `apiVersion` before the app uses it. */
export function c2paReaderOf(reader: C2paReader): C2paReader {
  const version: unknown = reader.apiVersion;

  if (version !== 1) {
    throw new TypeError(
      `C2PA reader "${reader.name}" targets C2PA reader API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release of the reader for API 1.`,
    );
  }

  return reader;
}

/** What the DAM keeps about a file's provenance. */
export interface C2paReading {
  /**
   * `absent`: no manifest. `valid`: the manifest validated. `invalid`: there is
   * one and it failed validation, so its claims are not to be trusted.
   */
  readonly status: "absent" | "valid" | "invalid";
  readonly manifest?: C2paManifest;
  /** The manifest says the media was generated or composited by a model. */
  readonly aiGenerated: boolean;
  /** The actions, but only from a valid manifest. */
  readonly actions: readonly C2paAction[];
}

/** Whether any action carries an AI digital source type. */
export function c2paIsAiGenerated(manifest: C2paManifest): boolean {
  return manifest.actions.some(
    (action) =>
      action.digitalSourceType !== undefined &&
      C2PA_AI_SOURCE_TYPES.includes(action.digitalSourceType),
  );
}

/**
 * Runs a reader over a file and summarizes it for the DAM. A reader that throws
 * gives an `unexpected` error and never a guess: the caller decides whether an
 * unreadable file blocks an upload. An invalid manifest keeps its `aiGenerated`
 * flag, since a tampered file can still say it was generated, but reports no
 * actions.
 */
export async function readC2paManifest(
  reader: C2paReader,
  input: { readonly bytes: Uint8Array; readonly mimeType: string },
): Promise<Result<C2paReading>> {
  const checked = c2paReaderOf(reader);
  let manifest: C2paManifest | undefined;

  try {
    manifest = await checked.read(input);
  } catch {
    return err(
      dbError("unexpected", `The C2PA reader "${checked.name}" failed`, {
        hint: "C2PA_READER_FAILED",
      }),
    );
  }

  if (manifest === undefined) {
    return ok({ status: "absent", aiGenerated: false, actions: [] });
  }

  return ok({
    status: manifest.valid ? "valid" : "invalid",
    manifest,
    aiGenerated: c2paIsAiGenerated(manifest),
    actions: manifest.valid ? manifest.actions : [],
  });
}
