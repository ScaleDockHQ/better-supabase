import {
  confirm,
  type Option,
  isCancel,
  multiselect,
  select,
  spinner,
} from "@clack/prompts";

export interface Choice<T extends string> {
  readonly value: T;
  readonly label: string;
  readonly hint?: string;
}

/**
 * Questions and progress for a person at a terminal. `run()` only gets one
 * from the bin on a TTY outside CI; every method resolves `undefined` when the
 * person cancels.
 */
export interface Prompter {
  readonly select: <T extends string>(
    message: string,
    choices: readonly Choice<T>[],
    initial: T,
  ) => Promise<T | undefined>;
  readonly multiselect: <T extends string>(
    message: string,
    choices: readonly Choice<T>[],
    initial: readonly T[],
  ) => Promise<T[] | undefined>;
  readonly confirm: (message: string) => Promise<boolean | undefined>;
  /** Shows `message` with a spinner until the returned function is called. */
  readonly spinner: (message: string) => () => void;
}

const options = (choices: readonly Choice<string>[]): Option<string>[] =>
  choices.map((choice) => ({
    value: choice.value,
    label: choice.label,
    ...(choice.hint ? { hint: choice.hint } : {}),
  }));

/** The @clack/prompts implementation; spinners write to stderr so stdout stays pipeable. */
export const clackPrompter: Prompter = {
  select: async (message, choices, initial) => {
    const answer = await select<string>({
      message,
      options: options(choices),
      initialValue: initial,
    });
    if (isCancel(answer)) return undefined;
    return choices.find((choice) => choice.value === answer)?.value;
  },
  multiselect: async (message, choices, initial) => {
    const answer = await multiselect<string>({
      message,
      options: options(choices),
      initialValues: [...initial],
      required: false,
    });
    if (isCancel(answer)) return undefined;
    return choices
      .filter((choice) => answer.includes(choice.value))
      .map((choice) => choice.value);
  },
  confirm: async (message) => {
    const answer = await confirm({ message, initialValue: false });
    return isCancel(answer) ? undefined : answer;
  },
  spinner: (message) => {
    const spin = spinner({ output: process.stderr });
    spin.start(message);
    return () => spin.clear();
  },
};

/** Runs `task` behind a spinner when `prompts` is set. */
export async function withSpinner<T>(
  prompts: Prompter | undefined,
  message: string,
  task: () => Promise<T>,
): Promise<T> {
  const stop = prompts?.spinner(message);
  try {
    return await task();
  } finally {
    stop?.();
  }
}
