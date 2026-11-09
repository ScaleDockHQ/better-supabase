import type { AnyCommand } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";

import { defineCliCommand } from "../core/command.ts";
import { commandMeta } from "../core/manifest.ts";
import { ERROR_CODES } from "../error-codes.ts";

export const codesCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("codes"),
  args: {},
  run: (_args, context): Promise<CommandResult> => {
    if (context.json) {
      return Promise.resolve({
        code: 0,
        output: `${JSON.stringify(ERROR_CODES, null, 2)}\n`,
        data: { codes: ERROR_CODES },
      });
    }

    return Promise.resolve({
      code: 0,
      output: `${String(ERROR_CODES.length)} error codes. Pass --json to print them.`,
      data: { count: ERROR_CODES.length },
    });
  },
});
