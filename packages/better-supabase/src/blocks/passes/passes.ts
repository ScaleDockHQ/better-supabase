import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTenantOptions } from "../../core/block-tenant.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { DbError, ErrorMapper } from "../../core/errors.ts";
import type { Jwks } from "../../core/jws.ts";
import type { Logger } from "../../core/logger.ts";
import type { SubjectRef } from "../../schema/types.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type { Signer } from "../signing-keys/signing-keys.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { dbError } from "../../core/errors.ts";
import { JwsError, verifyCompact } from "../../core/jws.ts";
import { AsyncResult } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  instantArg,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";
import { jwtType } from "../signing-keys/signing-keys.ts";

/** The `typ` header of a pass token: `vnd.pass+jwt`. */
export const PASS_TOKEN_TYPE: string = jwtType("pass");

export type PassStatus = "active" | "revoked";

/** How a pass reached the door. `manual`: staff looked the holder up. */
export type PassMethod = "qr" | "nfc" | "manual";

/** Why a scan turned the holder away. */
export type PassRejection =
  | "invalid"
  | "revoked"
  | "not_yet_valid"
  | "expired"
  | "used_up"
  | "booking_cancelled"
  | "booking_unconfirmed"
  | "outside_window"
  | "wrong_resource"
  | "full";

export interface PassesOptions
  extends BlockTemporalOptions, BlockTenantOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /**
   * Signs pass tokens, on the server: `signingKeys.signer({ type:
   * "organization", id })`. `token` fails without it.
   */
  readonly signer?: Signer;
  /**
   * The keys a scanner verifies tokens with: the JWKS the app publishes, or a
   * function that loads it. `checkIn` fails without it.
   */
  readonly jwks?: Jwks | (() => Promise<Jwks>);
  /**
   * The longest a token stays valid; a pass that outlives it gets a new token
   * from `token`. Default: 30 days.
   */
  readonly tokenLifetime?: Temporal.Duration;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Passes>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

/**
 * An admission pass: a ticket for a booking, or a pass for a resource or
 * record.
 */
export interface Pass {
  readonly id: string;
  readonly organizationId: string;
  /** Free text such as `ticket`, `membership` or `visitor`. */
  readonly kind: string;
  readonly holderUserId?: string;
  readonly holderName?: string;
  readonly holderEmail?: string;
  /** The record the pass is for, such as an event or a membership. */
  readonly subject?: SubjectRef;
  readonly bookingId?: string;
  readonly resourceId?: string;
  /** How many check-ins it admits; missing means no limit. */
  readonly usesAllowed?: number;
  readonly uses: number;
  readonly validFrom: Temporal.Instant;
  readonly validUntil?: Temporal.Instant;
  readonly status: PassStatus;
  readonly issuedBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  readonly revokedAt?: Temporal.Instant;
}

/** A pass with the nonce its token carries, for the holder or a manager. */
export interface IssuedPass extends Pass {
  readonly nonce: string;
}

/** One scan at a door, admitted or not. */
export interface PassCheckIn {
  readonly id: string;
  readonly organizationId: string;
  readonly passId: string;
  readonly resourceId?: string;
  readonly bookingId?: string;
  readonly gate?: string;
  readonly method: PassMethod;
  readonly admitted: boolean;
  readonly reason?: PassRejection;
  readonly checkedInBy?: string;
  readonly createdAt: Temporal.Instant;
}

/** What `checkIn` returns: the scan and the pass after it. */
export interface PassScan extends PassCheckIn {
  readonly pass: Pass;
}

/** How full a resource is now, for a door display. */
export interface PassOccupancy {
  readonly resourceId: string;
  readonly capacity: number;
  /** Seats held or confirmed by bookings running now. */
  readonly booked: number;
  /** Passes without a booking admitted within the drop-in length. */
  readonly dropIns: number;
  readonly free: number;
}

export interface PassInput {
  /** Default `ticket`. */
  readonly kind?: string;
  readonly holderUserId?: string;
  readonly holderName?: string;
  readonly holderEmail?: string;
  readonly subject?: SubjectRef;
  /**
   * A ticket for this booking: valid until the booking ends and good for one
   * check-in unless the other fields say otherwise.
   */
  readonly bookingId?: string;
  /** A pass for this resource; check-ins count against its capacity. */
  readonly resourceId?: string;
  readonly usesAllowed?: number;
  readonly validFrom?: Temporal.Instant;
  readonly validUntil?: Temporal.Instant;
}

