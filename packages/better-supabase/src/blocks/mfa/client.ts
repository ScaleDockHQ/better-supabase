import type { Aal } from "../../auth/mfa.ts";
import type { Result } from "../../core/result.ts";
import type { AuthReply } from "../auth-reply.ts";
import type { AuthPort, Controller } from "../controller.ts";

import { type DbError, dbError } from "../../core/errors.ts";
import { err, ok } from "../../core/result.ts";
import { authResult } from "../auth-reply.ts";
import { defineController, whileSignedIn } from "../controller.ts";

/** A factor as `auth.mfa.listFactors()` returns it. */
export interface RawMfaFactor {
  readonly id: string;
  readonly friendly_name?: string;
  readonly factor_type: string;
  readonly status: string;
}

/** The part of `supabase.auth.mfa` the MFA controllers call. */
export interface MfaApi {
  listFactors(): PromiseLike<
    AuthReply<{ readonly all: readonly RawMfaFactor[] }>
  >;
  enroll(params: {
    factorType: "totp";
    friendlyName?: string;
    issuer?: string;
  }): PromiseLike<
    AuthReply<{
      readonly id: string;
      readonly totp: {
        readonly qr_code: string;
        readonly secret: string;
        readonly uri: string;
      };
    }>
  >;
  challengeAndVerify(params: {
    factorId: string;
    code: string;
  }): PromiseLike<AuthReply<unknown>>;
  unenroll(params: { factorId: string }): PromiseLike<AuthReply<unknown>>;
  getAuthenticatorAssuranceLevel(): PromiseLike<
    AuthReply<{
      readonly currentLevel: string | null;
      readonly nextLevel: string | null;
    }>
  >;
}

export interface MfaFactor {
  readonly id: string;
  readonly name: string | undefined;
  /** `totp`, `phone` or `webauthn`. */
  readonly type: string;
  /** False for an enrolment the user hasn't confirmed with a code yet. */
  readonly verified: boolean;
}

/** A TOTP factor waiting for its first code. */
export interface MfaEnrollment {
  readonly factorId: string;
  /** An SVG data URL of the QR code for authenticator apps. */
  readonly qrCode: string;
  /** The secret, for typing into an authenticator by hand. */
  readonly secret: string;
  readonly uri: string;
}

export interface MfaAssurance {
  /** The session's level; `undefined` until the first load. */
  readonly level: Aal | undefined;
  /** `aal2` when the user has a verified factor, so a challenge can raise the session. */
  readonly nextLevel: Aal | undefined;
}

const toAal = (level: string | null): Aal | undefined =>
  level === "aal2" ? "aal2" : level === "aal1" ? "aal1" : undefined;

const toFactor = (raw: RawMfaFactor): MfaFactor => ({
  id: raw.id,
  name: raw.friendly_name === "" ? undefined : raw.friendly_name,
  type: raw.factor_type,
  verified: raw.status === "verified",
});

async function readAssurance(mfa: MfaApi): Promise<Result<MfaAssurance>> {
  const result = await authResult(() => mfa.getAuthenticatorAssuranceLevel());
  return result.ok
    ? ok({
        level: toAal(result.data.currentLevel),
        nextLevel: toAal(result.data.nextLevel),
      })
    : result;
}

async function readFactors(mfa: MfaApi): Promise<Result<readonly MfaFactor[]>> {
  const result = await authResult(() => mfa.listFactors());
  return result.ok ? ok(result.data.all.map(toFactor)) : result;
}

/** Whether `error` is the `INSUFFICIENT_AAL` refusal that asks for a step-up. */
export function needsStepUp(error: DbError | undefined): boolean {
  return error?.kind === "forbidden" && error.code === "INSUFFICIENT_AAL";
}

export interface MfaControllerOptions {
  /** `supabase.auth.mfa` of the browser client. */
  readonly mfa: MfaApi;
  readonly auth: AuthPort;
  /** The issuer authenticator apps show; default: the Auth Site URL's host. */
  readonly issuer?: string;
}

