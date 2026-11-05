import type { Jwks } from "../../core/jws.ts";
import type { ChainProof, ChainProofVerdict } from "./table-chain.ts";

import { sha256Hex } from "../../core/sha256.ts";
import { verifyChainProof } from "./table-chain.ts";

/** The record an evidence bundle is about. */
export interface EvidenceSubject {
  readonly type: string;
  readonly id: string;
}

export interface EvidenceParts {
  readonly subject: EvidenceSubject;
  /** One proof per chained row that belongs to the record. */
  readonly proofs: readonly ChainProof[];
  /**
   * Other sections as plain JSON: audit entries, signature verification
   * results, version and attachment hashes, the shipment timeline.
   */
  readonly sections?: Readonly<Record<string, unknown>>;
  readonly generatedAt: string;
}

/** One JSON document for a record, with a hash over its content. */
export interface EvidenceBundle extends EvidenceParts {
  readonly format: "better-supabase/evidence@1";
  /** SHA-256 (hex) of the bundle without this field, as JSON. */
  readonly sha256: string;
}

function body(parts: EvidenceParts): string {
  return JSON.stringify({
    format: "better-supabase/evidence@1",
    subject: parts.subject,
    proofs: parts.proofs,
    sections: parts.sections ?? {},
    generatedAt: parts.generatedAt,
  });
}

/**
 * Seals `parts` with a content hash. Write the result to storage under a legal
 * hold.
 */
export async function evidenceBundle(
  parts: EvidenceParts,
): Promise<EvidenceBundle> {
  return {
    format: "better-supabase/evidence@1",
    ...parts,
    sections: parts.sections ?? {},
    sha256: await sha256Hex(body(parts)),
  };
}

export type EvidenceVerdict =
  | { readonly valid: true; readonly proofs: number }
  | {
      readonly valid: false;
      readonly reason: "bundle" | "proof";
      readonly proof?: number;
      readonly detail?: ChainProofVerdict;
    };

/** Checks the content hash and every proof against `jwks`, offline. */
export async function verifyEvidenceBundle(
  bundle: EvidenceBundle,
  jwks: Jwks,
  options: { readonly requireSigned?: boolean } = {},
): Promise<EvidenceVerdict> {
  if ((await sha256Hex(body(bundle))) !== bundle.sha256) {
    return { valid: false, reason: "bundle" };
  }

  for (const [index, proof] of bundle.proofs.entries()) {
    const verdict = await verifyChainProof(proof, jwks, options);

    if (!verdict.valid) {
      return { valid: false, reason: "proof", proof: index, detail: verdict };
    }
  }

  return { valid: true, proofs: bundle.proofs.length };
}
