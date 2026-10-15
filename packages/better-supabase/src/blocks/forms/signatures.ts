import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  enumOrThrow,
  instantArg,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export interface SignaturesOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /** `blocks.signatures.schema`, or the API schema of its wrappers. */
  readonly schema?: string;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: BlockHooks<Signatures>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

export type SignatureMethod = "drawn" | "typed" | "click";
export type SignatureOrder = "parallel" | "sequential";
export type SignatureRequestStatus =
  | "pending"
  | "completed"
  | "declined"
  | "cancelled";

export interface SignatureRequest {
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
  readonly requestedBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly completedAt?: Temporal.Instant;
}

export interface Signature {
  readonly id: string;
  readonly requestId: string;
  readonly signer: string;
  readonly method: SignatureMethod;
  readonly typedName?: string;
  /** The attachment that holds a drawn signature's image. */
  readonly imageAttachmentId?: string;
  /** SHA-256 over the request, the content hash, the signer, the method and the time. */
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
export interface SignatureRequestDetail extends SignatureRequest {
  readonly signatures: readonly Signature[];
  readonly verification: SignatureVerification;
}

export interface SignatureRequestInput {
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

export interface Signatures {
  request(input: SignatureRequestInput): AsyncResult<SignatureRequest>;
  sign(
    requestId: string,
    input: SignInput,
  ): AsyncResult<
    Signature & { readonly requestStatus: SignatureRequestStatus }
  >;
  decline(requestId: string, reason?: string): AsyncResult<SignatureRequest>;
  cancel(requestId: string): AsyncResult<SignatureRequest>;
  get(requestId: string): AsyncResult<SignatureRequestDetail>;
  /** Newest first. */
  list(
    organizationId: string,
    options?: SignatureRequestListOptions,
  ): AsyncResult<readonly SignatureRequest[]>;
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
    ...optional("requestedBy", optionalText(row["requestedBy"])),
    ...optional("completedAt", optionalInstant(row["completedAt"])),
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
export function createSignatures(options: SignaturesOptions): Signatures {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const client: Signatures = {
    request: (input) =>
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
        },
        (value) => requestOf(value, "create_signature_request"),
      ),
    sign: (requestId, input) =>
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
    decline: (requestId, reason) =>
      call(
        "decline_signature_request",
        { request_id: requestId, reason: reason ?? null },
        (value) => requestOf(value, "decline_signature_request"),
      ),
    cancel: (requestId) =>
      call("cancel_signature_request", { request_id: requestId }, (value) =>
        requestOf(value, "cancel_signature_request"),
      ),
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
      }),
    list: (organizationId, list = {}) =>
      call(
        "list_signature_requests",
        {
          tenant: organizationId,
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
      ),
  };
  return withBlockHooks(client, options.hooks, {
    block: "signatures",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
