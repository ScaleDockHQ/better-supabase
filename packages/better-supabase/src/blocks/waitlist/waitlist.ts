import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { VerifyOptions } from "../webhooks/verify.ts";

import {
  blockCall,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
  toInstant,
} from "../shared.ts";
import { authHook, hookError } from "../webhooks/verify.ts";

export type WaitlistStatus = "waiting" | "approved" | "rejected" | "joined";

export interface WaitlistEntry {
  readonly id: string;
  readonly email: string;
  readonly status: WaitlistStatus;
  readonly position: number;
  readonly referrer: string | undefined;
  readonly metadata: Readonly<Record<string, unknown>>;
  readonly userId: string | undefined;
  readonly decidedBy: string | undefined;
  readonly decidedAt: Temporal.Instant | undefined;
  readonly createdAt: Temporal.Instant;
}

/** What `join` tells the person: rejected entries read as `waiting`. */
export interface WaitlistPlace {
  /** Their place among the waiting entries; `undefined` once approved. */
  readonly position: number | undefined;
  readonly status: Exclude<WaitlistStatus, "rejected">;
}

export interface InviteCode {
  readonly id: string;
  /** The first four characters, to tell codes apart in a list. */
  readonly prefix: string;
  readonly maxUses: number | undefined;
  readonly uses: number;
  readonly expiresAt: Temporal.Instant | undefined;
  readonly organizationId: string | undefined;
  readonly role: string | undefined;
  readonly createdBy: string | undefined;
  readonly createdAt: Temporal.Instant;
  readonly revokedAt: Temporal.Instant | undefined;
}

export interface CreateInviteCodeInput {
  /** Defaults to 1. `null` allows any number of uses. */
  readonly maxUses?: number | null;
  readonly expiresAt?: Temporal.Instant;
  /** Adds whoever redeems the code to this organization. */
  readonly organizationId?: string;
  /** The role in `organizationId`; `sql.modules.waitlist.options.defaultRole` otherwise. */
  readonly role?: string;
  /** Your own code, such as `LAUNCH2026`; a random one otherwise. */
  readonly code?: string;
}

export interface Redemption {
  readonly organizationId: string | undefined;
  /** The role the code granted; `undefined` when the user was a member already. */
  readonly role: string | undefined;
}

export interface WaitlistOptions {
  readonly transport: BlockTransport;
  /** The module schema (`sql.modules.waitlist.schema`), default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface Waitlist {
  /** Adds an address, or returns its place when it is already there. Works signed out. */
  join(
    email: string,
    options?: {
      readonly referrer?: string;
      readonly metadata?: Readonly<Record<string, unknown>>;
    },
  ): AsyncResult<WaitlistPlace>;
  /** Entries by position; needs `waitlist.manage` on the platform. */
  entries(options?: {
    readonly status?: WaitlistStatus | null;
    readonly limit?: number;
    readonly afterPosition?: number;
  }): AsyncResult<readonly WaitlistEntry[]>;
  /** Lets the address sign up and emits `waitlist.approved`. */
  approve(entryId: string): AsyncResult<WaitlistEntry>;
  reject(entryId: string): AsyncResult<WaitlistEntry>;
  /** Creates a code; `code` is shown once, the database keeps its hash. */
  createCode(
    input?: CreateInviteCodeInput,
  ): AsyncResult<{ readonly code: string; readonly invite: InviteCode }>;
  /** Platform codes, or one organization's. */
  codes(organizationId?: string): AsyncResult<readonly InviteCode[]>;
  revokeCode(codeId: string): AsyncResult<boolean>;
  /** Uses a code for the signed-in user, e.g. one that joins an organization. */
  redeem(code: string): AsyncResult<Redemption>;
}

const STATUSES: ReadonlySet<string> = new Set([
  "waiting",
  "approved",
  "rejected",
  "joined",
]);

function statusOf(value: unknown): WaitlistStatus {
  const text = textOf(value);
  if (!STATUSES.has(text)) {
    throw new TypeError(`Unknown waitlist status ${text}`);
  }
  // SAFETY: the set holds exactly the WaitlistStatus values.
  return text as WaitlistStatus;
}

const optionalNumber = (value: unknown): number | undefined =>
  value === null || value === undefined ? undefined : Number(value);

function entryOf(value: unknown): WaitlistEntry {
  const row = recordOf(value, "waitlist_entries");
  return {
    id: textOf(row["id"]),
    email: textOf(row["email"]),
    status: statusOf(row["status"]),
    position: Number(row["position"]),
    referrer: optionalText(row["referrer"]),
    metadata: isRecord(row["metadata"]) ? row["metadata"] : {},
    userId: optionalText(row["user_id"]),
    decidedBy: optionalText(row["decided_by"]),
    decidedAt: optionalInstant(row["decided_at"]),
    createdAt: toInstant(textOf(row["created_at"])),
  };
}

