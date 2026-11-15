import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type {
  Count,
  FacetResult,
  ListPage,
  PageOptions,
} from "../../core/block-helpers.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTenantOptions } from "../../core/block-tenant.ts";
import type {
  CountOptions,
  FacetOptions,
  TenantOption,
} from "../../core/entity-list.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { entityList, tenantOrOption } from "../../core/entity-list.ts";
import { AsyncResult } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";
import { signatureRequestListSurface } from "./lists.ts";

export interface SignaturesOptions<
  S extends StandardSchemaV1 | undefined = undefined,
>
  extends BlockOptions, BlockTenantOptions {
  /**
   * A Standard Schema for the request's extra columns (columns the app's schema
   * files add to the table), keyed by database name. It types and parses them
   * on the request reads, and validates them on `request`.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Signatures<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

export type SignatureMethod = "drawn" | "typed" | "click";

export type SignatureOrder = "parallel" | "sequential";

export type SignatureRequestStatus =
  | "pending"
  | "completed"
  | "declined"
  | "cancelled";

/** A request. `F` types the extra columns the `fields` schema describes. */
export interface SignatureRequest<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  /** The frozen version the signers sign. */
  readonly versionId: string;
  /** The version's content hash when the request was made. */
  readonly contentHash: string;
  readonly signers: readonly string[];
  readonly order: SignatureOrder;
  readonly status: SignatureRequestStatus;
  readonly approvalRequestId?: string;
  readonly message?: string;
  /** What signing means, such as `approved` (`options.meanings`). */
  readonly meaning?: string;
  readonly requestedBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly completedAt?: Temporal.Instant;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

export interface Signature {
  readonly id: string;
  readonly requestId: string;
  readonly signer: string;
  readonly method: SignatureMethod;
  readonly typedName?: string;
  /** The attachment that holds a drawn signature's image. */
  readonly imageAttachmentId?: string;
  /**
   * SHA-256 over the request, the content hash, the signer, the method and the
   * time.
   */
  readonly signedHash: string;
  readonly ip?: string;
  readonly userAgent?: string;
  readonly signedAt: Temporal.Instant;
}

export interface SignatureVerification {
  /** The signed version is unchanged and every signature hash matches. */
  readonly valid: boolean;
  /** The signed version's content still hashes to the requested hash. */
  readonly contentMatches: boolean;
  /** The record has a newer version than the one signed. */
  readonly changedSince: boolean;
  readonly latestVersionId?: string;
  readonly signatures: readonly {
    readonly id: string;
    readonly signer: string;
    readonly valid: boolean;
  }[];
}

/** A request with its signatures and their verification, from `get`. */
export interface SignatureRequestDetail<
  F extends object = Record<never, never>,
> extends SignatureRequest<F> {
  readonly signatures: readonly Signature[];
  readonly verification: SignatureVerification;
}

export interface SignatureRequestInput<
  F extends object = Record<never, never>,
> {
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  /** Members of the organization, in signing order for `sequential`. */
  readonly signers: readonly string[];
  /** Default: a new snapshot of the record's versioned columns. */
  readonly versionId?: string;
  /** Default: `parallel`. */
  readonly order?: SignatureOrder;
  /** An approval request on the same record that a signer's signature decides. */
  readonly approvalRequestId?: string;
  readonly message?: string;
  /**
   * What signing means, one of `blocks.signatures.options.meanings`. The
   * defaults are `authored`, `reviewed`, `approved`, `released`, `acknowledged`
   * and `agreed`.
   */
  readonly meaning?: string;
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
}

export type SignInput =
  | { readonly method: "click" }
  | { readonly method: "typed"; readonly typedName: string }
  | { readonly method: "drawn"; readonly imageAttachmentId: string };

export interface SignatureRequestListOptions {
  readonly subjectType?: string;
  readonly subjectId?: string;
  readonly status?: SignatureRequestStatus;
  /** Only the requests the caller is asked to sign. */
  readonly mine?: boolean;
  readonly pageSize?: number;
  /** Requests created before this time, for the next page. */
  readonly before?: Temporal.Instant;
}

export interface Signatures<F extends object = Record<never, never>> {
  request(input: SignatureRequestInput<F>): AsyncResult<SignatureRequest<F>>;
  sign(input: {
    requestId: string;
    input: SignInput;
  }): AsyncResult<
    Signature & { readonly requestStatus: SignatureRequestStatus }
  >;
  decline(input: {
    requestId: string;
    reason?: string | undefined;
  }): AsyncResult<SignatureRequest<F>>;
  cancel(requestId: string): AsyncResult<SignatureRequest<F>>;
  get(requestId: string): AsyncResult<SignatureRequestDetail<F>>;
  /**
   * Newest first.
   *
   * @deprecated Use `requestPage`, which pages by keyset and takes `q`, sorts,
   * array filters and a count (ADR 1077).
   */
  list(
    input: {
      organizationId?: string | undefined;
    } & SignatureRequestListOptions,
  ): AsyncResult<readonly SignatureRequest<F>[]>;
  /**
   * One keyset page of requests, newest first. `filters` takes `status`,
   * `subjectType` and `subjectId` (lists) and `mine: ["true"]` for the requests
   * the caller is asked to sign; `q` searches the subject id and the message.
   * The organization comes from `organizationId` or `options.tenant`.
   */
  requestPage(
    options?: PageOptions & TenantOption,
  ): AsyncResult<ListPage<SignatureRequest<F>>>;
  /** The values of each facet (`status`) under the page's filters. */
  requestFacets(
    options?: FacetOptions & TenantOption,
  ): AsyncResult<readonly FacetResult[]>;
  /** How many requests match the page's filters. */
  requestCount(options?: CountOptions & TenantOption): AsyncResult<Count>;
}

const STATUSES: readonly SignatureRequestStatus[] = [
  "pending",
  "completed",
  "declined",
  "cancelled",
];

const ORDERS: readonly SignatureOrder[] = ["parallel", "sequential"];
const METHODS: readonly SignatureMethod[] = ["drawn", "typed", "click"];

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

const textsOf = (value: unknown): readonly string[] =>
  Array.isArray(value) ? value.map((item) => textOf(item)) : [];

function requestOf(value: unknown, fn: string): SignatureRequest {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    subjectType: textOf(row["subjectType"]),
    subjectId: textOf(row["subjectId"]),
    versionId: textOf(row["versionId"]),
    contentHash: textOf(row["contentHash"]),
    signers: textsOf(row["signers"]),
    order: enumOrThrow(row["order"], ORDERS, "signing order"),
    status: enumOrThrow(row["status"], STATUSES, "signature request status"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional("approvalRequestId", optionalText(row["approvalRequestId"])),
    ...optional("message", optionalText(row["message"])),
    ...optional("meaning", optionalText(row["meaning"])),
    ...optional("requestedBy", optionalText(row["requestedBy"])),
    ...optional("completedAt", optionalInstant(row["completedAt"])),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
  };
}

function signatureOf(value: unknown, fn: string): Signature {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    requestId: textOf(row["requestId"]),
    signer: textOf(row["signer"]),
    method: enumOrThrow(row["method"], METHODS, "signature method"),
    signedHash: textOf(row["signedHash"]),
    signedAt: requiredInstant(row["signedAt"], "signedAt"),
    ...optional("typedName", optionalText(row["typedName"])),
    ...optional("imageAttachmentId", optionalText(row["imageAttachmentId"])),
    ...optional("ip", optionalText(row["ip"])),
    ...optional("userAgent", optionalText(row["userAgent"])),
  };
}

