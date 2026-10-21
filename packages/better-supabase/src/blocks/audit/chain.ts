import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";

import { base64ToText } from "../../core/base64.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult } from "../../core/result.ts";
import { nowInstant } from "../../core/temporal.ts";
import {
  applyTemporal,
  blockCall,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
  toInstant,
  type BlockTemporalOptions,
} from "../shared.ts";

/**
 * Why `verify` stopped: the row changed, a link or an entry is missing, or a
 * signed head disagrees.
 */
export type AuditChainBreak = "hash" | "link" | "gap" | "checkpoint";

export type AuditChainVerdict =
  | {
      readonly valid: true;
      readonly checked: number;
      /** The last entry's position, absent for an empty range. */
      readonly seq: number | undefined;
      /**
       * The last entry's hash (hex), to compare with a checkpoint kept
       * elsewhere.
       */
      readonly hash: string | undefined;
    }
  | {
      readonly valid: false;
      readonly checked: number;
      readonly seq: number;
      /** The first broken entry, absent when the range ends early (`gap`). */
      readonly brokenAt: string | undefined;
      readonly reason: AuditChainBreak;
    };

/** A tenant's latest entry that no checkpoint covers. */
export interface AuditChainHead {
  readonly organizationId: string | undefined;
  readonly seq: number;
  readonly hash: string;
  readonly entryId: string;
}

export interface AuditCheckpoint extends AuditChainHead {
  readonly id: string;
  readonly keyId: string;
  /** The compact JWS over `sub`, `seq`, `hash`, `entry` and `iat`. */
  readonly signature: string;
  readonly createdAt: Temporal.Instant;
}

/** What signs a checkpoint: the signing-keys block's `Signer` fits. */
export interface AuditCheckpointSigner {
  signJwt(claims: Readonly<Record<string, unknown>>): AsyncResult<string>;
}

export interface AuditChainOptions extends BlockTemporalOptions {
  /** A service-role transport: the functions are granted to `service_role` only. */
  readonly transport: BlockTransport;
  /** Required for `checkpoint()`. */
  readonly signer?: AuditCheckpointSigner;
  /** The `iss` claim of each checkpoint. */
  readonly issuer?: string;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface AuditChain {
  /** Checks a tenant's entries (none: those without a tenant) in chain order. */
  verify(range?: {
    readonly organizationId?: string;
    readonly from?: Temporal.Instant;
    readonly to?: Temporal.Instant;
  }): AsyncResult<AuditChainVerdict>;
  heads(): AsyncResult<readonly AuditChainHead[]>;
  /** Signs and records every head; run it on a schedule. */
  checkpoint(): AsyncResult<readonly AuditCheckpoint[]>;
  checkpoints(options?: {
    readonly organizationId?: string;
    readonly limit?: number;
  }): AsyncResult<readonly AuditCheckpoint[]>;
}

function headOf(value: unknown): AuditChainHead {
  const row = recordOf(value, "audit_chain_heads");

  return {
    organizationId: optionalText(row["tenant"]),
    seq: Number(row["seq"]),
    hash: textOf(row["hash"]),
    entryId: textOf(row["entryId"]),
  };
}

function checkpointOf(value: unknown): AuditCheckpoint {
  const row = recordOf(value, "audit_checkpoints");

  return {
    ...headOf(row),
    id: textOf(row["id"]),
    keyId: textOf(row["keyId"]),
    signature: textOf(row["signature"]),
    createdAt: toInstant(textOf(row["createdAt"])),
  };
}

function verdictOf(value: unknown): AuditChainVerdict {
  const row = recordOf(value, "verify_audit_chain");
  const seq = row["seq"] === null ? undefined : Number(row["seq"]);

  if (row["valid"] === true) {
    return {
      valid: true,
      checked: Number(row["checked"]),
      seq,
      hash: optionalText(row["hash"]),
    };
  }

  // SAFETY: verify_audit_chain only returns these reasons.
  const reason = textOf(row["reason"]) as AuditChainBreak;

  return {
    valid: false,
    checked: Number(row["checked"]),
    seq: seq ?? 0,
    brokenAt: optionalText(row["brokenAt"]),
    reason,
  };
}

/** The `kid` of a compact JWS header, or an empty string. */
function keyIdOf(token: string): string {
  const header: unknown = JSON.parse(base64ToText(token.split(".")[0] ?? ""));

  const kid =
    typeof header === "object" && header !== null && "kid" in header
      ? header.kid
      : undefined;

  return typeof kid === "string" ? kid : "";
}

/** The audit hash chain (`blocks.audit.options.chain`), as the service role. */
export function createAuditChain(options: AuditChainOptions): AuditChain {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const heads = () =>
    call("audit_chain_heads", {}, (value) =>
      recordsOf(value, "audit_chain_heads").map(headOf),
    );

  const sign = (head: AuditChainHead, signer: AuditCheckpointSigner) =>
    signer
      .signJwt({
        ...(options.issuer === undefined ? {} : { iss: options.issuer }),
        sub: head.organizationId ?? "",
        seq: head.seq,
        hash: head.hash,
        entry: head.entryId,
        iat: Math.floor(nowInstant().epochMilliseconds / 1000),
      })
      .andThen((signature) =>
        call(
          "record_audit_checkpoint",
          {
            tenant: head.organizationId,
            seq: head.seq,
            hash: head.hash,
            key_id: keyIdOf(signature),
            signature,
          },
          checkpointOf,
        ),
      );

  return {
    verify: (range = {}) =>
      call(
        "verify_audit_chain",
        {
          tenant: range.organizationId,
          from_at: range.from?.toString(),
          to_at: range.to?.toString(),
        },
        verdictOf,
      ),
    heads,
    checkpoint: () => {
      const { signer } = options;

      if (!signer) {
        return AsyncResult.err(
          dbError("invalid_request", "checkpoint() needs a signer", {
            hint: "AUDIT_CHAIN_SIGNER",
          }),
        );
      }

      return heads().andThen((list) =>
        list.reduce<AsyncResult<AuditCheckpoint[]>>(
          (done, head) =>
            done.andThen((made) =>
              sign(head, signer).map((checkpoint) => [...made, checkpoint]),
            ),
          AsyncResult.ok<AuditCheckpoint[]>([]),
        ),
      );
    },
    checkpoints: (request = {}) =>
      call(
        "list_audit_checkpoints",
        { tenant: request.organizationId, max_rows: request.limit ?? 100 },
        (value) => recordsOf(value, "list_audit_checkpoints").map(checkpointOf),
      ),
  };
}