export interface PassListOptions {
  readonly holderUserId?: string;
  readonly subject?: SubjectRef;
  readonly status?: PassStatus;
  /** Pages back from a pass's `createdAt`. */
  readonly before?: Temporal.Instant;
  readonly pageSize?: number;
}

export interface PassCheckInOptions {
  /** Default `qr`. */
  readonly method?: Exclude<PassMethod, "manual">;
  /** The door or scanner, for the log. */
  readonly gate?: string;
  /** The resource the door belongs to: a pass for another one is turned away. */
  readonly resourceId?: string;
}

export interface PassManualCheckInOptions {
  readonly gate?: string;
  readonly resourceId?: string;
}

export interface PassCheckInListOptions {
  readonly before?: Temporal.Instant;
  readonly pageSize?: number;
}

/** The claims of a pass token. */
export type PassTokenClaims = {
  /** The pass. */
  readonly sub: string;
  /** The pass's nonce; revoking or reissuing the pass changes what it matches. */
  readonly jti: string;
  readonly org: string;
  readonly kind: string;
  readonly name?: string;
  readonly nbf: number;
  readonly exp: number;
};

export interface Passes {
  /** Issues a pass in the block's tenant. Needs `passes.manage`. */
  issue(input: PassInput): AsyncResult<IssuedPass>;
  /** Needs `passes.manage`. Its tokens stop admitting. */
  revoke(passId: string): AsyncResult<Pass>;
  /** One pass with its nonce, for its holder or a manager; `null` otherwise. */
  get(passId: string): AsyncResult<IssuedPass | null>;
  /** The tenant's passes, newest first. Needs `passes.read`. */
  list(options?: PassListOptions): AsyncResult<readonly Pass[]>;
  /** The caller's live passes, for a wallet screen. */
  mine(): AsyncResult<readonly IssuedPass[]>;
  /**
   * The signed token to put in a QR code or on an NFC tag. Needs `signer`. It
   * expires with the pass, or after `tokenLifetime`.
   */
  token(pass: IssuedPass): AsyncResult<string>;
  /**
   * Verifies a scanned token against `jwks`, then checks the holder in. Needs
   * `passes.check_in`. A bad signature fails with `PASS_TOKEN_INVALID` and an
   * expired token with `PASS_TOKEN_EXPIRED`, before the database is asked; a
   * pass the database turns away comes back with `admitted: false` and a
   * `reason`.
   */
  checkIn(token: string, options?: PassCheckInOptions): AsyncResult<PassScan>;
  /** Checks a holder in by pass id, for staff at the door. */
  checkInManually(
    passId: string,
    options?: PassManualCheckInOptions,
  ): AsyncResult<PassScan>;
  /** A pass's scans, newest first. */
  checkIns(
    passId: string,
    options?: PassCheckInListOptions,
  ): AsyncResult<readonly PassCheckIn[]>;
  /** How full a resource is now. Needs the bookings block. */
  occupancy(resourceId: string): AsyncResult<PassOccupancy>;
}

const STATUSES: readonly PassStatus[] = ["active", "revoked"];

const METHODS: readonly PassMethod[] = ["qr", "nfc", "manual"];

const REJECTIONS: readonly PassRejection[] = [
  "invalid",
  "revoked",
  "not_yet_valid",
  "expired",
  "used_up",
  "booking_cancelled",
  "booking_unconfirmed",
  "outside_window",
  "wrong_resource",
  "full",
];

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

function countOf(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isInteger(value)) {
    throw new TypeError(`${field} is not an integer`);
  }

  return value;
}

function optionalCount(value: unknown, field: string): number | undefined {
  return value === null || value === undefined
    ? undefined
    : countOf(value, field);
}

function subjectOf(row: Record<string, unknown>): SubjectRef | undefined {
  const type = optionalText(row["subjectType"]);
  const id = optionalText(row["subjectId"]);

  return type === undefined || id === undefined ? undefined : { type, id };
}

