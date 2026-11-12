import "server-only";
import type { AdvisoryStatus } from "better-supabase/blocks/advisories";

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
    db.advisories.advisories().orThrow(),
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
    .vulnerabilities({ limit: 100 })
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
