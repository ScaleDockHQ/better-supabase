"use client";

import type {
  MfaActions,
  MfaSnapshot,
  StepUpActions,
  StepUpSnapshot,
} from "../client.ts";

import { useController } from "../../react-controller.ts";
import { useBlockEnv } from "../../react-env.ts";
import { createMfaController, createStepUpController } from "../client.ts";

export type { MfaAssurance, MfaEnrollment, MfaFactor } from "../client.ts";

export { needsStepUp } from "../client.ts";

export interface UseMfaOptions {
  /** The issuer authenticator apps show; default: the Auth Site URL's host. */
  readonly issuer?: string;
}

export interface MfaState extends MfaSnapshot, MfaActions {}

export interface StepUpState extends StepUpSnapshot, StepUpActions {}

/**
 * The user's MFA factors through the browser client, for a security
 * settings page: `enroll` keeps a QR code in `enrollment`, `verify` confirms
 * it with the first code, and `unenroll` removes a factor.
 *
 * ```tsx
 * const { factors, enrollment, enroll, verify } = useMfa();
 * ```
 */
export function useMfa(options: UseMfaOptions = {}): MfaState {
  const { supabase, auth } = useBlockEnv();
  const { issuer } = options;

  return useController(
    () =>
      createMfaController({
        mfa: supabase.auth.mfa,
        auth,
        ...(issuer === undefined ? {} : { issuer }),
      }),
    [supabase, auth, issuer],
  ).view;
}

/**
 * Raises the session to `aal2` with a code from a verified factor. Show it
 * when a call fails with `needsStepUp(error)`, and retry the call once
 * `satisfied` is true.
 *
 * ```tsx
 * const { satisfied, verify } = useStepUp();
 * ```
 */
export function useStepUp(): StepUpState {
  const { supabase, auth } = useBlockEnv();

  return useController(
    () => createStepUpController({ mfa: supabase.auth.mfa, auth }),
    [supabase, auth],
  ).view;
}
