import { CliError } from "../../../src/cli/core/errors.ts";

/** The message of the usage error `run` throws; fails when it throws nothing or another error. */
export async function usageError(run: () => unknown): Promise<string> {
  try {
    await run();
  } catch (error) {
    if (error instanceof CliError && error.code === "usage") {
      return error.message;
    }

    throw error;
  }

  throw new Error("Expected a usage error");
}
