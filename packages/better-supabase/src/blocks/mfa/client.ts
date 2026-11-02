import type { Aal } from "../../auth/mfa.ts";
import type { DbError } from "../../core/errors.ts";
import type { Result } from "../../core/result.ts";
import type { AuthReply } from "../auth-reply.ts";
import type { AuthPort, Controller } from "../controller.ts";

import { dbError } from "../../core/errors.ts";
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

/** The browser options `supabase.auth.mfa.webauthn` takes (WebAuthn Level 3). */
export interface PasskeyOptions {
  /** The relying party id; default: the page's hostname. */
  readonly rpId?: string;
  /** The origins that may use the passkey; default: the page's origin. */
  readonly rpOrigins?: readonly string[];
  /** Aborts the browser's credential prompt. */
  readonly signal?: AbortSignal;
}

/**
 * `supabase.auth.mfa.webauthn` of supabase-js 2.100 and later. It runs the
 * browser's `navigator.credentials` calls and the Auth server's challenge and
 * verify steps, so no WebAuthn library is needed.
 */
export interface WebAuthnApi {
  register(params: {
    friendlyName: string;
    webauthn?: { rpId?: string; rpOrigins?: string[]; signal?: AbortSignal };
  }): PromiseLike<AuthReply<unknown>>;
  authenticate(params: {
    factorId: string;
    webauthn?: { rpId?: string; rpOrigins?: string[]; signal?: AbortSignal };
  }): PromiseLike<AuthReply<unknown>>;
}

/** The part of `supabase.auth.mfa` the MFA controllers call. */
export interface MfaApi {
  /**
   * Present when the client supports passkeys; without it they report
   * unsupported.
   */
  readonly webauthn?: WebAuthnApi;
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

/** The refusal when the client has no `auth.mfa.webauthn`. */
const PASSKEYS_UNSUPPORTED = (): DbError =>
  dbError(
    "invalid_input",
    "This Supabase client does not support passkeys (auth.mfa.webauthn)",
    { code: "MFA_PASSKEYS_UNSUPPORTED" },
  );

const webauthnParams = (
  options: PasskeyOptions | undefined,
): {
  webauthn: { rpId?: string; rpOrigins?: string[]; signal?: AbortSignal };
} => ({
  webauthn: {
    ...(options?.rpId === undefined ? {} : { rpId: options.rpId }),
    ...(options?.rpOrigins === undefined
      ? {}
      : { rpOrigins: [...options.rpOrigins] }),
    ...(options?.signal === undefined ? {} : { signal: options.signal }),
  },
});

export interface MfaAssurance {
  /** The session's level; `undefined` until the first load. */
  readonly level: Aal | undefined;
  /**
   * `aal2` when the user has a verified factor, so a challenge can raise the
   * session.
   */
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
  /**
   * Confirms `enrollment` with a code from the app; the session is `aal2` after
   * it.
   */
  readonly verify: (code: string) => Promise<Result<MfaAssurance>>;
  /**
   * Registers a passkey: the browser asks for the authenticator, and the factor
   * is verified in the same call, so the session is `aal2` after it.
   */
  readonly registerPasskey: (
    input?: PasskeyOptions & { readonly name?: string },
  ) => Promise<Result<MfaAssurance>>;
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
 * A user's MFA factors for a security settings page: `enroll` shows a QR code,
 * `verify` confirms it with the first code, and `unenroll` removes a factor.
 * The assurance level is read again after each change.
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
        ticket += 1;
        const request = ticket;

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
          registerPasskey: async (input) => {
            if (mfa.webauthn === undefined) {
              const unsupported = PASSKEYS_UNSUPPORTED();

              state.set({ error: unsupported });

              return err(unsupported);
            }

            const webauthn = mfa.webauthn;
            state.set({ pending: true, error: undefined });

            const registered = await authResult(() =>
              webauthn.register({
                friendlyName: input?.name ?? "Passkey",
                ...webauthnParams(input),
              }),
            );

            if (!registered.ok) {
              return settle<MfaAssurance>(err(registered.error));
            }

            return settle<MfaAssurance>(await readAssurance(mfa));
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
  /**
   * The verified factors a code can come from; `undefined` until the first
   * load.
   */
  readonly factors: readonly MfaFactor[] | undefined;
  /** Whether the session is `aal2`. */
  readonly satisfied: boolean;
  readonly verifying: boolean;
  readonly error: DbError | undefined;
}

export interface StepUpActions {
  /**
   * Challenges a verified factor (the first one by default) with `code`, then
   * reads the session's level again.
   */
  readonly verify: (input: {
    code: string;
    factorId?: string | undefined;
  }) => Promise<Result<MfaAssurance>>;
  /**
   * Challenges a verified passkey (`factorId`, or the first `webauthn` factor)
   * through the browser, then reads the session's level again.
   */
  readonly verifyPasskey: (
    input?: PasskeyOptions & { readonly factorId?: string },
  ) => Promise<Result<MfaAssurance>>;
  readonly dismiss: () => void;
  readonly refresh: () => Promise<void>;
}

export type StepUpController = Controller<StepUpSnapshot, StepUpActions>;

/**
 * Raises the session to `aal2` before a call that `checkAal` guards: show it
 * when an error passes `needsStepUp`, then retry the call once `satisfied` is
 * true.
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
        ticket += 1;
        const request = ticket;

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
          verify: async ({ code, factorId }) => {
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
          verifyPasskey: async (input) => {
            const fail = (error: DbError): Result<MfaAssurance> => {
              state.set({ verifying: false, error });

              return err(error);
            };

            if (mfa.webauthn === undefined) {
              return fail(PASSKEYS_UNSUPPORTED());
            }

            const webauthn = mfa.webauthn;

            const id =
              input?.factorId ??
              state.get().factors?.find((factor) => factor.type === "webauthn")
                ?.id;

            if (id === undefined) {
              return fail(
                dbError("invalid_input", "No verified passkey to challenge"),
              );
            }

            state.set({ verifying: true, error: undefined });

            const verified = await authResult(() =>
              webauthn.authenticate({ factorId: id, ...webauthnParams(input) }),
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
