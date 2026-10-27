import { readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";

import { CODEMOD_FILES, renderCodemodJson } from "./codemod-json.ts";

describe("codemods/*.json", () => {
  it.each(CODEMOD_FILES.map((entry) => [entry.renames.codemod, entry]))(
    "%s matches the codemod (run pnpm gen:codemods)",
    async (_, { file, renames }) => {
      // Compared as JSON: Oxfmt formats the file after the script writes it.
      expect(JSON.parse(await readFile(file, "utf-8"))).toEqual(
        JSON.parse(renderCodemodJson(renames)),
      );
    },
  );

  it("lists the 0.32 import, member and key renames", () => {
    const renames = CODEMOD_FILES[0]!.renames;

    expect(renames.imports["checkSession"]).toBe("verifySession");
    expect(renames.members["getRequestSession"]).toBe("getClaims");
    expect(renames.configKeys["auth.organization"]).toBe("auth.tenant");
    expect(renames.optionKeys["requireOrganization"]).toBe("requireTenant");
  });
});
