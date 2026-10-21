import type { QuestionnaireView, UseQuestionnaireOptions } from "./index.ts";

export type { QuestionnaireView, UseQuestionnaireOptions } from "./index.ts";

/**
 * The `react-server` build of `useQuestionnaire`: render the form in a Client
 * Component.
 */
export const useQuestionnaire: (
  options: UseQuestionnaireOptions,
) => QuestionnaireView = () => {
  throw new Error(
    "better-supabase: useQuestionnaire() runs in Client Components only. In Server Components load the version with `forms.get()` and pass it down.",
  );
};
