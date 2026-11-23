import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { readDotenv } from "../../../src/cli/doctor/dotenv.ts";
import { ENV_RULES } from "../../../src/cli/doctor/env.ts";

describe("readDotenv", () => {
  it("reads keys, export, spaces around = and quoted values with their lines", () => {
    expect(
      readDotenv(
        [
          "A=1",
          "export B = two",
          'C="three"',
          "D='four'",
          "E=",
          "",
          "F=a#b",
        ].join("\n"),
      ),
    ).toEqual([
      { key: "A", value: "1", line: 1 },
      { key: "B", value: "two", line: 2 },
      { key: "C", value: "three", line: 3 },
      { key: "D", value: "four", line: 4 },
      { key: "E", value: "", line: 5 },
      { key: "F", value: "a#b", line: 7 },
    ]);
  });

  it("skips comment lines and drops a comment after the value", () => {
    expect(
      readDotenv(
        [
          "# SUPABASE_SECRET_KEY=sb_secret_in_a_comment",
          "  # NEXT_PUBLIC_SECRET=x",
          "A=1 # trailing note",
          'B="two" # SUPABASE_SERVICE_ROLE_KEY=x',
          "C=#all comment",
        ].join("\n"),
      ),
    ).toEqual([
      { key: "A", value: "1", line: 3 },
      { key: "B", value: "two", line: 4 },
      { key: "C", value: "", line: 5 },
    ]);
  });

  it("keeps a multi-line quoted value in one entry and counts its lines", () => {
    expect(
      readDotenv(
        'KEY="-----BEGIN\nNEXT_PUBLIC_SECRET=inside\n-----END"\nAFTER=1\r\n',
      ),
    ).toEqual([
      {
        key: "KEY",
        value: "-----BEGIN\nNEXT_PUBLIC_SECRET=inside\n-----END",
        line: 1,
      },
      { key: "AFTER", value: "1", line: 4 },
    ]);
  });

  it("treats an unterminated quote as the rest of the line", () => {
    expect(readDotenv('A="open\nB=2')).toEqual([
      { key: "A", value: '"open', line: 1 },
      { key: "B", value: "2", line: 2 },
    ]);
  });
});

describe("env rules read comments as comments", () => {
  const run = (code: string, text: string) =>
    ENV_RULES.find((rule) => rule.code === code)!.check({
      envFiles: [{ path: ".env.local", text }],
      gitignore: "",
    } as unknown as DoctorContext);

  it("BS501 ignores a commented secret and a secret inside a quoted value", async () => {
    expect(
      await run(
        "BS501",
        '# NEXT_PUBLIC_SERVICE_ROLE_KEY=x\nNOTE="a\nVITE_SECRET=b"\nNEXT_PUBLIC_SERVICE_ROLE_KEY=x\n',
      ),
    ).toHaveLength(1);
  });

  it("BS502 ignores a secret named only in a comment", async () => {
    expect(
      await run("BS502", "# SUPABASE_SECRET_KEY=sb_secret_x\nA=1\n"),
    ).toEqual([]);
  });

  it("BS506 ignores a commented URL", async () => {
    expect(
      await run(
        "BS506",
        "SUPABASE_URL=http://127.0.0.1:54321 # NEXT_PUBLIC_SUPABASE_URL=https://other.example.com\n# NEXT_PUBLIC_SUPABASE_URL=https://other.example.com\n",
      ),
    ).toEqual([]);
  });
});