function passOf(value: unknown, fn: string): Pass {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    kind: textOf(row["kind"]),
    uses: countOf(row["uses"], "uses"),
    validFrom: requiredInstant(row["validFrom"], "validFrom"),
    status: enumOrThrow(row["status"], STATUSES, "pass status"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("holderUserId", optionalText(row["holderUserId"])),
    ...optional("holderName", optionalText(row["holderName"])),
    ...optional("holderEmail", optionalText(row["holderEmail"])),
    ...optional("subject", subjectOf(row)),
    ...optional("bookingId", optionalText(row["bookingId"])),
    ...optional("resourceId", optionalText(row["resourceId"])),
    ...optional(
      "usesAllowed",
      optionalCount(row["usesAllowed"], "usesAllowed"),
    ),
    ...optional("validUntil", optionalInstant(row["validUntil"])),
    ...optional("issuedBy", optionalText(row["issuedBy"])),
    ...optional("revokedAt", optionalInstant(row["revokedAt"])),
  };
}

function issuedOf(value: unknown, fn: string): IssuedPass {
  return { ...passOf(value, fn), nonce: textOf(recordOf(value, fn)["nonce"]) };
}

function checkInOf(value: unknown, fn: string): PassCheckIn {
  const row = recordOf(value, fn);
  const reason = optionalText(row["reason"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    passId: textOf(row["passId"]),
    method: enumOrThrow(row["method"], METHODS, "pass method"),
    admitted: row["admitted"] === true,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional("resourceId", optionalText(row["resourceId"])),
    ...optional("bookingId", optionalText(row["bookingId"])),
    ...optional("gate", optionalText(row["gate"])),
    ...optional(
      "reason",
      reason === undefined
        ? undefined
        : enumOrThrow(reason, REJECTIONS, "pass rejection"),
    ),
    ...optional("checkedInBy", optionalText(row["checkedInBy"])),
  };
}

function scanOf(value: unknown): PassScan {
  return {
    ...checkInOf(value, "check_in_pass"),
    pass: passOf(recordOf(value, "check_in_pass")["pass"], "check_in_pass"),
  };
}

const epochSeconds = (instant: Temporal.Instant): number =>
  Math.floor(instant.epochMilliseconds / 1000);

const DEFAULT_LIFETIME_DAYS = 30;

function tokenError(hint: string, message: string): DbError {
  return dbError("invalid_input", message, { hint });
}

/** The pass id and nonce in a verified token, or the reason it fails. */
async function readToken(
  token: string,
  jwks: Jwks | (() => Promise<Jwks>),
): Promise<
  | { readonly ok: true; readonly sub: string; readonly jti: string }
  | { readonly ok: false; readonly error: DbError }
> {
  let payload: Record<string, unknown>;

  try {
    const keys = typeof jwks === "function" ? await jwks() : jwks;

    ({ payload } = await verifyCompact(token, keys, { typ: PASS_TOKEN_TYPE }));
  } catch (cause) {
    if (cause instanceof JwsError) {
      return {
        ok: false,
        error: tokenError("PASS_TOKEN_INVALID", cause.message),
      };
    }

    throw cause;
  }

  const now = Date.now() / 1000;
  const { sub, jti, exp, nbf } = payload;

  if (typeof sub !== "string" || typeof jti !== "string") {
    return {
      ok: false,
      error: tokenError("PASS_TOKEN_INVALID", "The token is not a pass token"),
    };
  }

  if (typeof exp === "number" && exp <= now) {
    return {
      ok: false,
      error: tokenError("PASS_TOKEN_EXPIRED", "The pass token has expired"),
    };
  }

  if (typeof nbf === "number" && nbf > now) {
    return {
      ok: false,
      error: tokenError(
        "PASS_TOKEN_EXPIRED",
        "The pass token is not valid yet",
      ),
    };
  }

  return { ok: true, sub, jti };
}

/** The `passes` SQL module as typed calls. */
export function createPasses(options: PassesOptions): Passes {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const checkInCall = (
    passId: string,
    nonce: string | null,
    method: PassMethod,
    gate: string | undefined,
    resourceId: string | undefined,
  ): AsyncResult<PassScan> =>
    call(
      "check_in_pass",
      {
        pass_id: passId,
        nonce,
        method,
        gate: gate ?? null,
        resource_id: resourceId ?? null,
      },
      scanOf,
    );

  const client: Passes = {
    issue: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "issue_pass",
          {
            tenant: organizationId,
            kind: input.kind ?? "ticket",
            holder_user: input.holderUserId ?? null,
            holder_name: input.holderName ?? null,
            holder_email: input.holderEmail ?? null,
            subject_type: input.subject?.type ?? null,
            subject_id: input.subject?.id ?? null,
            booking_id: input.bookingId ?? null,
            resource_id: input.resourceId ?? null,
            uses_allowed: input.usesAllowed ?? null,
            valid_from: instantArg(input.validFrom),
            valid_until: instantArg(input.validUntil),
          },
          (value) => issuedOf(value, "issue_pass"),
        ),
      ),
    revoke: (passId) =>
      call("revoke_pass", { pass_id: passId }, (value) =>
        passOf(value, "revoke_pass"),
      ),
    get: (passId) =>
      call("get_pass", { pass_id: passId }, (value) =>
        value === null ? null : issuedOf(value, "get_pass"),
      ),
    list: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_passes",
          {
            tenant: organizationId,
            holder_user: list.holderUserId ?? null,
            subject_type: list.subject?.type ?? null,
            subject_id: list.subject?.id ?? null,
            status: list.status ?? null,
            before: instantArg(list.before),
            page_size: list.pageSize ?? null,
          },
          (value) =>
            recordsOf(value, "list_passes").map((row) =>
              passOf(row, "list_passes"),
            ),
        ),
      ),
    mine: () =>
      call("my_passes", {}, (value) =>
        recordsOf(value, "my_passes").map((row) => issuedOf(row, "my_passes")),
      ),
    token: (pass) => {
      if (options.signer === undefined) {
        return AsyncResult.err(
          dbError(
            "invalid_input",
            "createPasses needs a signer to sign tokens",
            { hint: "PASS_SIGNER_MISSING" },
          ),
        );
      }

      const latest = temporal()
        .Now.instant()
        .add(
          options.tokenLifetime ??
            temporal().Duration.from({ hours: DEFAULT_LIFETIME_DAYS * 24 }),
        );

      const until =
        pass.validUntil !== undefined &&
        temporal().Instant.compare(pass.validUntil, latest) < 0
          ? pass.validUntil
          : latest;

      const claims: PassTokenClaims = {
        sub: pass.id,
        jti: pass.nonce,
        org: pass.organizationId,
        kind: pass.kind,
        nbf: epochSeconds(pass.validFrom),
        exp: epochSeconds(until),
        ...optional("name", pass.holderName),
      };

      return options.signer.signJwt(claims, { typ: PASS_TOKEN_TYPE });
    },
    checkIn: (token, scan = {}) => {
      const { jwks } = options;

      if (jwks === undefined) {
        return AsyncResult.err(
          dbError("invalid_input", "createPasses needs jwks to verify tokens", {
            hint: "PASS_JWKS_MISSING",
          }),
        );
      }

      return AsyncResult.from(async () => {
        const read = await readToken(token, jwks);

        return read.ok
          ? checkInCall(
              read.sub,
              read.jti,
              scan.method ?? "qr",
              scan.gate,
              scan.resourceId,
            )
          : AsyncResult.err(read.error);
      });
    },
    checkInManually: (passId, scan = {}) =>
      checkInCall(passId, null, "manual", scan.gate, scan.resourceId),
    checkIns: (passId, list = {}) =>
      call(
        "list_pass_check_ins",
        {
          pass_id: passId,
          before: instantArg(list.before),
          page_size: list.pageSize ?? null,
        },
        (value) =>
          recordsOf(value, "list_pass_check_ins").map((row) =>
            checkInOf(row, "list_pass_check_ins"),
          ),
      ),
    occupancy: (resourceId) =>
      call("pass_occupancy", { resource_id: resourceId }, (value) => {
        const row = recordOf(value, "pass_occupancy");

        return {
          resourceId: textOf(row["resourceId"]),
          capacity: countOf(row["capacity"], "capacity"),
          booked: countOf(row["booked"], "booked"),
          dropIns: countOf(row["dropIns"], "dropIns"),
          free: countOf(row["free"], "free"),
        };
      }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "passes",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
