import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { Result } from "../../core/result.ts";
import type { BlockOptions } from "../shared.ts";
import type { CsafSource } from "./csaf.ts";
import type { KevEntry, VulnerabilityFeed } from "./feed.ts";
import type {
  AdvisoryRevision,
  AdvisoryStatus,
  PublishedAdvisory,
  PublishedAdvisorySummary,
  PublishedStatement,
  PublishedVulnerability,
  VexJustification,
  VexStatus,
} from "./types.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";
import { parseCvss } from "./cvss.ts";
import { parseCycloneDx } from "./cyclonedx.ts";
import { publicVulnerabilityFeed, vulnerabilityFeedOf } from "./feed.ts";
import { renderOpenVex } from "./openvex.ts";
import {
  ADVISORY_STATUSES,
  VEX_JUSTIFICATIONS,
  VEX_STATUSES,
} from "./types.ts";

export interface AdvisoryProduct {
  readonly id: string;
  readonly organizationId: string;
  readonly key: string;
  readonly name: string;
  readonly vendor: string | undefined;
  readonly description: string | undefined;
  readonly archivedAt: Temporal.Instant | undefined;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface ProductVersion {
  readonly id: string;
  readonly organizationId: string;
  readonly productId: string;
  readonly version: string;
  readonly releasedAt: Temporal.Instant | undefined;
  readonly endOfSupportAt: Temporal.Instant | undefined;
  readonly sbomSerial: string | undefined;
  readonly sbomSpec: string | undefined;
  readonly sbomComponents: number;
  readonly sbomImportedAt: Temporal.Instant | undefined;
  readonly createdAt: Temporal.Instant;
}

export interface StoredSbomComponent {
  readonly id: string;
  readonly bomRef: string | undefined;
  readonly type: string;
  readonly name: string;
  readonly version: string | undefined;
  readonly purl: string | undefined;
  readonly cpe: string | undefined;
  readonly supplier: string | undefined;
  readonly licenses: readonly string[];
}

export interface TrackedVulnerability {
  readonly id: string;
  readonly organizationId: string;
  readonly vulnId: string;
  readonly aliases: readonly string[];
  readonly summary: string | undefined;
  readonly details: string | undefined;
  readonly cvssVector: string | undefined;
  readonly cvssVersion: string | undefined;
  readonly cvssScore: number | undefined;
  /** `none`, `low`, `medium`, `high` or `critical`. */
  readonly severity: string | undefined;
  readonly epssScore: number | undefined;
  readonly epssPercentile: number | undefined;
  readonly kev: boolean;
  readonly kevAddedOn: string | undefined;
  readonly kevDueOn: string | undefined;
  readonly affectedPurls: readonly string[];
  readonly enrichedAt: Temporal.Instant | undefined;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** A tracked vulnerability that matches a component of a version by package. */
export interface VersionExposure {
  readonly vulnerabilityId: string;
  readonly vulnId: string;
  readonly severity: string | undefined;
  readonly cvssScore: number | undefined;
  readonly epssScore: number | undefined;
  readonly kev: boolean;
  readonly componentId: string;
  readonly componentName: string;
  readonly componentVersion: string | undefined;
  readonly purl: string | undefined;
  /** The product's VEX status, or `undefined` while nobody triaged it. */
  readonly vexStatus: VexStatus | undefined;
}

export interface StoredVexStatement {
  readonly id: string;
  readonly productId: string;
  readonly versionId: string | undefined;
  readonly version: string | undefined;
  readonly vulnerabilityId: string;
  readonly vulnId: string;
  readonly status: VexStatus;
  readonly justification: VexJustification | undefined;
  readonly impactStatement: string | undefined;
  readonly actionStatement: string | undefined;
  readonly updatedAt: Temporal.Instant;
}

export interface Advisory {
  readonly id: string;
  readonly organizationId: string;
  readonly trackingId: string;
  readonly title: string;
  readonly summary: string | undefined;
  readonly productId: string;
  readonly severity: string | undefined;
  readonly status: AdvisoryStatus;
  /** 0 until the first publication. */
  readonly revision: number;
  readonly initialReleaseAt: Temporal.Instant | undefined;
  readonly currentReleaseAt: Temporal.Instant | undefined;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface AdvisoryDetail extends Advisory {
  readonly vulnerabilityIds: readonly string[];
  readonly revisionHistory: readonly AdvisoryRevision[];
}

/** What `enrichDue` did. */
export interface EnrichmentReport {
  readonly checked: number;
  /** Vulnerabilities the feed (OSV, EPSS or KEV) had something for. */
  readonly enriched: number;
  /** Vulnerabilities none of the sources knew. */
  readonly unknown: number;
  /** Vulnerabilities a source failed for; they stay due. */
  readonly failed: number;
}

export interface OpenVexOptions {
  /** Who the document names as its author. */
  readonly author: string;
  readonly role?: string;
  /** The product's package URL, when it has one. */
  readonly purl?: string;
  readonly id?: string;
  /** The document's version, 1 for the first. */
  readonly version?: number;
}

export interface Advisories {
  /** Needs `advisories.write`. Pass `id` to change a product. */
  saveProduct(input: {
    readonly key: string;
    readonly name: string;
    readonly vendor?: string;
    readonly description?: string;
    readonly archived?: boolean;
    readonly id?: string;
  }): AsyncResult<AdvisoryProduct>;
  products(): AsyncResult<AdvisoryProduct[]>;
  createVersion(input: {
    readonly productId: string;
    readonly version: string;
    readonly releasedAt?: Temporal.Instant;
    readonly endOfSupportAt?: Temporal.Instant;
  }): AsyncResult<ProductVersion>;
  versions(productId: string): AsyncResult<ProductVersion[]>;
  /**
   * Replaces a version's components with a CycloneDX 1.4 to 1.7 JSON BOM. A
   * component's `group` is prefixed to its name. Needs `advisories.write`.
   */
  importSbom(versionId: string, bom: unknown): AsyncResult<ProductVersion>;
  components(
    versionId: string,
    options?: { readonly limit?: number },
  ): AsyncResult<StoredSbomComponent[]>;
  /**
   * Tracks a vulnerability by its CVE or OSV id. A CVSS vector is parsed: a 3.x
   * vector stores its score, a 4.0 vector is validated and stored without one.
   * Needs `advisories.write`.
   */
  saveVulnerability(input: {
    readonly vulnId: string;
    readonly summary?: string;
    readonly details?: string;
    readonly aliases?: readonly string[];
    readonly cvssVector?: string;
    readonly affectedPurls?: readonly string[];
  }): AsyncResult<TrackedVulnerability>;
  vulnerabilities(options?: {
    readonly kevOnly?: boolean;
    readonly limit?: number;
  }): AsyncResult<TrackedVulnerability[]>;
  /**
   * Fills the vulnerabilities that were never enriched, or not for
   * `staleAfter`, from OSV, EPSS and the CISA KEV catalog, for a schedule.
   * Needs `advisories.write` (a service role call for a cron).
   */
  enrichDue(options?: {
    readonly limit?: number;
    /** A Postgres interval. Default: `1 day`. */
    readonly staleAfter?: string;
    readonly signal?: AbortSignal;
  }): AsyncResult<EnrichmentReport>;
  /** The vulnerabilities that match a version's components by package. */
  exposure(versionId: string): AsyncResult<VersionExposure[]>;
  /**
   * Sets the product's VEX statement for a vulnerability, for one version or,
   * without `versionId`, for all of them. `not_affected` needs a
   * `justification`.
   */
  saveVexStatement(input: {
    readonly productId: string;
    readonly vulnerabilityId: string;
    readonly status: VexStatus;
    readonly versionId?: string;
    readonly justification?: VexJustification;
    readonly impactStatement?: string;
    readonly actionStatement?: string;
  }): AsyncResult<StoredVexStatement>;
  vexStatements(
    productId: string,
    versionId?: string,
  ): AsyncResult<StoredVexStatement[]>;
  /** An OpenVEX 0.2.0 document with the product's statements. */
  openVex(
    productId: string,
    options: OpenVexOptions,
  ): AsyncResult<Readonly<Record<string, unknown>>>;
  /** Creates a draft, or with `id` changes one. Needs `advisories.write`. */
  saveAdvisory(input: {
    readonly trackingId: string;
    readonly title: string;
    readonly summary: string;
    readonly productId: string;
    readonly vulnerabilityIds: readonly string[];
    readonly severity?: string;
    readonly id?: string;
  }): AsyncResult<Advisory>;
  /** Releases or revises an advisory. Needs `advisories.publish`. */
  publishAdvisory(
    id: string,
    options?: { readonly status?: "interim" | "final"; readonly note?: string },
  ): AsyncResult<Advisory>;
  advisories(options?: {
    readonly status?: AdvisoryStatus;
  }): AsyncResult<Advisory[]>;
  getAdvisory(id: string): AsyncResult<AdvisoryDetail>;
  /**
   * What `createCsafHandler` reads for one organization. The calls need the
   * service role, so build the client over a service transport.
   */
  csafSource(organizationId: string): CsafSource;
}

export interface AdvisoriesOptions extends BlockOptions {
  /**
   * Reads OSV, EPSS and CISA KEV. Default: `publicVulnerabilityFeed()`, the
   * public endpoints over `fetch`.
   */
  readonly feed?: VulnerabilityFeed;
  readonly hooks?: NoInfer<BlockHooks<Advisories>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

const optionalNumber = (value: unknown): number | undefined =>
  value === null || value === undefined ? undefined : Number(value);

const textsOf = (value: unknown): string[] =>
  Array.isArray(value) ? value.map((entry) => textOf(entry)) : [];

const optionalEnum = <T extends string>(
  value: unknown,
  values: readonly T[],
  what: string,
): T | undefined =>
  value === null || value === undefined
    ? undefined
    : enumOrThrow(value, values, what);

function productOf(value: unknown): AdvisoryProduct {
  const row = recordOf(value, "advisory_product");

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    vendor: optionalText(row["vendor"]),
    description: optionalText(row["description"]),
    archivedAt: optionalInstant(row["archivedAt"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
  };
}

function versionOf(value: unknown): ProductVersion {
  const row = recordOf(value, "advisory_product_version");

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    productId: textOf(row["productId"]),
    version: textOf(row["version"]),
    releasedAt: optionalInstant(row["releasedAt"]),
    endOfSupportAt: optionalInstant(row["endOfSupportAt"]),
    sbomSerial: optionalText(row["sbomSerial"]),
    sbomSpec: optionalText(row["sbomSpec"]),
    sbomComponents: Number(row["sbomComponents"] ?? 0),
    sbomImportedAt: optionalInstant(row["sbomImportedAt"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
  };
}

function componentOf(value: unknown): StoredSbomComponent {
  const row = recordOf(value, "sbom_component");

  return {
    id: textOf(row["id"]),
    bomRef: optionalText(row["bomRef"]),
    type: textOf(row["type"]),
    name: textOf(row["name"]),
    version: optionalText(row["version"]),
    purl: optionalText(row["purl"]),
    cpe: optionalText(row["cpe"]),
    supplier: optionalText(row["supplier"]),
    licenses: textsOf(row["licenses"]),
  };
}

function vulnerabilityOf(value: unknown): TrackedVulnerability {
  const row = recordOf(value, "vulnerability");

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    vulnId: textOf(row["vulnId"]),
    aliases: textsOf(row["aliases"]),
    summary: optionalText(row["summary"]),
    details: optionalText(row["details"]),
    cvssVector: optionalText(row["cvssVector"]),
    cvssVersion: optionalText(row["cvssVersion"]),
    cvssScore: optionalNumber(row["cvssScore"]),
    severity: optionalText(row["severity"]),
    epssScore: optionalNumber(row["epssScore"]),
    epssPercentile: optionalNumber(row["epssPercentile"]),
    kev: row["kev"] === true,
    kevAddedOn: optionalText(row["kevAddedOn"]),
    kevDueOn: optionalText(row["kevDueOn"]),
    affectedPurls: textsOf(row["affectedPurls"]),
    enrichedAt: optionalInstant(row["enrichedAt"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
  };
}

function exposureOf(value: unknown): VersionExposure {
  const row = recordOf(value, "version_exposure");

  return {
    vulnerabilityId: textOf(row["vulnerabilityId"]),
    vulnId: textOf(row["vulnId"]),
    severity: optionalText(row["severity"]),
    cvssScore: optionalNumber(row["cvssScore"]),
    epssScore: optionalNumber(row["epssScore"]),
    kev: row["kev"] === true,
    componentId: textOf(row["componentId"]),
    componentName: textOf(row["componentName"]),
    componentVersion: optionalText(row["componentVersion"]),
    purl: optionalText(row["purl"]),
    vexStatus: optionalEnum(row["vexStatus"], VEX_STATUSES, "VEX status"),
  };
}

function statementOf(value: unknown): StoredVexStatement {
  const row = recordOf(value, "vex_statement");

  return {
    id: textOf(row["id"]),
    productId: textOf(row["productId"]),
    versionId: optionalText(row["versionId"]),
    version: optionalText(row["version"]),
    vulnerabilityId: textOf(row["vulnerabilityId"]),
    vulnId: textOf(row["vulnId"]),
    status: enumOrThrow(row["status"], VEX_STATUSES, "VEX status"),
    justification: optionalEnum(
      row["justification"],
      VEX_JUSTIFICATIONS,
      "VEX justification",
    ),
    impactStatement: optionalText(row["impactStatement"]),
    actionStatement: optionalText(row["actionStatement"]),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
  };
}

function advisoryOf(value: unknown): Advisory {
  const row = recordOf(value, "advisory");

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    trackingId: textOf(row["trackingId"]),
    title: textOf(row["title"]),
    summary: optionalText(row["summary"]),
    productId: textOf(row["productId"]),
    severity: optionalText(row["severity"]),
    status: enumOrThrow(row["status"], ADVISORY_STATUSES, "advisory status"),
    revision: Number(row["revision"] ?? 0),
    initialReleaseAt: optionalInstant(row["initialReleaseAt"]),
    currentReleaseAt: optionalInstant(row["currentReleaseAt"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
  };
}

function revisionOf(value: unknown): AdvisoryRevision {
  const row = recordOf(value, "advisory_revision");

  return {
    number: textOf(row["number"]),
    date: requiredInstant(row["date"], "date"),
    summary: textOf(row["summary"]),
  };
}

function revisionsOf(value: unknown): AdvisoryRevision[] {
  return Array.isArray(value) ? value.map(revisionOf) : [];
}

function detailOf(value: unknown): AdvisoryDetail {
  const row = recordOf(value, "advisory");

  return {
    ...advisoryOf(row),
    vulnerabilityIds: textsOf(row["vulnerabilityIds"]),
    revisionHistory: revisionsOf(row["revisionHistory"]),
  };
}

const publishedStatus = (value: unknown): "interim" | "final" =>
  enumOrThrow(value, ["interim", "final"], "published advisory status");

function publishedStatementOf(value: unknown): PublishedStatement {
  const row = recordOf(value, "published_statement");

  return {
    version: optionalText(row["version"]),
    status: enumOrThrow(row["status"], VEX_STATUSES, "VEX status"),
    justification: optionalEnum(
      row["justification"],
      VEX_JUSTIFICATIONS,
      "VEX justification",
    ),
    impactStatement: optionalText(row["impactStatement"]),
    actionStatement: optionalText(row["actionStatement"]),
  };
}

function publishedVulnerabilityOf(value: unknown): PublishedVulnerability {
  const row = recordOf(value, "published_vulnerability");
  const statements = row["statements"];

  return {
    vulnId: textOf(row["vulnId"]),
    aliases: textsOf(row["aliases"]),
    summary: optionalText(row["summary"]),
    details: optionalText(row["details"]),
    cvssVector: optionalText(row["cvssVector"]),
    cvssVersion: optionalText(row["cvssVersion"]),
    cvssScore: optionalNumber(row["cvssScore"]),
    kevAddedOn: optionalText(row["kevAddedOn"]),
    statements: Array.isArray(statements)
      ? statements.map(publishedStatementOf)
      : [],
  };
}

function publishedOf(value: unknown): PublishedAdvisory {
  const row = recordOf(value, "published_advisory");
  const product = recordOf(row["product"], "published_advisory.product");
  const vulnerabilities = row["vulnerabilities"];

  return {
    trackingId: textOf(row["trackingId"]),
    title: textOf(row["title"]),
    summary: textOf(row["summary"]),
    status: publishedStatus(row["status"]),
    version: Number(row["version"]),
    initialReleaseAt: requiredInstant(
      row["initialReleaseAt"],
      "initialReleaseAt",
    ),
    currentReleaseAt: requiredInstant(
      row["currentReleaseAt"],
      "currentReleaseAt",
    ),
    revisionHistory: revisionsOf(row["revisionHistory"]),
    product: {
      key: textOf(product["key"]),
      name: textOf(product["name"]),
      versions: textsOf(product["versions"]),
    },
    vulnerabilities: Array.isArray(vulnerabilities)
      ? vulnerabilities.map(publishedVulnerabilityOf)
      : [],
  };
}

function summaryOf(value: unknown): PublishedAdvisorySummary {
  const row = recordOf(value, "published_advisory_summary");

  return {
    trackingId: textOf(row["trackingId"]),
    title: textOf(row["title"]),
    status: publishedStatus(row["status"]),
    version: Number(row["version"]),
    initialReleaseAt: requiredInstant(
      row["initialReleaseAt"],
      "initialReleaseAt",
    ),
    currentReleaseAt: requiredInstant(
      row["currentReleaseAt"],
      "currentReleaseAt",
    ),
  };
}

const definedOf = (
  values: Readonly<Record<string, unknown>>,
): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(values).filter(([, value]) => value !== undefined),
  );

const isNotFound = (error: { readonly kind: string }): boolean =>
  error.kind === "not_found";

/**
 * What the feed found for a vulnerability, as `record_vulnerability_enrichment`
 * takes it.
 */
async function enrichmentOf(
  feed: VulnerabilityFeed,
  vulnId: string,
  kev: Readonly<Record<string, KevEntry>>,
  signal: AbortSignal | undefined,
): Promise<Result<Record<string, unknown> | undefined>> {
  const callOptions = signal === undefined ? {} : { signal };
  const osv = await feed.osv(vulnId, callOptions);

  if (!osv.ok) {
    return osv;
  }

  const record = osv.data;

  const cveIds = [vulnId, ...(record?.aliases ?? [])].filter((id) =>
    id.startsWith("CVE-"),
  );

  const scores = await feed.epss(cveIds, callOptions);

  if (!scores.ok) {
    return scores;
  }

  const enrichment: Record<string, unknown> = {};

  if (record !== undefined) {
    const vectors = record.severity.map((entry) => parseCvss(entry.score));

    const parsed = vectors.find(
      (entry) => entry.ok && entry.data.baseScore !== undefined,
    );

    const any = parsed ?? vectors.find((entry) => entry.ok);

    if (any?.ok) {
      enrichment["cvssVector"] = any.data.vector;
      enrichment["cvssVersion"] = any.data.version;

      if (any.data.baseScore !== undefined) {
        enrichment["cvssScore"] = any.data.baseScore;
      }
    }

    Object.assign(
      enrichment,
      definedOf({
        summary: record.summary,
        details: record.details,
        aliases: [...record.aliases],
        affectedPurls: [...record.affectedPurls],
        publishedAt: record.published,
        modifiedAt: record.modified,
        references: record.references,
      }),
    );
  }

  const score = cveIds.map((id) => scores.data[id]).find(Boolean);

  if (score !== undefined) {
    enrichment["epss"] = {
      score: score.score,
      percentile: score.percentile,
      date: score.date,
    };
  }

  const listed = cveIds.map((id) => kev[id]).find(Boolean);

  if (listed !== undefined) {
    enrichment["kev"] = {
      addedOn: listed.dateAdded,
      dueOn: listed.dueDate ?? null,
      ransomware: listed.knownRansomwareUse,
    };
  }

  return ok(Object.keys(enrichment).length === 0 ? undefined : enrichment);
}

/** Creates the `advisories` block's client (ADR 0182). */
export function createAdvisories(options: AdvisoriesOptions): Advisories {
  applyTemporal(options);
  const feed = vulnerabilityFeedOf(options.feed ?? publicVulnerabilityFeed());
  const call = blockCall(options.transport, options.schema, options.mappers);

  const serviceCall = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );

  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const withTenant = <T>(
    run: (organizationId: string) => AsyncResult<T>,
  ): AsyncResult<T> => tenant().andThen(run);

  const statements = (
    productId: string,
    versionId: string | undefined,
  ): AsyncResult<StoredVexStatement[]> =>
    withTenant((organizationId) =>
      call(
        "list_vex_statements",
        {
          tenant: organizationId,
          product_id: productId,
          version_id: versionId ?? null,
        },
        (value) => recordsOf(value, "list_vex_statements").map(statementOf),
      ),
    );

  const client: Advisories = {
    saveProduct: (input) =>
      withTenant((organizationId) =>
        call(
          "save_advisory_product",
          {
            tenant: organizationId,
            key: input.key,
            name: input.name,
            vendor: input.vendor ?? null,
            description: input.description ?? null,
            archived: input.archived ?? null,
            product_id: input.id ?? null,
          },
          productOf,
        ),
      ),
    products: () =>
      withTenant((organizationId) =>
        call("list_advisory_products", { tenant: organizationId }, (value) =>
          recordsOf(value, "list_advisory_products").map(productOf),
        ),
      ),
    createVersion: (input) =>
      withTenant((organizationId) =>
        call(
          "create_product_version",
          {
            tenant: organizationId,
            product_id: input.productId,
            version: input.version,
            released_at: input.releasedAt?.toString() ?? null,
            end_of_support_at: input.endOfSupportAt?.toString() ?? null,
          },
          versionOf,
        ),
      ),
    versions: (productId) =>
      withTenant((organizationId) =>
        call(
          "list_product_versions",
          { tenant: organizationId, product_id: productId },
          (value) => recordsOf(value, "list_product_versions").map(versionOf),
        ),
      ),
    importSbom: (versionId, bom) =>
      AsyncResult.from(async () => {
        const parsed = parseCycloneDx(bom);

        if (!parsed.ok) {
          return parsed;
        }

        return withTenant((organizationId) =>
          call(
            "import_sbom",
            {
              tenant: organizationId,
              version_id: versionId,
              components: parsed.data.components.map((component) =>
                definedOf({
                  bomRef: component.bomRef,
                  type: component.type,
                  name:
                    component.group === undefined
                      ? component.name
                      : `${component.group}/${component.name}`,
                  version: component.version,
                  purl: component.purl,
                  cpe: component.cpe,
                  supplier: component.supplier,
                  licenses: component.licenses,
                  hashes: component.hashes,
                }),
              ),
              serial_number: parsed.data.serialNumber ?? null,
              spec_version: parsed.data.specVersion,
            },
            versionOf,
          ),
        );
      }),
    components: (versionId, list = {}) =>
      withTenant((organizationId) =>
        call(
          "list_sbom_components",
          {
            tenant: organizationId,
            version_id: versionId,
            max_count: list.limit ?? null,
          },
          (value) => recordsOf(value, "list_sbom_components").map(componentOf),
        ),
      ),
    saveVulnerability: (input) =>
      AsyncResult.from(async () => {
        const cvss =
          input.cvssVector === undefined
            ? undefined
            : parseCvss(input.cvssVector);

        if (cvss !== undefined && !cvss.ok) {
          return cvss;
        }

        return withTenant((organizationId) =>
          call(
            "save_vulnerability",
            {
              tenant: organizationId,
              vuln_id: input.vulnId,
              summary: input.summary ?? null,
              details: input.details ?? null,
              aliases: input.aliases ?? null,
              cvss_vector: cvss?.data.vector ?? null,
              cvss_version: cvss?.data.version ?? null,
              cvss_score: cvss?.data.baseScore ?? null,
              affected_purls: input.affectedPurls ?? null,
            },
            vulnerabilityOf,
          ),
        );
      }),
    vulnerabilities: (list = {}) =>
      withTenant((organizationId) =>
        call(
          "list_vulnerabilities",
          {
            tenant: organizationId,
            kev_only: list.kevOnly ?? false,
            max_count: list.limit ?? null,
          },
          (value) =>
            recordsOf(value, "list_vulnerabilities").map(vulnerabilityOf),
        ),
      ),
    enrichDue: (run = {}) =>
      AsyncResult.from(async (): Promise<Result<EnrichmentReport>> => {
        const organization = await tenant();

        if (!organization.ok) {
          return organization;
        }

        const due = await call(
          "vulnerabilities_due",
          {
            tenant: organization.data,
            max_count: run.limit ?? null,
            stale_after: run.staleAfter ?? null,
          },
          (value) =>
            recordsOf(value, "vulnerabilities_due").map((row) =>
              textOf(row["vulnId"]),
            ),
        );

        if (!due.ok || due.data.length === 0) {
          return due.ok
            ? ok({ checked: 0, enriched: 0, unknown: 0, failed: 0 })
            : due;
        }

        const kev = await feed.kev(
          run.signal === undefined ? {} : { signal: run.signal },
        );

        if (!kev.ok) {
          return kev;
        }

        let enriched = 0;
        let unknown = 0;
        let failed = 0;

        for (const vulnId of due.data) {
          const found = await enrichmentOf(feed, vulnId, kev.data, run.signal);

          if (!found.ok) {
            failed += 1;
            options.logger?.warn("advisory enrichment failed", {
              feed: feed.name,
              vulnId,
              kind: found.error.kind,
            });

            if (found.error.kind === "rate_limited") {
              break;
            }

            continue;
          }

          // A vulnerability no source knows is stamped, so it isn't due again at once.
          const stored = await call(
            "record_vulnerability_enrichment",
            {
              tenant: organization.data,
              vuln_id: vulnId,
              enrichment: found.data ?? {},
            },
            vulnerabilityOf,
          );

          if (!stored.ok) {
            failed += 1;
          } else if (found.data === undefined) {
            unknown += 1;
          } else {
            enriched += 1;
          }
        }

        return ok({ checked: due.data.length, enriched, unknown, failed });
      }),
    exposure: (versionId) =>
      withTenant((organizationId) =>
        call(
          "version_exposure",
          { tenant: organizationId, version_id: versionId },
          (value) => recordsOf(value, "version_exposure").map(exposureOf),
        ),
      ),
    saveVexStatement: (input) =>
      withTenant((organizationId) =>
        call(
          "save_vex_statement",
          {
            tenant: organizationId,
            product_id: input.productId,
            vulnerability_id: input.vulnerabilityId,
            status: input.status,
            version_id: input.versionId ?? null,
            justification: input.justification ?? null,
            impact_statement: input.impactStatement ?? null,
            action_statement: input.actionStatement ?? null,
          },
          statementOf,
        ),
      ),
    vexStatements: statements,
    openVex: (productId, vex) =>
      AsyncResult.from(async () => {
        const [list, products] = await Promise.all([
          statements(productId, undefined),
          client.products(),
        ]);

        if (!list.ok) {
          return list;
        }

        if (!products.ok) {
          return products;
        }

        const product = products.data.find((entry) => entry.id === productId);

        if (product === undefined) {
          return err(dbError("not_found", "advisory product not found"));
        }

        return ok(
          renderOpenVex({
            author: vex.author,
            ...(vex.role === undefined ? {} : { role: vex.role }),
            ...(vex.id === undefined ? {} : { id: vex.id }),
            ...(vex.version === undefined ? {} : { version: vex.version }),
            product: {
              key: product.key,
              ...(vex.purl === undefined ? {} : { purl: vex.purl }),
            },
            statements: list.data.map((statement) => ({
              vulnId: statement.vulnId,
              version: statement.version,
              status: statement.status,
              justification: statement.justification,
              impactStatement: statement.impactStatement,
              actionStatement: statement.actionStatement,
              timestamp: statement.updatedAt,
            })),
          }),
        );
      }),
    saveAdvisory: (input) =>
      withTenant((organizationId) =>
        call(
          "save_advisory",
          {
            tenant: organizationId,
            tracking_id: input.trackingId,
            title: input.title,
            summary: input.summary,
            product_id: input.productId,
            vulnerability_ids: input.vulnerabilityIds,
            severity: input.severity ?? null,
            advisory_id: input.id ?? null,
          },
          advisoryOf,
        ),
      ),
    publishAdvisory: (id, publish = {}) =>
      withTenant((organizationId) =>
        call(
          "publish_advisory",
          {
            tenant: organizationId,
            advisory_id: id,
            status: publish.status ?? "final",
            note: publish.note ?? null,
          },
          advisoryOf,
        ),
      ),
    advisories: (list = {}) =>
      withTenant((organizationId) =>
        call(
          "list_advisories",
          { tenant: organizationId, status: list.status ?? null },
          (value) => recordsOf(value, "list_advisories").map(advisoryOf),
        ),
      ),
    getAdvisory: (id) =>
      withTenant((organizationId) =>
        call(
          "get_advisory",
          { tenant: organizationId, advisory_id: id },
          detailOf,
        ),
      ),
    csafSource: (organizationId) => ({
      listPublished: () =>
        serviceCall(
          "list_published_advisories",
          { tenant: organizationId },
          (value) =>
            recordsOf(value, "list_published_advisories").map(summaryOf),
        ),
      getPublished: (trackingId) =>
        AsyncResult.from(async () => {
          const found = await serviceCall(
            "get_published_advisory",
            { tenant: organizationId, tracking_id: trackingId },
            (value) => (isRecord(value) ? publishedOf(value) : undefined),
          );

          return !found.ok && isNotFound(found.error) ? ok(undefined) : found;
        }),
    }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "advisories",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
