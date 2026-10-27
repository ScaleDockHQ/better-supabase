/**
 * Renders `codemods/<name>.json`, each codemod's renames as plain JSON, then
 * formats them with Oxfmt.
 */
import { execFileSync } from "node:child_process";
import { writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

import { CODEMOD_FILES, renderCodemodJson } from "../tests/cli/codemod-json.ts";

for (const { file, renames } of CODEMOD_FILES) {
  await writeFile(file, renderCodemodJson(renames));
}

execFileSync(
  "pnpm",
  ["exec", "oxfmt", ...CODEMOD_FILES.map(({ file }) => fileURLToPath(file))],
  { stdio: "inherit" },
);

console.log(`wrote ${CODEMOD_FILES.length} codemod JSON files`);
