import { CliError } from "../../../src/cli/core/errors.ts";

/** The message of the exit-2 error `run` throws; fails when it throws nothing or another error. */
export async function usageError(run: () => unknown): Promise<string> {
  try {
    await run();
  } catch (error) {
    if (error instanceof CliError && error.exitCode === 2) {
      return error.message;
    }

    throw error;
  }

  throw new Error("Expected a usage error");
}
