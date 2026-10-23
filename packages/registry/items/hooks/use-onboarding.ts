"use client";

import type {
  Checklist,
  ChecklistScope,
  OnboardingActions,
  OnboardingSnapshot,
} from "better-supabase/blocks/onboarding";

import { rpcTransport } from "better-supabase/blocks";
import {
  createOnboarding,
  createOnboardingController,
} from "better-supabase/blocks/onboarding";
import { useBlockEnv, useController } from "better-supabase/react";

export interface UseOnboardingOptions {
  /** The organization, for an organization checklist. */
  readonly organizationId?: string | null;
  /**
   * The schema the calls go to: the module schema (default `better_supabase`),
   * or the API schema from `blocks.<module>.api`.
   */
  readonly schema?: string;
}

export interface OnboardingState<Id extends string>
  extends OnboardingSnapshot<Id>, OnboardingActions<Id> {}

/**
 * A checklist's progress for the signed-in user, or for an organization with
 * `organizationId`, through the browser client.
 *
 * ```tsx
 * const { progress, complete } = useOnboarding(gettingStarted, {
 *   organizationId,
 * });
 * ```
 */
export function useOnboarding<Id extends string, Scope extends ChecklistScope>(
  checklist: Checklist<Id, Scope>,
  options: UseOnboardingOptions = {},
): OnboardingState<Id> {
  const { supabase, auth } = useBlockEnv();
  const { organizationId, schema } = options;

  return useController(
    () =>
      createOnboardingController<Id, Scope>({
        client: createOnboarding({
          transport: rpcTransport(supabase),
          ...(schema === undefined ? {} : { schema }),
        }),
        checklist,
        auth,
        organizationId: organizationId ?? null,
      }),
    [checklist, supabase, auth, organizationId, schema],
  ).view;
}
