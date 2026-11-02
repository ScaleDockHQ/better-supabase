/** What an OpenVEX statement says about a product (OpenVEX 0.2.0). */
export const VEX_STATUSES = [
  "not_affected",
  "affected",
  "fixed",
  "under_investigation",
] as const;

export type VexStatus = (typeof VEX_STATUSES)[number];

/** The OpenVEX justifications of a `not_affected` statement. */
export const VEX_JUSTIFICATIONS = [
  "component_not_present",
  "vulnerable_code_not_present",
  "vulnerable_code_not_in_execute_path",
  "vulnerable_code_cannot_be_controlled_by_adversary",
  "inline_mitigations_already_exist",
] as const;

export type VexJustification = (typeof VEX_JUSTIFICATIONS)[number];

/** The status of a CSAF advisory. Publishing needs `interim` or `final`. */
export const ADVISORY_STATUSES = ["draft", "interim", "final"] as const;

export type AdvisoryStatus = (typeof ADVISORY_STATUSES)[number];

/** One VEX statement of a published advisory, for one version or all of them. */
export interface PublishedStatement {
  /** The product version it is about, or `undefined` for every version. */
  readonly version: string | undefined;
  readonly status: VexStatus;
  readonly justification: VexJustification | undefined;
  readonly impactStatement: string | undefined;
  readonly actionStatement: string | undefined;
}

/** A vulnerability of a published advisory, with the product's statements. */
export interface PublishedVulnerability {
  /** `CVE-2026-1234`, `GHSA-xxxx-xxxx-xxxx` or another OSV id. */
  readonly vulnId: string;
  readonly aliases: readonly string[];
  readonly summary: string | undefined;
  readonly details: string | undefined;
  readonly cvssVector: string | undefined;
  readonly cvssVersion: string | undefined;
  readonly cvssScore: number | undefined;
  /** `YYYY-MM-DD`, when the CISA KEV catalog lists it. */
  readonly kevAddedOn: string | undefined;
  readonly statements: readonly PublishedStatement[];
}

/** One entry of a CSAF document's revision history. */
export interface AdvisoryRevision {
  readonly number: string;
  readonly date: Temporal.Instant;
  readonly summary: string;
}

/** A published advisory with everything a CSAF document needs. */
export interface PublishedAdvisory {
  /** The CSAF `tracking.id`, such as `ACME-SA-2026-001`. */
  readonly trackingId: string;
  readonly title: string;
  readonly summary: string;
  readonly status: Exclude<AdvisoryStatus, "draft">;
  /** The document version, 1 for the first publication. */
  readonly version: number;
  readonly initialReleaseAt: Temporal.Instant;
  readonly currentReleaseAt: Temporal.Instant;
  readonly revisionHistory: readonly AdvisoryRevision[];
  readonly product: {
    readonly key: string;
    readonly name: string;
    /** The versions the advisory's statements name, plus the product's own. */
    readonly versions: readonly string[];
  };
  readonly vulnerabilities: readonly PublishedVulnerability[];
}

/** A row of the published advisory index. */
export interface PublishedAdvisorySummary {
  readonly trackingId: string;
  readonly title: string;
  readonly status: Exclude<AdvisoryStatus, "draft">;
  readonly version: number;
  readonly initialReleaseAt: Temporal.Instant;
  readonly currentReleaseAt: Temporal.Instant;
}
