import "server-only";
import type { AdvisoryStatus } from "better-supabase/blocks/advisories";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { bsb } from "@/lib/supabase/server";

import { ADVISORIES_TAG } from "./advisories-cache";

export interface AdvisoryProductRow {
  readonly id: string;
  readonly key: string;
  readonly name: string;
  readonly vendor: string | null;
}

export interface AdvisoryRow {
  readonly id: string;
  readonly trackingId: string;
  readonly title: string;
  readonly severity: string | null;
  readonly status: AdvisoryStatus;
  readonly revision: number;
  readonly productName: string;
}

export interface VulnerabilityRow {
  readonly id: string;
  readonly vulnId: string;
  readonly summary: string | null;
  readonly severity: string | null;
  readonly cvssScore: number | null;
  readonly epssScore: number | null;
  readonly kev: boolean;
}

/** The products the organization ships advisories for. */
export async function getAdvisoryProducts(): Promise<
  readonly AdvisoryProductRow[]
> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(ADVISORIES_TAG);

  const products = await db.advisories.products().orThrow();

  return products
    .filter((product) => product.archivedAt === undefined)
    .map((product) => ({
      id: product.id,
      key: product.key,
      name: product.name,
      vendor: product.vendor ?? null,
    }));
}

/** The advisories, drafts first, with the name of their product. */
export async function getAdvisories(): Promise<readonly AdvisoryRow[]> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(ADVISORIES_TAG);

  const [advisories, products] = await Promise.all([
    db.advisories
      .page({ limit: 200 })
      .map((page) => page.items)
      .orThrow(),
    db.advisories.products().orThrow(),
  ]);

  const names = new Map(products.map((product) => [product.id, product.name]));

  return advisories.map((advisory) => ({
    id: advisory.id,
    trackingId: advisory.trackingId,
    title: advisory.title,
    severity: advisory.severity ?? null,
    status: advisory.status,
    revision: advisory.revision,
    productName: names.get(advisory.productId) ?? "",
  }));
}

/** The tracked vulnerabilities, with their CVSS, EPSS and KEV enrichment. */
export async function getVulnerabilities(): Promise<
  readonly VulnerabilityRow[]
> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(ADVISORIES_TAG);

  const vulnerabilities = await db.advisories
    .pageVulnerabilities({ limit: 100 })
    .map((page) => page.items)
    .orThrow();

  return vulnerabilities.map((vulnerability) => ({
    id: vulnerability.id,
    vulnId: vulnerability.vulnId,
    summary: vulnerability.summary ?? null,
    severity: vulnerability.severity ?? null,
    cvssScore: vulnerability.cvssScore ?? null,
    epssScore: vulnerability.epssScore ?? null,
    kev: vulnerability.kev,
  }));
}

/** One tracked vulnerability with its enrichment, serializable. */
export interface VulnerabilityDetail extends VulnerabilityRow {
  readonly details: string | null;
  readonly aliases: readonly string[];
  readonly cvssVector: string | null;
  readonly cvssVersion: string | null;
  readonly epssPercentile: number | null;
  readonly kevAddedOn: string | null;
  readonly kevDueOn: string | null;
  readonly affectedPurls: readonly string[];
  readonly enrichedAt: string | null;
  readonly updatedAt: string;
}

/**
 * One vulnerability; `undefined` when it is not tracked, `null` without an
 * organization. The block has no single get, so it reads the page the id sits
 * on, up to 200 rows.
 */
export async function getVulnerability(
  id: string,
): Promise<VulnerabilityDetail | undefined | null> {
  "use cache: private";
  const { db, session } = await bsb.cached();
  cacheTag(ADVISORIES_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const items = await db.advisories
    .pageVulnerabilities({ limit: 200 })
    .map((page) => page.items)
    .orThrow();

  const found = items.find((item) => item.id === id);

  if (found === undefined) {
    return undefined;
  }

  return {
    id: found.id,
    vulnId: found.vulnId,
    summary: found.summary ?? null,
    severity: found.severity ?? null,
    cvssScore: found.cvssScore ?? null,
    epssScore: found.epssScore ?? null,
    kev: found.kev,
    details: found.details ?? null,
    aliases: found.aliases,
    cvssVector: found.cvssVector ?? null,
    cvssVersion: found.cvssVersion ?? null,
    epssPercentile: found.epssPercentile ?? null,
    kevAddedOn: found.kevAddedOn ?? null,
    kevDueOn: found.kevDueOn ?? null,
    affectedPurls: found.affectedPurls,
    enrichedAt: found.enrichedAt?.toString() ?? null,
    updatedAt: found.updatedAt.toString(),
  };
}
