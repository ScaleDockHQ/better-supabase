import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { Result } from "../../core/result.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type {
  CompanyProfile,
  EnrichmentProvider,
  PersonProfile,
} from "./providers.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";
import { enrichmentProviderOf } from "./providers.ts";

/** A company or person, by its subject type and id. */
export interface EnrichmentSubject {
  /** The parties block's subject type: `company` or `person`, after renames. */
  readonly type: string;
  readonly id: string;
}

/** What a provider returned for a record, as stored. */
export interface EnrichmentResult {
  readonly id: string;
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly provider: string;
  readonly status: "matched" | "not_found";
  /** The provider's profile; `{}` when nothing matched. */
  readonly data: Readonly<Record<string, unknown>>;
  /** The record's columns this result filled, such as `domain` or `title`. */
  readonly filled: readonly string[];
  readonly fetchedAt: Temporal.Instant;
  readonly requestedBy: string | undefined;
}

/** What `enrichDue` did. */
export interface EnrichmentReport {
  readonly checked: number;
  readonly matched: number;
  readonly notFound: number;
  /** Lookups the provider failed; the records stay due. */
  readonly failed: number;
}

export interface EnrichOptions {
  /** Fill the record's empty columns from a match. Default: the block's `fill`. */
  readonly fill?: boolean;
  readonly signal?: AbortSignal;
}

export interface Enrichment {
  /**
   * Looks a company or person up with the provider and stores the result. Needs
   * `enrichment.run`. A provider error is returned and nothing is stored.
   */
  enrich(
    subject: EnrichmentSubject,
    options?: EnrichOptions,
  ): AsyncResult<EnrichmentResult>;
  /**
   * Enriches the records the provider has no result for, or one older than
   * `staleAfter`, for a cron. Service role. Stops early when the provider rate
   * limits or refuses the key.
   */
  enrichDue(options?: {
    /** At most this many records. Default: 25. */
    readonly limit?: number;
    /** A Postgres interval. Default: `30 days`. */
    readonly staleAfter?: string;
    /** Only companies or only people. */
    readonly subjectType?: string;
    readonly signal?: AbortSignal;
  }): AsyncResult<EnrichmentReport>;
  /** A record's stored results, one per provider, newest first. */
  of(subject: EnrichmentSubject): AsyncResult<EnrichmentResult[]>;
}

export interface EnrichmentOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /** Looks records up; `peopleDataLabsEnrichment`, or your own. */
  readonly provider: EnrichmentProvider;
  /** Fill a record's empty columns from a match. Default: true. */
  readonly fill?: boolean;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  readonly hooks?: NoInfer<BlockHooks<Enrichment>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

function resultOf(value: unknown): EnrichmentResult {
  const row = recordOf(value, "enrichment");
  const data = row["data"];
  const filled = row["filled"];

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    subjectType: textOf(row["subjectType"]),
    subjectId: textOf(row["subjectId"]),
    provider: textOf(row["provider"]),
    status: row["status"] === "matched" ? "matched" : "not_found",
    data: recordOf(data ?? {}, "enrichment.data"),
    filled: Array.isArray(filled) ? filled.map((entry) => textOf(entry)) : [],
    fetchedAt: requiredInstant(row["fetchedAt"], "fetchedAt"),
    requestedBy: optionalText(row["requestedBy"]),
  };
}

/** A record the provider is asked about. */
interface Target {
  readonly subjectType: string;
  readonly subjectId: string;
  readonly name: string;
  readonly kind: "company" | "person";
  readonly domain?: string;
  readonly website?: string;
  readonly email?: string;
  readonly phone?: string;
  readonly companyDomain?: string;
}

