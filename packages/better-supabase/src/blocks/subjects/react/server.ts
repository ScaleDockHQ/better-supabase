import type {
  useSubject as useClientSubject,
  useSubjects as useClientSubjects,
} from "./index.ts";

export type { ResolvedSubject, SubjectsState, SubjectState } from "./index.ts";

const clientOnly = (name: string): Error =>
  new Error(
    `better-supabase: ${name} runs in Client Components only. In Server Components call \`createBlockClient(db, subjectsBlock).resolve(refs)\` instead.`,
  );

/** The `react-server` build of `useSubjects`. */
export const useSubjects: typeof useClientSubjects = () => {
  throw clientOnly("useSubjects()");
};

/** The `react-server` build of `useSubject`. */
export const useSubject: typeof useClientSubject = () => {
  throw clientOnly("useSubject()");
};
