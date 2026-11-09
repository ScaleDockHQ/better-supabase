import { describe, expect, it } from "vitest";

import { codesCommand } from "../../../src/cli/commands/codes.ts";
import { ERROR_CODES } from "../../../src/cli/error-codes.ts";
import { resolveConfig } from "../../../src/config/index.ts";

const context = (json: boolean) => ({
  cwd: "/",
  config: resolveConfig({}, "/"),
  io: { stdout: () => undefined, stderr: () => undefined },
  env: {},
  json,
  signal: undefined,
});

describe("codes", () => {
  it("prints the catalog as JSON or a count", async () => {
    const command = codesCommand as {
      run: (input: {
        args: object;
        data: unknown;
      }) => Promise<{
        code: number;
        output?: string;
        data?: { codes?: unknown; count?: number };
      }>;
    };

    const json = await command.run({ args: {}, data: context(true) });

    expect(json.code).toBe(0);
    expect(json.data?.codes).toEqual(ERROR_CODES);
    expect(json.output).toContain(ERROR_CODES[0].code);

    const text = await command.run({ args: {}, data: context(false) });

    expect(text.output).toContain(`${String(ERROR_CODES.length)} error codes`);
    expect(text.data?.count).toBe(ERROR_CODES.length);
  });
});