function targetOf(value: unknown): Target {
  const row = recordOf(value, "enrichment_target");

  const optional = (key: string): Record<string, string> => {
    const entry = optionalText(row[key]);

    return entry === undefined ? {} : { [key]: entry };
  };

  return {
    subjectType: textOf(row["subjectType"]),
    subjectId: textOf(row["subjectId"]),
    name: textOf(row["name"]),
    kind: row["kind"] === "person" ? "person" : "company",
    ...optional("domain"),
    ...optional("website"),
    ...optional("email"),
    ...optional("phone"),
    ...optional("companyDomain"),
  };
}

const STOPPING = new Set(["rate_limited", "unauthorized"]);

export function createEnrichment(options: EnrichmentOptions): Enrichment {
  applyTemporal(options);
  const provider = enrichmentProviderOf(options.provider);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const lookup = (
    target: Target,
    signal: AbortSignal | undefined,
  ): AsyncResult<CompanyProfile | PersonProfile | undefined> => {
    const signalled = signal === undefined ? {} : { signal };

    if (target.kind === "company") {
      return provider.company({
        name: target.name,
        ...(target.domain === undefined ? {} : { domain: target.domain }),
        ...(target.website === undefined ? {} : { website: target.website }),
        ...signalled,
      });
    }

    return provider.person({
      name: target.name,
      ...(target.email === undefined ? {} : { email: target.email }),
      ...(target.phone === undefined ? {} : { phone: target.phone }),
      ...(target.companyDomain === undefined
        ? {}
        : { companyDomain: target.companyDomain }),
      ...signalled,
    });
  };

  const store = (
    target: Target,
    profile: CompanyProfile | PersonProfile | undefined,
    fill: boolean,
  ): AsyncResult<EnrichmentResult> =>
    call(
      "record_enrichment",
      {
        subject_type: target.subjectType,
        subject_id: target.subjectId,
        provider: provider.name,
        result:
          profile === undefined
            ? { status: "not_found" }
            : { status: "matched", data: profile },
        fill,
      },
      resultOf,
    );

  const enrichTarget = (
    target: Target,
    fill: boolean,
    signal: AbortSignal | undefined,
  ): AsyncResult<EnrichmentResult> =>
    AsyncResult.from(async (): Promise<Result<EnrichmentResult>> => {
      const found = await lookup(target, signal);

      return found.ok ? store(target, found.data, fill) : found;
    });

  const client: Enrichment = {
    enrich: (subject, enrich = {}) =>
      AsyncResult.from(async () => {
        const target = await call(
          "enrichment_target",
          { subject_type: subject.type, subject_id: subject.id },
          targetOf,
        );

        return target.ok
          ? enrichTarget(
              target.data,
              enrich.fill ?? options.fill ?? true,
              enrich.signal,
            )
          : target;
      }),
    enrichDue: (run = {}) =>
      AsyncResult.from(async (): Promise<Result<EnrichmentReport>> => {
        const due = await call(
          "enrichment_due",
          {
            provider: provider.name,
            max_count: run.limit ?? null,
            stale_after: run.staleAfter ?? null,
            subject_type: run.subjectType ?? null,
          },
          (value) => recordsOf(value, "enrichment_due").map(targetOf),
        );

        if (!due.ok) {
          return due;
        }

        let matched = 0;
        let notFound = 0;
        let failed = 0;

        for (const target of due.data) {
          const result = await enrichTarget(
            target,
            options.fill ?? true,
            run.signal,
          );

          if (result.ok) {
            if (result.data.status === "matched") {
              matched += 1;
            } else {
              notFound += 1;
            }
          } else {
            failed += 1;
            options.logger?.warn("enrichment failed", {
              provider: provider.name,
              subjectType: target.subjectType,
              subjectId: target.subjectId,
              kind: result.error.kind,
            });

            if (STOPPING.has(result.error.kind)) {
              break;
            }
          }
        }

        return ok({
          checked: matched + notFound + failed,
          matched,
          notFound,
          failed,
        });
      }),
    of: (subject) =>
      call(
        "enrichments_of",
        { subject_type: subject.type, subject_id: subject.id },
        (value) => recordsOf(value, "enrichments_of").map(resultOf),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "enrichment",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
