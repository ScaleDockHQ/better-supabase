import type {
  OAuthConsentState,
  OAuthGrantsState,
  UseOAuthConsentOptions,
} from "./index.ts";

export type {
  OAuthClientInfo,
  OAuthConsentRequest,
  OAuthConsentState,
  OAuthGrant,
  OAuthGrantsState,
  UseOAuthConsentOptions,
} from "./index.ts";

/**
 * The `react-server` build of `useOAuthConsent`: it runs in Client Components
 * only.
 */
export const useOAuthConsent: (
  options: UseOAuthConsentOptions,
) => OAuthConsentState = () => {
  throw new Error(
    "better-supabase: useOAuthConsent() runs in Client Components only; render the consent form as one.",
  );
};

/**
 * The `react-server` build of `useOAuthGrants`: it runs in Client Components
 * only.
 */
export const useOAuthGrants: () => OAuthGrantsState = () => {
  throw new Error(
    "better-supabase: useOAuthGrants() runs in Client Components only; render the list as one.",
  );
};
