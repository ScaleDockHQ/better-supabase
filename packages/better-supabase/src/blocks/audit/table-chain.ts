import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Jwks } from "../../core/jws.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { dbError } from "../../core/errors.ts";
import { verifyCompact } from "../../core/jws.ts";
import { AsyncResult } from "../../core/result.ts";
import { nowInstant } from "../../core/temporal.ts";
import {
  applyTemporal,
  blockCall,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";

/**
 * Why `verify` stopped: the row changed, a link or a row is missing, or a
 * signed head disagrees.
 */
export type ChainBreak = "hash" | "link" | "gap" | "checkpoint";

export type ChainVerdict =
  | {
      readonly valid: true;
      readonly checked: number;
      /** The last row's position, absent for an empty chain. */
      readonly seq: number | undefined;
      /** The last row's hash (hex), to compare with a checkpoint kept elsewhere. */
      readonly hash: string | undefined;
    }
  | {
      readonly valid: false;
      readonly checked: number;
      readonly seq: number;
      readonly reason: ChainBreak;
    };

/** What signs a checkpoint: the signing-keys block's `Signer` fits. */
export interface ChainSigner {
  signJwt(claims: Readonly<Record<string, unknown>>): AsyncResult<string>;
}

/** A tenant's latest row of a chained table that no checkpoint covers. */
export interface ChainHead {
  readonly tenant: string | undefined;
  readonly seq: number;
  readonly hash: string;
}

export interface ChainCheckpoint extends ChainHead {
  readonly id: string;
  readonly keyId: string;
  /** The compact JWS over `sub`, `table`, `seq`, `hash` and `iat`. */
  readonly signature: string;
}

/** One row of a proof, with the text its hash covers. */
export interface ChainProofEntry {
  readonly seq: number;
  readonly prevHash: string | undefined;
  readonly rowHash: string;
  readonly entry: Readonly<Record<string, unknown>>;
  /** The row without its hashes and null columns, as hashed. */
  readonly hashed: string;
}

/** Everything an auditor needs to check one row offline. */
export interface ChainProof {
  readonly table: string;
  readonly tenant: string | undefined;
  readonly entries: readonly ChainProofEntry[];
  readonly checkpoint:
    | {
        readonly seq: number;
        readonly hash: string;
        readonly keyId: string;
        readonly signature: string;
      }
    | undefined;
}

export interface ChainOptions extends BlockTemporalOptions {
  /** A service-role transport: the functions are granted to `service_role` only. */
  readonly transport: BlockTransport;
  /** The chained table, `schema.name`. */
  readonly table: string;
  /** The tenant column the chain is split by; none for one chain. */
  readonly tenantColumn?: string;
  /** Required for `checkpoint()`. */
  readonly signer?: ChainSigner;
  readonly issuer?: string;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface Chain {
  verify(range?: { readonly tenant?: string }): AsyncResult<ChainVerdict>;
  heads(): AsyncResult<readonly ChainHead[]>;
  /** Signs and records every head; run it on a schedule. */
  checkpoint(): AsyncResult<readonly ChainCheckpoint[]>;
  checkpoints(options?: {
    readonly tenant?: string;
    readonly limit?: number;
  }): AsyncResult<readonly ChainCheckpoint[]>;
  /** The proof for the row at `seq`, to give to `verifyChainProof`. */
  proof(input: { seq: number; tenant?: string }): AsyncResult<ChainProof>;
}

function headOf(value: unknown): ChainHead {
  const row = recordOf(value, "chain_heads");

  return {
    tenant: optionalText(row["tenant"]),
    seq: Number(row["seq"]),
    hash: textOf(row["hash"]),
  };
}

function checkpointOf(value: unknown): ChainCheckpoint {
  const row = recordOf(value, "chain_checkpoints");

  return {
    ...headOf(row),
    id: textOf(row["id"]),
    keyId: textOf(row["keyId"]),
    signature: textOf(row["signature"]),
  };
}

function verdictOf(value: unknown): ChainVerdict {
  const row = recordOf(value, "verify_chain");
  const seq = row["seq"] === null ? undefined : Number(row["seq"]);

  if (row["valid"] === true) {
    return {
      valid: true,
      checked: Number(row["checked"]),
      seq,
      hash: optionalText(row["hash"]),
    };
  }

  // SAFETY: verify_chain only returns these reasons.
  const reason = textOf(row["reason"]) as ChainBreak;

  return {
    valid: false,
    checked: Number(row["checked"]),
    seq: seq ?? 0,
    reason,
  };
}

function proofOf(value: unknown): ChainProof {
  const row = recordOf(value, "chain_proof");
  const checkpoint = row["checkpoint"];

  return {
    table: textOf(row["table"]),
    tenant: optionalText(row["tenant"]),
    entries: recordsOf(row["entries"], "chain_proof entries").map((each) => ({
      seq: Number(each["seq"]),
      prevHash: optionalText(each["prevHash"]),
      rowHash: textOf(each["rowHash"]),
      entry: recordOf(each["entry"], "chain_proof entry"),
      hashed: textOf(each["hashed"]),
    })),
    checkpoint:
      checkpoint === null || checkpoint === undefined
        ? undefined
        : (() => {
            const found = recordOf(checkpoint, "chain_proof checkpoint");

            return {
              seq: Number(found["seq"]),
              hash: textOf(found["hash"]),
              keyId: textOf(found["keyId"]),
              signature: textOf(found["signature"]),
            };
          })(),
  };
}

function keyIdOf(token: string): string {
  const header = token.split(".")[0] ?? "";

  try {
    const parsed: unknown = JSON.parse(
      new TextDecoder().decode(
        Uint8Array.from(
          atob(header.replaceAll("-", "+").replaceAll("_", "/")),
          (character) => character.codePointAt(0) ?? 0,
        ),
      ),
    );

    return typeof parsed === "object" &&
      parsed !== null &&
      "kid" in parsed &&
      typeof parsed.kid === "string"
      ? parsed.kid
      : "";
  } catch {
    return "";
  }
}

/** The hash chain of any table tagged `chain`, as the service role. */
export function createChain(options: ChainOptions): Chain {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const base = { target: options.table, tenant_column: options.tenantColumn };

  const heads = () =>
    call("chain_heads", base, (value) =>
      (Array.isArray(value) ? value : []).map(headOf),
    );

  const sign = (head: ChainHead, signer: ChainSigner) =>
    signer
      .signJwt({
        ...(options.issuer === undefined ? {} : { iss: options.issuer }),
        sub: head.tenant ?? "",
        table: options.table,
        seq: head.seq,
        hash: head.hash,
        iat: Math.floor(nowInstant().epochMilliseconds / 1000),
      })
      .andThen((signature) =>
        call(
          "record_chain_checkpoint",
          {
            ...base,
            tenant: head.tenant,
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
      call("verify_chain", { ...base, tenant: range.tenant }, verdictOf),
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
        list.reduce<AsyncResult<ChainCheckpoint[]>>(
          (done, head) =>
            done.andThen((made) =>
              sign(head, signer).map((checkpoint) => [...made, checkpoint]),
            ),
          AsyncResult.ok<ChainCheckpoint[]>([]),
        ),
      );
    },
    checkpoints: (request = {}) =>
      call(
        "list_chain_checkpoints",
        {
          target: options.table,
          tenant: request.tenant,
          max_rows: request.limit ?? 100,
        },
        (value) => (Array.isArray(value) ? value : []).map(checkpointOf),
      ),
    proof: ({ seq, tenant }) =>
      call("chain_proof", { ...base, tenant, seq }, proofOf),
  };
}

const encoder = new TextEncoder();

function hexOf(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function bytesOf(hex: string | undefined): Uint8Array {
  if (hex === undefined || hex === "") {
    return new Uint8Array();
  }

  return Uint8Array.from(hex.match(/../gu) ?? [], (pair) =>
    Number.parseInt(pair, 16),
  );
}

/** Why `verifyChainProof` refused a proof. */
export type ChainProofError = ChainBreak | "empty" | "signature" | "unsigned";

export type ChainProofVerdict =
  | { readonly valid: true; readonly signed: boolean; readonly checked: number }
  | {
      readonly valid: false;
      readonly reason: ChainProofError;
      readonly seq?: number;
    };

/**
 * Checks a proof without a database: each row's hash against the row text and
 * the one before it, the links, and the checkpoint's signature against `jwks`.
 * Runs on WebCrypto only, so an auditor can run it anywhere. `requireSigned`
 * refuses a proof the chain head isn't signed for.
 */
export async function verifyChainProof(
  proof: ChainProof,
  jwks: Jwks,
  options: { readonly requireSigned?: boolean } = {},
): Promise<ChainProofVerdict> {
  const [first] = proof.entries;

  if (first === undefined) {
    return { valid: false, reason: "empty" };
  }

  let previous: ChainProofEntry | undefined;

  for (const entry of proof.entries) {
    if (previous !== undefined && entry.seq !== previous.seq + 1) {
      return { valid: false, reason: "gap", seq: entry.seq };
    }

    if (previous !== undefined && entry.prevHash !== previous.rowHash) {
      return { valid: false, reason: "link", seq: entry.seq };
    }

    const material = new Uint8Array([
      ...bytesOf(entry.prevHash),
      ...encoder.encode(entry.hashed),
    ]);

    if (
      hexOf(await crypto.subtle.digest("SHA-256", material)) !== entry.rowHash
    ) {
      return { valid: false, reason: "hash", seq: entry.seq };
    }

    previous = entry;
  }

  const { checkpoint } = proof;

  if (checkpoint === undefined) {
    return options.requireSigned
      ? { valid: false, reason: "unsigned" }
      : { valid: true, signed: false, checked: proof.entries.length };
  }

  if (
    previous?.seq !== checkpoint.seq ||
    previous.rowHash !== checkpoint.hash
  ) {
    return { valid: false, reason: "checkpoint", seq: checkpoint.seq };
  }

  try {
    const { payload } = await verifyCompact(checkpoint.signature, jwks);

    if (
      payload["hash"] !== checkpoint.hash ||
      payload["seq"] !== checkpoint.seq
    ) {
      return { valid: false, reason: "signature", seq: checkpoint.seq };
    }
  } catch {
    return { valid: false, reason: "signature", seq: checkpoint.seq };
  }

  return { valid: true, signed: true, checked: proof.entries.length };
}