export interface MfaSnapshot extends MfaAssurance {
  /** Every factor, verified or not; `undefined` until the first load. */
  readonly factors: readonly MfaFactor[] | undefined;
  /** The TOTP factor `enroll` made, until `verify` or `cancel`. */
  readonly enrollment: MfaEnrollment | undefined;
  /** Whether an enrol, verify or unenrol call is in flight. */
  readonly pending: boolean;
  readonly error: DbError | undefined;
}

export interface MfaActions {
  /** Enrols a TOTP factor and keeps its QR code in `enrollment`. */
  readonly enroll: (input?: {
    readonly name?: string;
  }) => Promise<Result<MfaEnrollment>>;
  /** Confirms `enrollment` with a code from the app; the session is `aal2` after it. */
  readonly verify: (code: string) => Promise<Result<MfaAssurance>>;
  /** Removes the unconfirmed factor of `enrollment`. */
  readonly cancel: () => Promise<void>;
  /** Removes a factor; removing a verified one needs an `aal2` session. */
  readonly unenroll: (factorId: string) => Promise<Result<boolean>>;
  /** Forgets `error`. */
  readonly dismiss: () => void;
  readonly refresh: () => Promise<void>;
}

export type MfaController = Controller<MfaSnapshot, MfaActions>;

/**
 * A user's MFA factors for a security settings page: `enroll` shows a QR
 * code, `verify` confirms it with the first code, and `unenroll` removes a
 * factor. The assurance level is read again after each change.
 */
export function createMfaController(
  options: MfaControllerOptions,
): MfaController {
  const { mfa } = options;
  return defineController<MfaSnapshot, MfaActions>(
    {
      factors: undefined,
      level: undefined,
      nextLevel: undefined,
      enrollment: undefined,
      pending: false,
      error: undefined,
    },
    (state) => {
      let ticket = 0;
      const refresh = async (): Promise<void> => {
        const request = ++ticket;
        const [factors, assurance] = await Promise.all([
          readFactors(mfa),
          readAssurance(mfa),
        ]);
        if (request !== ticket) {
          return;
        }
        if (!factors.ok) {
          state.set({ error: factors.error });
          return;
        }
        if (!assurance.ok) {
          state.set({ error: assurance.error });
          return;
        }
        state.set({ factors: factors.data, ...assurance.data });
      };
      const settle = async <T>(result: Result<T>): Promise<Result<T>> => {
        state.set(
          result.ok
            ? { pending: false }
            : { pending: false, error: result.error },
        );
        if (result.ok) {
          await refresh();
        }
        return result;
      };
      return {
        actions: {
          refresh,
          dismiss: () => {
            state.set({ error: undefined });
          },
          enroll: async (input) => {
            state.set({ pending: true, error: undefined });
            const result = await authResult(() =>
              mfa.enroll({
                factorType: "totp",
                ...(input?.name === undefined
                  ? {}
                  : { friendlyName: input.name }),
                ...(options.issuer === undefined
                  ? {}
                  : { issuer: options.issuer }),
              }),
            );
            const enrolled: Result<MfaEnrollment> = result.ok
              ? ok({
                  factorId: result.data.id,
                  qrCode: result.data.totp.qr_code,
                  secret: result.data.totp.secret,
                  uri: result.data.totp.uri,
                })
              : result;
            if (enrolled.ok) {
              state.set({ enrollment: enrolled.data });
            }
            return settle(enrolled);
          },
          verify: async (code) => {
            const enrollment = state.get().enrollment;
            if (enrollment === undefined) {
              return err(
                dbError("invalid_input", "Enrol a factor before verifying it"),
              );
            }
            state.set({ pending: true, error: undefined });
            const verified = await authResult(() =>
              mfa.challengeAndVerify({ factorId: enrollment.factorId, code }),
            );
            if (!verified.ok) {
              return settle<MfaAssurance>(err(verified.error));
            }
            state.set({ enrollment: undefined });
            return settle<MfaAssurance>(await readAssurance(mfa));
          },
          cancel: async () => {
            const enrollment = state.get().enrollment;
            if (enrollment === undefined) {
              return;
            }
            state.set({ enrollment: undefined, pending: true });
            await settle(
              await authResult(() =>
                mfa.unenroll({ factorId: enrollment.factorId }),
              ),
            );
          },
          unenroll: async (factorId) => {
            state.set({ pending: true, error: undefined });
            const result = await authResult(() => mfa.unenroll({ factorId }));
            return settle(result.ok ? ok(true) : result);
          },
        },
        start: () =>
          whileSignedIn(options.auth, () => {
            void refresh();
            return;
          }),
      };
    },
  );
}

