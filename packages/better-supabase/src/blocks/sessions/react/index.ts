"use client";

import type {
  OAuthConsentActions,
  OAuthConsentSnapshot,
  OAuthGrantsActions,
  OAuthGrantsSnapshot,
} from "../client.ts";

import { useController, useLatest } from "../../react-controller.ts";
import { useBlockEnv } from "../../react-env.ts";
import {
  createOAuthConsentController,
  createOAuthGrantsController,
} from "../client.ts";

export type {
  OAuthClientInfo,
  OAuthConsentRequest,
  OAuthGrant,
} from "../client.ts";

export interface UseOAuthConsentOptions {
  /** `authorization_id` from the page's URL; `undefined` loads nothing. */
  readonly authorizationId: string | undefined;
  /**
   * Leaves for the `redirect_url` Auth returned. Default:
   * `window.location.assign`.
   */
  readonly redirect?: (url: string) => void;
}

export interface OAuthConsentState
  extends OAuthConsentSnapshot, OAuthConsentActions {}

export interface OAuthGrantsState
  extends OAuthGrantsSnapshot, OAuthGrantsActions {}

/**
 * The consent page of the Supabase Auth OAuth server: `request` holds the
 * client and scopes, and `approve` or `deny` go to the client through the
 * `redirect_url` Auth returns.
 *
 * ```tsx
 * const { request, deciding, approve, deny } = useOAuthConsent({
 *   authorizationId,
 * });
 * ```
 */
export function useOAuthConsent(
  options: UseOAuthConsentOptions,
): OAuthConsentState {
  const { supabase, auth } = useBlockEnv();
  const latest = useLatest(options);
  const { authorizationId } = options;

  return useController(
    () =>
      createOAuthConsentController({
        oauth: supabase.auth.oauth,
        auth,
        authorizationId,
        redirect: (url) => {
          const redirect = latest.current.redirect;

          if (redirect) {
            redirect(url);
          } else {
            globalThis.location.assign(url);
          }
        },
      }),
    [supabase, auth, authorizationId, latest],
  ).view;
}

/**
 * The OAuth clients the user approved, for a connected agents list: `revoke`
 * disconnects one.
 *
 * ```tsx
 * const { grants, revoke } = useOAuthGrants();
 * ```
 */
export function useOAuthGrants(): OAuthGrantsState {
  const { supabase, auth } = useBlockEnv();

  return useController(
    () => createOAuthGrantsController({ oauth: supabase.auth.oauth, auth }),
    [supabase, auth],
  ).view;
}
