import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `advisory_product.*`: the product after the change. */
export interface AdvisoryProductEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly key: string;
  readonly name: string;
}

/** `advisory_product_version.created`. */
export interface ProductVersionEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly productId: string;
  readonly version: string;
}

/** `sbom_component.imported`: a BOM replaced the components of a version. */
export interface SbomImportedEventData {
  readonly organizationId: string;
  readonly versionId: string;
  readonly productId: string;
  readonly componentCount: number;
  readonly serialNumber: string | null;
}

/** What every `vulnerability.*` event carries. */
export interface VulnerabilityEventData {
  readonly organizationId: string;
  readonly id: string;
  /** `CVE-2026-1234`, `GHSA-xxxx-xxxx-xxxx` or another OSV id. */
  readonly vulnId: string;
  /** `none`, `low`, `medium`, `high` or `critical`, once a score is known. */
  readonly severity: string | null;
  readonly cvssScore: number | null;
  readonly epssScore: number | null;
  readonly kev: boolean;
}

/** `vulnerability.exploited`: the CISA KEV catalog lists it now. */
export interface VulnerabilityExploitedEventData extends VulnerabilityEventData {
  /** `YYYY-MM-DD`. */
  readonly kevAddedOn: string | null;
  /** `YYYY-MM-DD`, the remediation due date the catalog carries. */
  readonly kevDueOn: string | null;
}

/** `vex_statement.saved`. */
export interface VexStatementEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly productId: string;
  /** Null when the statement covers every version. */
  readonly versionId: string | null;
  readonly vulnerabilityId: string;
  readonly vulnId: string;
  /** `not_affected`, `affected`, `fixed` or `under_investigation`. */
  readonly status: string;
}

/** What every `advisory.*` event carries. */
export interface AdvisoryEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly trackingId: string;
  readonly title: string;
  /** `draft`, `interim` or `final`. */
  readonly status: string;
  /** The CSAF document version, 0 until the first publication. */
  readonly revision: number;
}

/** The events of the `advisories` block: type to data. */
export type AdvisoriesEvents = {
  readonly "advisory_product.created": AdvisoryProductEventData;
  readonly "advisory_product.updated": AdvisoryProductEventData;
  readonly "advisory_product_version.created": ProductVersionEventData;
  readonly "sbom_component.imported": SbomImportedEventData;
  readonly "vulnerability.created": VulnerabilityEventData;
  readonly "vulnerability.enriched": VulnerabilityEventData;
  readonly "vulnerability.exploited": VulnerabilityExploitedEventData;
  readonly "vex_statement.saved": VexStatementEventData;
  readonly "advisory.created": AdvisoryEventData;
  readonly "advisory.updated": AdvisoryEventData;
  readonly "advisory.published": AdvisoryEventData;
};

/** The `advisories` block's event types, for its manifest and `onBlockEvent`. */
export const advisoriesEvents: Events<AdvisoriesEvents> = defineEvents({
  "advisory_product.created": event<AdvisoryProductEventData>(),
  "advisory_product.updated": event<AdvisoryProductEventData>(),
  "advisory_product_version.created": event<ProductVersionEventData>(),
  "sbom_component.imported": event<SbomImportedEventData>(),
  "vulnerability.created": event<VulnerabilityEventData>(),
  "vulnerability.enriched": event<VulnerabilityEventData>(),
  "vulnerability.exploited": event<VulnerabilityExploitedEventData>(),
  "vex_statement.saved": event<VexStatementEventData>(),
  "advisory.created": event<AdvisoryEventData>(),
  "advisory.updated": event<AdvisoryEventData>(),
  "advisory.published": event<AdvisoryEventData>(),
});