export interface StepUpControllerOptions {
  /** `supabase.auth.mfa` of the browser client. */
  readonly mfa: MfaApi;
  readonly auth: AuthPort;
}

export interface StepUpSnapshot extends MfaAssurance {
  /** The verified factors a code can come from; `undefined` until the first load. */
  readonly factors: readonly MfaFactor[] | undefined;
  /** Whether the session is `aal2`. */
  readonly satisfied: boolean;
  readonly verifying: boolean;
  readonly error: DbError | undefined;
}

export interface StepUpActions {
  /**
   * Challenges a verified factor (the first one by default) with `code`,
   * then reads the session's level again.
   */
  readonly verify: (
    code: string,
    factorId?: string,
  ) => Promise<Result<MfaAssurance>>;
  readonly dismiss: () => void;
  readonly refresh: () => Promise<void>;
}

export type StepUpController = Controller<StepUpSnapshot, StepUpActions>;

/**
 * Raises the session to `aal2` before a call that `checkAal` guards: show
 * it when an error passes `needsStepUp`, then retry the call once
 * `satisfied` is true.
 */
export function createStepUpController(
  options: StepUpControllerOptions,
): StepUpController {
  const { mfa } = options;
  return defineController<StepUpSnapshot, StepUpActions>(
    {
      factors: undefined,
      level: undefined,
      nextLevel: undefined,
      satisfied: false,
      verifying: false,
      error: undefined,
    },
    (state) => {
      let ticket = 0;
      const assured = (assurance: MfaAssurance): Partial<StepUpSnapshot> => ({
        ...assurance,
        satisfied: assurance.level === "aal2",
      });
      const refresh = async (): Promise<void> => {
        const request = ++ticket;
        const [factors, assurance] = await Promise.all([
          readFactors(mfa),
          readAssurance(mfa),
        ]);
        if (request !== ticket) {
          return;
        }
        if (!factors.ok) {
          state.set({ error: factors.error });
          return;
        }
        if (!assurance.ok) {
          state.set({ error: assurance.error });
          return;
        }
        state.set({
          factors: factors.data.filter((factor) => factor.verified),
          ...assured(assurance.data),
        });
      };
      return {
        actions: {
          refresh,
          dismiss: () => {
            state.set({ error: undefined });
          },
          verify: async (code, factorId) => {
            const id = factorId ?? state.get().factors?.[0]?.id;
            if (id === undefined) {
              const missing = dbError(
                "invalid_input",
                "No verified factor to challenge",
              );
              state.set({ error: missing });
              return err(missing);
            }
            state.set({ verifying: true, error: undefined });
            const verified = await authResult(() =>
              mfa.challengeAndVerify({ factorId: id, code }),
            );
            const result = verified.ok ? await readAssurance(mfa) : verified;
            state.set(
              result.ok
                ? { verifying: false, ...assured(result.data) }
                : { verifying: false, error: result.error },
            );
            return result;
          },
        },
        start: () =>
          whileSignedIn(options.auth, () => {
            void refresh();
            return;
          }),
      };
    },
  );
}
