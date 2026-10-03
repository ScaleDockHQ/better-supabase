import { describe, expect, it } from "vitest";

import type { Snapshot } from "../../../src/cli/introspect/types.ts";

import { formatReport } from "../../../src/cli/doctor/format.ts";
import { RULES, runRules } from "../../../src/cli/doctor/rules.ts";
import { parseToml } from "../../../src/cli/supabase-toml.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { SPEC_PINS } from "../../../src/index.ts";
import { snapshotFixture as fixture } from "../fixtures/library.ts";
import { problems, validatorFor } from "./validator.ts";

interface Sarif {
  $schema: string;
  version: string;
  runs: {
    tool: {
      driver: { name: string; version: string; rules: { id: string }[] };
    };
    results: {
      ruleId: string;
      ruleIndex?: number;
      level: string;
      locations?: { physicalLocation: { artifactLocation: { uri: string } } }[];
    }[];
  }[];
}

async function report(): Promise<Sarif> {
  const snapshot = structuredClone(fixture) as unknown as {
    generator: { tables: { schema: string; rls_enabled: boolean }[] };
  };
  snapshot.generator.tables.find(
    (table) => table.schema === "public",
  )!.rls_enabled = false;
  const findings = await runRules(
    {
      config: resolveConfig({}, "/project"),
      snapshot: snapshot as unknown as Snapshot,
      configToml: {
        path: "supabase/config.toml",
        text: "[auth]\njwt_expiry = 7200\n",
        document: parseToml("[auth]\njwt_expiry = 7200\n"),
        parser: "smol-toml" as const,
      },
      envFiles: [{ path: ".env", text: "SUPABASE_SECRET_KEY=x\n" }],
      gitignore: "",
      sources: [],
    },
    RULES.filter((rule) => rule.code !== "BS303"),
  );
  expect(findings.length).toBeGreaterThan(2);
  return JSON.parse(
    formatReport(findings, {
      format: "sarif",
      rules: RULES,
      version: "1.2.3",
      fallbackFile: "package.json",
    }),
  ) as Sarif;
}

describe("SARIF 2.1.0", () => {
  it("version and $schema follow SPEC_PINS.sarif", async () => {
    const sarif = await report();
    expect(sarif.version).toBe(SPEC_PINS.sarif);
    expect(sarif.$schema).toContain(`sarif-schema-${SPEC_PINS.sarif}.json`);
  });

  it("validates against the official OASIS schema", async () => {
    expect(problems(validatorFor("sarif-2.1.0.json"), await report())).toEqual(
      [],
    );
  });

  it("lists every doctor rule in tool.driver.rules and every result points at a listed rule", async () => {
    const [run] = (await report()).runs;
    expect(run!.tool.driver.name).toBe("better-supabase doctor");
    expect(run!.tool.driver.version).toBe("1.2.3");
    const ids = run!.tool.driver.rules.map((rule) => rule.id);
    expect(ids).toEqual(RULES.map((rule) => rule.code));
    for (const result of run!.results) {
      expect(ids).toContain(result.ruleId);
      expect(ids[result.ruleIndex ?? ids.indexOf(result.ruleId)]).toBe(
        result.ruleId,
      );
      expect(["error", "warning", "note", "none"]).toContain(result.level);
    }
  });

  it("every result has a physical location (GitHub code scanning needs one)", async () => {
    for (const result of (await report()).runs[0]!.results)
      expect(
        result.locations?.[0]?.physicalLocation.artifactLocation.uri,
      ).toMatch(/\S/);
  });
});
