import type { VexJustification, VexStatus } from "./types.ts";

/** A statement to put in an OpenVEX document. */
export interface OpenVexStatement {
  /** The vulnerability's name: `CVE-2026-1234` or an OSV id. */
  readonly vulnId: string;
  /** The version it is about, or `undefined` for the product as a whole. */
  readonly version?: string | undefined;
  readonly status: VexStatus;
  readonly justification?: VexJustification | undefined;
  readonly impactStatement?: string | undefined;
  readonly actionStatement?: string | undefined;
  readonly timestamp?: Temporal.Instant | undefined;
}

export interface OpenVexInput {
  /** The document's `@id`, an IRI. Default: a `urn:uuid:`. */
  readonly id?: string;
  /** Who wrote the statements: a person, a team or a company. */
  readonly author: string;
  readonly role?: string;
  /** Default: now. */
  readonly timestamp?: Temporal.Instant;
  /** The document's version, 1 for the first. Default: 1. */
  readonly version?: number;
  readonly product: {
    readonly key: string;
    /** The package URL the product is identified by. Default: a generic one. */
    readonly purl?: string;
  };
  readonly statements: readonly OpenVexStatement[];
}

/** The OpenVEX version the block writes. */
export const OPENVEX_CONTEXT = "https://openvex.dev/ns/v0.2.0";

function productId(
  input: OpenVexInput["product"],
  version: string | undefined,
): string {
  const base = input.purl ?? `pkg:generic/${encodeURIComponent(input.key)}`;

  return version === undefined || input.purl?.includes("@") === true
    ? base
    : `${base}@${encodeURIComponent(version)}`;
}

/**
 * Renders an OpenVEX 0.2.0 document for one product. Each statement names the
 * product, or one of its versions as `pkg:generic/<key>@<version>` unless the
 * product has its own package URL.
 */
export function renderOpenVex(
  input: OpenVexInput,
): Readonly<Record<string, unknown>> {
  const timestamp = input.timestamp?.toString() ?? new Date().toISOString();

  return {
    "@context": OPENVEX_CONTEXT,
    "@id": input.id ?? `urn:uuid:${crypto.randomUUID()}`,
    author: input.author,
    ...(input.role === undefined ? {} : { role: input.role }),
    timestamp,
    version: input.version ?? 1,
    statements: input.statements.map((statement) => ({
      vulnerability: { name: statement.vulnId },
      ...(statement.timestamp === undefined
        ? {}
        : { timestamp: statement.timestamp.toString() }),
      products: [{ "@id": productId(input.product, statement.version) }],
      status: statement.status,
      ...(statement.justification === undefined
        ? {}
        : { justification: statement.justification }),
      ...(statement.impactStatement === undefined
        ? {}
        : { impact_statement: statement.impactStatement }),
      ...(statement.actionStatement === undefined
        ? {}
        : { action_statement: statement.actionStatement }),
    })),
  };
}
