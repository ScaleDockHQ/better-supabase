import type { AnyCommand } from "../core/command.ts";

import { defineCliCommand } from "../core/command.ts";
import { completionScript, isShell, SHELLS } from "../core/completion.ts";
import { CliError } from "../core/errors.ts";
import { commandMeta } from "../core/manifest.ts";

const ARGS = {
  shell: {
    type: "positional",
    required: false,
    description: SHELLS.join(", "),
  },
} as const;

export const completionCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("completion"),
  args: ARGS,
  completions: { shell: () => SHELLS },
  runsWithInvalidConfig: true,
  run: (args) => {
    const shell = args.shell;

    if (shell === undefined || !isShell(shell)) {
      throw new CliError(
        "usage",
        shell === undefined
          ? "Name a shell: bash, zsh or fish."
          : `Unknown shell "${shell}". Use bash, zsh or fish.`,
      );
    }

    const script = completionScript(shell);

    return Promise.resolve({
      code: 0,
      output: script.trimEnd(),
      data: { shell, script },
    });
  },
});