function codeOf(value: unknown): InviteCode {
  const row = recordOf(value, "invite_codes");
  return {
    id: textOf(row["id"]),
    prefix: textOf(row["prefix"]),
    maxUses: optionalNumber(row["max_uses"]),
    uses: Number(row["uses"]),
    expiresAt: optionalInstant(row["expires_at"]),
    organizationId: optionalText(row["organization_id"]),
    role: optionalText(row["role"]),
    createdBy: optionalText(row["created_by"]),
    createdAt: toInstant(textOf(row["created_at"])),
    revokedAt: optionalInstant(row["revoked_at"]),
  };
}

/** A random code in groups of four, without characters that look alike. */
export function generateInviteCode(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  const chars = [...bytes].map((byte) => alphabet[byte % alphabet.length]);
  return [0, 4, 8, 12].map((at) => chars.slice(at, at + 4).join("")).join("-");
}

export function createWaitlist(options: WaitlistOptions): Waitlist {
  const call = blockCall(options.transport, options.schema, options.mappers);
  const decide = (entryId: string, approve: boolean) =>
    call("decide_waitlist_entry", { id: entryId, approve }, entryOf);
  return {
    join: (email, more = {}) =>
      call(
        "join_waitlist",
        {
          email,
          referrer: more.referrer ?? null,
          metadata: more.metadata ?? {},
        },
        (value) => {
          const row = recordOf(value, "join_waitlist");
          const status = statusOf(row["status"]);
          return {
            position: optionalNumber(row["position"]),
            status: status === "rejected" ? "waiting" : status,
          };
        },
      ),
    entries: (query = {}) =>
      call(
        "list_waitlist",
        {
          status: query.status === undefined ? "waiting" : query.status,
          page_size: query.limit ?? 50,
          after_position: query.afterPosition ?? null,
        },
        (value) => recordsOf(value, "list_waitlist").map(entryOf),
      ),
    approve: (entryId) => decide(entryId, true),
    reject: (entryId) => decide(entryId, false),
    createCode: (input = {}) => {
      const code = input.code ?? generateInviteCode();
      return call(
        "create_invite_code",
        {
          code,
          max_uses: input.maxUses === undefined ? 1 : input.maxUses,
          expires_at: instantArg(input.expiresAt),
          tenant: input.organizationId ?? null,
          role: input.role ?? null,
        },
        (value) => ({ code, invite: codeOf(value) }),
      );
    },
    codes: (organizationId) =>
      call("list_invite_codes", { tenant: organizationId ?? null }, (value) =>
        recordsOf(value, "list_invite_codes").map(codeOf),
      ),
    revokeCode: (codeId) =>
      call("revoke_invite_code", { id: codeId }, (value) => value === true),
    redeem: (code) =>
      call("redeem_invite_code", { code }, (value) => {
        const row = recordOf(value, "redeem_invite_code");
        return {
          organizationId: optionalText(row["organizationId"]),
          role: optionalText(row["role"]),
        };
      }),
  };
}

export interface WaitlistHookOptions {
  /** A service transport: `waitlist_admit` is granted to the service role. */
  readonly transport: BlockTransport;
  /** The hook secret, `v1,whsec_...`, or several while rotating. */
  readonly secret: string | readonly string[];
  /** The user metadata field the client puts the code in (`codeField`), default `invite_code`. */
  readonly codeField?: string;
  /** What Supabase Auth tells a rejected sign-up. */
  readonly message?: string;
  readonly schema?: string;
  readonly verify?: VerifyOptions;
}

/**
 * The before-user-created Auth hook: lets an address sign up when it is
 * approved on the waitlist or the sign-up carries a valid invite code.
 *
 * ```ts
 * export const POST = waitlistHook({ transport, secret: env.BEFORE_USER_CREATED_SECRET });
 * ```
 */
export function waitlistHook(
  options: WaitlistHookOptions,
): (request: Request) => Promise<Response> {
  const call = blockCall(options.transport, options.schema);
  const field = options.codeField ?? "invite_code";
  const message =
    options.message ?? "Sign-ups are invite-only. Join the waitlist first.";
  return authHook(
    "before_user_created",
    options.secret,
    async ({ user }) => {
      const code = user.user_metadata?.[field];
      const result = await call(
        "waitlist_admit",
        {
          email: user.email ?? "",
          code: typeof code === "string" && code !== "" ? code : null,
        },
        (value) => recordOf(value, "waitlist_admit")["allowed"] === true,
      );
      if (!result.ok) throw new Error(result.error.message);
      return result.data ? {} : hookError(403, message);
    },
    options.verify,
  );
}