function verificationOf(value: unknown, fn: string): SignatureVerification {
  const row = recordOf(value, fn);

  return {
    valid: row["valid"] === true,
    contentMatches: row["contentMatches"] === true,
    changedSince: row["changedSince"] === true,
    signatures: recordsOf(row["signatures"], fn).map((item) => ({
      id: textOf(item["id"]),
      signer: textOf(item["signer"]),
      valid: item["valid"] === true,
    })),
    ...optional("latestVersionId", optionalText(row["latestVersionId"])),
  };
}

/** The `signatures` SQL module as typed calls. */
export function createSignatures<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: SignaturesOptions<S>): Signatures<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "signature request fields",
  );

  // SAFETY: `requestOf` reads the extra columns as a record; `fields.rows` types them next.
  const requests = entityList<SignatureRequest<F>, TenantOption>({
    entity: "signature_request",
    surface: signatureRequestListSurface,
    call,
    tenant: tenantOrOption(options.tenant),
    fn: "page_signature_requests",
    rowOf: (row, fn) => requestOf(row, fn) as SignatureRequest<F>,
  });

  const client: Signatures<F> = {
    request: (input) =>
      fields
        .args(input.fields)
        .andThen((checked) =>
          call(
            "create_signature_request",
            {
              tenant: input.organizationId,
              subject_type: input.subjectType,
              subject_id: input.subjectId,
              signers: input.signers,
              version_id: input.versionId ?? null,
              sign_order: input.order ?? "parallel",
              approval_request_id: input.approvalRequestId ?? null,
              message: input.message ?? null,
              meaning: input.meaning ?? null,
              fields: checked,
            },
            (value) => requestOf(value, "create_signature_request"),
          ).andThen(fields.row),
        ),
    sign: ({ requestId, input }) =>
      call(
        "sign_signature",
        {
          request_id: requestId,
          method: input.method,
          typed_name: input.method === "typed" ? input.typedName : null,
          image_attachment_id:
            input.method === "drawn" ? input.imageAttachmentId : null,
        },
        (value) => ({
          ...signatureOf(value, "sign_signature"),
          requestStatus: enumOrThrow(
            recordOf(value, "sign_signature")["requestStatus"],
            STATUSES,
            "signature request status",
          ),
        }),
      ),
    decline: ({ requestId, reason }) =>
      call(
        "decline_signature_request",
        { request_id: requestId, reason: reason ?? null },
        (value) => requestOf(value, "decline_signature_request"),
      ).andThen(fields.row),
    cancel: (requestId) =>
      call("cancel_signature_request", { request_id: requestId }, (value) =>
        requestOf(value, "cancel_signature_request"),
      ).andThen(fields.row),
    get: (requestId) =>
      call("get_signature_request", { request_id: requestId }, (value) => {
        const row = recordOf(value, "get_signature_request");

        return {
          ...requestOf(row, "get_signature_request"),
          signatures: recordsOf(row["signatures"], "get_signature_request").map(
            (item) => signatureOf(item, "get_signature_request"),
          ),
          verification: verificationOf(
            row["verification"],
            "get_signature_request",
          ),
        };
      }).andThen(fields.row),
    // oxlint-disable-next-line typescript/no-deprecated -- the deprecated alias is still implemented until 0.70 (ADR 1077)
    list: ({ organizationId, ...list }) =>
      (organizationId === undefined
        ? requireTenant(options.tenant)
        : AsyncResult.ok(organizationId)
      ).andThen((tenant) =>
        call(
          "list_signature_requests",
          {
            tenant,
            subject_type: list.subjectType ?? null,
            subject_id: list.subjectId ?? null,
            status: list.status ?? null,
            mine: list.mine ?? false,
            page_size: list.pageSize ?? null,
            before: instantArg(list.before) ?? null,
          },
          (value) =>
            recordsOf(value, "list_signature_requests").map((row) =>
              requestOf(row, "list_signature_requests"),
            ),
        ).andThen(fields.rows),
      ),
    requestPage: (page = {}) =>
      requests
        .page(page)
        .andThen((read) =>
          fields.rows(read.items).map((items) => ({ ...read, items })),
        ),
    requestFacets: requests.facets,
    requestCount: requests.count,
  };

  return withBlockHooks(client, options.hooks, {
    block: "signatures",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
