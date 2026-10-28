import type { Codemod } from "../../src/cli/codemod.ts";

import {
  CODEMOD_0_32,
  CONFIG_KEY_RENAMES_0_32,
  OPTION_KEY_RENAMES_0_32,
} from "../../src/cli/codemod-0-32.ts";

/** A codemod's renames as plain JSON, old name to new name. */
export interface CodemodRenames {
  readonly codemod: string;
  readonly imports: Readonly<Record<string, string>>;
  readonly subpaths: Readonly<Record<string, string>>;
  readonly members: Readonly<Record<string, string>>;
  readonly configKeys: Readonly<Record<string, string>>;
  readonly optionKeys: Readonly<Record<string, string>>;
}

function renamesOf(
  codemod: Codemod,
  keys: Pick<CodemodRenames, "configKeys" | "optionKeys">,
): CodemodRenames {
  return {
    codemod: codemod.name,
    imports: { ...codemod.imports, ...codemod.bindings },
    subpaths: { ...codemod.subpaths },
    members: Object.fromEntries(
      (codemod.members ?? []).map((member) => [member.from, member.to]),
    ),
    configKeys: keys.configKeys,
    optionKeys: {
      ...keys.optionKeys,
      ...Object.fromEntries(
        (codemod.options ?? []).map((option) => [option.from, option.to]),
      ),
    },
  };
}

/** Each published `codemods/<name>.json`, by file URL. */
export const CODEMOD_FILES: readonly {
  readonly file: URL;
  readonly renames: CodemodRenames;
}[] = [
  {
    file: new URL("../../codemods/0.32.json", import.meta.url),
    renames: renamesOf(CODEMOD_0_32, {
      configKeys: CONFIG_KEY_RENAMES_0_32,
      optionKeys: OPTION_KEY_RENAMES_0_32,
    }),
  },
];

export const renderCodemodJson = (renames: CodemodRenames): string =>
  `${JSON.stringify(renames, null, 2)}\n`;
