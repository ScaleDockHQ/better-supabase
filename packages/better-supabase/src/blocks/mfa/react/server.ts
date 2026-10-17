import type { MfaState, StepUpState, UseMfaOptions } from "./index.ts";

export type {
  MfaAssurance,
  MfaEnrollment,
  MfaFactor,
  MfaState,
  StepUpState,
  UseMfaOptions,
} from "./index.ts";

export { needsStepUp } from "../client.ts";

/** The `react-server` build of `useMfa`: it runs in Client Components only. */
export const useMfa: (options?: UseMfaOptions) => MfaState = () => {
  throw new Error(
    "better-supabase: useMfa() runs in Client Components only. In Server Components read the `aal` claim with `aalOf()` instead.",
  );
};

/** The `react-server` build of `useStepUp`: it runs in Client Components only. */
export const useStepUp: () => StepUpState = () => {
  throw new Error(
    "better-supabase: useStepUp() runs in Client Components only. In Server Components read the `aal` claim with `aalOf()` instead.",
  );
};
