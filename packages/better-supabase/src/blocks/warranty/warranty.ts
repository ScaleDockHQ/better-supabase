import type {
  Count,
  FacetResult,
  ListPage,
  PageOptions,
} from "../../core/block-helpers.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { CountOptions, FacetOptions } from "../../core/entity-list.ts";
import type { AsyncResult } from "../../core/result.ts";
import type {
  WarrantyDecision,
  WarrantyStatus,
} from "../../sql/modules/warranty-values.ts";
import type { BlockOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { entityList } from "../../core/entity-list.ts";
import {
  WARRANTY_DECISIONS,
  WARRANTY_STATUSES,
} from "../../sql/modules/warranty-values.ts";
import {
  applyTemporal,
  bigintOf,
  blockCall,
  enumOrThrow,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";
import { warrantyClaimListSurface } from "./lists.ts";

/** What `createClaim` takes. `amount` is minor units. */
export interface WarrantyClaimInput {
  readonly title: string;
  /** The asset the claim covers. */
  readonly assetId: string;
  /** Covered amount, in the currency's minor units. */
  readonly amount: bigint;
  /** An ISO 4217 code, such as `EUR`. */
  readonly currency: string;
  /** The supplier. A claim names this, `manufacturer`, or both. */
  readonly supplierId?: string;
  /** The manufacturer. A claim names this, `supplierId`, or both. */
  readonly manufacturer?: string;
}

/** A filter for `list`. */
export interface WarrantyClaimListOptions {
  readonly status?: WarrantyStatus;
  readonly assetId?: string;
  readonly limit?: number;
  readonly offset?: number;
}

/** A warranty claim. */
export interface WarrantyClaim {
  readonly id: string;
  readonly organizationId: string;
  readonly title: string;
  readonly assetId: string;
  readonly amount: bigint;
  readonly currency: string;
  readonly status: WarrantyStatus;
  readonly supplierId?: string;
  readonly manufacturer?: string;
  readonly decision?: string;
  readonly decidedAt?: Temporal.Instant;
  readonly decidedBy?: string;
}

/** Warranty claims for an organization's assets. */
export interface Warranty {
  /** Files a draft claim. Needs `warranty.write`. */
  createClaim(input: WarrantyClaimInput): AsyncResult<WarrantyClaim>;
  /** Moves a draft claim to `submitted`. Needs `warranty.write`. */
  submit(id: string): AsyncResult<WarrantyClaim>;
  /**
   * Moves `submitted` to `approved` or `denied`, or either of those to
   * `closed`. Approving or denying stores `decision`. Needs `warranty.decide`.
   */
  decide(
    id: string,
    status: WarrantyDecision,
    decision?: string,
  ): AsyncResult<WarrantyClaim>;
  /** Claims of the caller's organization, newest first. Needs `warranty.read`. */
  list(
    options?: WarrantyClaimListOptions,
  ): AsyncResult<readonly WarrantyClaim[]>;
  /** One claim by id. Needs `warranty.read`. */
  get(id: string): AsyncResult<WarrantyClaim>;
  /**
   * One keyset page of claims, in the order of `sort` (newest first by
   * default): the rows, `hasMore` and a `nextCursor` to pass as `after`. Needs
   * `warranty.read`.
   */
  page(options?: PageOptions): AsyncResult<ListPage<WarrantyClaim>>;
  /** The claims per status, under the page's filters. */
  facets(options?: FacetOptions): AsyncResult<readonly FacetResult[]>;
  /** How many claims match the page's filters. */
  count(options?: CountOptions): AsyncResult<Count>;
}

/** What `createWarranty` takes: a transport and the caller's organization. */
export interface WarrantyOptions extends BlockOptions {
  readonly hooks?: BlockHooks<Warranty>;
}

function claimOf(value: unknown, fn: string): WarrantyClaim {
  const row = recordOf(value, fn);
  const supplierId = optionalText(row["supplierId"]);
  const manufacturer = optionalText(row["manufacturer"]);
  const decision = optionalText(row["decision"]);
  const decidedAt = optionalInstant(row["decidedAt"]);
  const decidedBy = optionalText(row["decidedBy"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    title: textOf(row["title"]),
    assetId: textOf(row["assetId"]),
    amount: bigintOf(row["amount"], "amount"),
    currency: textOf(row["currency"]),
    status: enumOrThrow(row["status"], WARRANTY_STATUSES, "status"),
    ...(supplierId === undefined ? {} : { supplierId }),
    ...(manufacturer === undefined ? {} : { manufacturer }),
    ...(decision === undefined ? {} : { decision }),
    ...(decidedAt === undefined ? {} : { decidedAt }),
    ...(decidedBy === undefined ? {} : { decidedBy }),
  };
}

/**
 * Warranty claims: a supplier or manufacturer, an asset, a covered amount, a
 * status and a decision. Attachments use the claim subject.
 */
export function createWarranty(options: WarrantyOptions): Warranty {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);
  const claim = (fn: string) => (value: unknown) => claimOf(value, fn);

  const claims = entityList({
    entity: "warranty_claim",
    surface: warrantyClaimListSurface,
    call,
    tenant,
    fn: "list_warranty_claims",
    rowOf: claimOf,
  });

  const client: Warranty = {
    createClaim: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "create_warranty_claim",
          {
            tenant: organizationId,
            input: {
              title: input.title,
              assetId: input.assetId,
              amount: input.amount.toString(),
              currency: input.currency,
              ...(input.supplierId === undefined
                ? {}
                : { supplierId: input.supplierId }),
              ...(input.manufacturer === undefined
                ? {}
                : { manufacturer: input.manufacturer }),
            },
          },
          claim("create_warranty_claim"),
        ),
      ),
    submit: (id) =>
      call(
        "submit_warranty_claim",
        { claim_id: id },
        claim("submit_warranty_claim"),
      ),
    decide: (id, status, decision) =>
      call(
        "decide_warranty_claim",
        {
          claim_id: id,
          next_status: enumOrThrow(status, WARRANTY_DECISIONS, "status"),
          decision: decision ?? null,
        },
        claim("decide_warranty_claim"),
      ),
    list: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_warranty_claims",
          {
            tenant: organizationId,
            filters: {
              ...(list.status === undefined ? {} : { status: list.status }),
              ...(list.assetId === undefined ? {} : { assetId: list.assetId }),
              ...(list.limit === undefined ? {} : { limit: list.limit }),
              ...(list.offset === undefined ? {} : { offset: list.offset }),
            },
          },
          (value) =>
            recordsOf(value, "list_warranty_claims").map((row) =>
              claimOf(row, "list_warranty_claims"),
            ),
        ),
      ),
    get: (id) =>
      call("get_warranty_claim", { claim_id: id }, claim("get_warranty_claim")),
    page: claims.page,
    facets: claims.facets,
    count: claims.count,
  };

  return withBlockHooks(client, options.hooks);
}
