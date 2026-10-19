import {
  confirm,
  type Option,
  isCancel,
  multiselect,
  select,
  spinner,
} from "@clack/prompts";

import { CliError } from "./errors.ts";

export interface Choice<T extends string> {
  readonly value: T;
  readonly label: string;
  readonly hint?: string;
}

/**
 * Questions and progress for a person at a terminal. `run()` only gets one
 * from the bin on a TTY outside CI. A method that resolves `undefined` gave
 * no answer, and the command takes its default.
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

/** Ctrl-C or Escape at a prompt ends the run with exit code 130. */
function answered<T extends boolean | string | string[]>(
  answer: T | symbol,
): T {
  if (isCancel(answer) || typeof answer === "symbol") {
    throw new CliError("cancelled", "Cancelled.");
  }

  return answer;
}

const options = (choices: readonly Choice<string>[]): Option<string>[] =>
  choices.map((choice) => ({
    value: choice.value,
    label: choice.label,
    ...(choice.hint ? { hint: choice.hint } : {}),
  }));

/** The @clack/prompts implementation; spinners write to `output` (stderr in the bin) so stdout stays pipeable. */
export const createClackPrompter = (output: NodeJS.WriteStream): Prompter => ({
  select: async (message, choices, initial) => {
    const answer = answered<string>(
      await select<string>({
        message,
        options: options(choices),
        initialValue: initial,
      }),
    );

    return choices.find((choice) => choice.value === answer)?.value;
  },
  multiselect: async (message, choices, initial) => {
    const answer = answered<string[]>(
      await multiselect<string>({
        message,
        options: options(choices),
        initialValues: [...initial],
        required: false,
      }),
    );

    return choices
      .filter((choice) => answer.includes(choice.value))
      .map((choice) => choice.value);
  },
  confirm: async (message) =>
    answered<boolean>(await confirm({ message, initialValue: false })),
  spinner: (message) => {
    const spin = spinner({ output });
    spin.start(message);

    return () => {
      spin.clear();
    };
  },
});

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
