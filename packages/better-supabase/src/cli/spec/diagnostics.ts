import type { DiagnosticSeverity, SpecDiagnostic } from "../../spec/index.ts";

import { VERSION } from "../version.ts";

export type FailOn = "error" | "warning" | "never";

export const FAIL_ON: readonly FailOn[] = ["error", "warning", "never"];

export function isFailOn(value: unknown): value is FailOn {
  return value === "error" || value === "warning" || value === "never";
}

/**
 * The codes the `spec` command adds to the ones formats report. Codes are
 * stable; a retired code stays reserved.
 */
export const SPEC_CLI_CODES: Readonly<Record<string, string>> = {
  "schema-invalid":
    "The document does not match the format's official JSON Schema.",
  "schema-unavailable":
    "No official JSON Schema is bundled for this version; only the semantic checks ran.",
  "output-stale": "The file on disk differs from the rendered document.",
  "output-missing": "The file does not exist yet.",
  "ui-unsupported": "The reference UI only renders OpenAPI documents.",
  "document-version":
    "The entry exports a finished document in another version than the one asked for.",
  "lint-failed":
    "The format's semantic lint threw on a finished document the entry exports.",
  "overlay-invalid":
    "An overlay file does not parse or is not an Overlay document.",
  "format-unknown": "No registered document format has this id.",
  "version-unknown": "The format has no such version.",
};

/** True when the diagnostic fails the run under `failOn`. */
export function fails(diagnostic: SpecDiagnostic, failOn: FailOn): boolean {
  switch (failOn) {
    case "error":
      return diagnostic.severity === "error";
    case "warning":
      return diagnostic.severity !== "info";
    case "never":
      return false;
    default: {
      const unknown: never = failOn;
      throw new Error(`Unknown fail-on level: ${String(unknown)}`);
    }
  }
}

export type OutputStatus =
  | "written"
  | "unchanged"
  | "up-to-date"
  | "stale"
  | "validated";

/** One rendered output in the diagnostics manifest. */
export interface ManifestOutput {
  readonly format: string;
  readonly version: string;
  readonly pin: string;
  /** Relative to the project root; absent for `validate` without an output file. */
  readonly path: string;
  readonly sha256: string;
  readonly status: OutputStatus;
  readonly cached: boolean;
  readonly diagnostics: readonly SpecDiagnostic[];
}

/** The diagnostics manifest (`schemas/spec-manifest-v1.json`). No timestamps, so it diffs cleanly. */
export interface SpecManifest {
  readonly $schema: string;
  readonly version: 1;
  readonly generator: string;
  readonly failOn: FailOn;
  readonly ok: boolean;
  readonly outputs: readonly ManifestOutput[];
  readonly summary: Readonly<Record<DiagnosticSeverity, number>>;
}

const MANIFEST_SCHEMA =
  "https://unpkg.com/better-supabase/schemas/spec-manifest-v1.json";

export function buildManifest(
  outputs: readonly ManifestOutput[],
  failOn: FailOn,
  ok: boolean,
): SpecManifest {
  const summary = { error: 0, warning: 0, info: 0 };
  for (const output of outputs)
    for (const diagnostic of output.diagnostics)
      summary[diagnostic.severity] += 1;
  return {
    $schema: MANIFEST_SCHEMA,
    version: 1,
    generator: `better-supabase ${VERSION}`,
    failOn,
    ok,
    outputs,
    summary,
  };
}

const HEADINGS: Readonly<Record<DiagnosticSeverity, string>> = {
  error: "Errors",
  warning: "Warnings",
  info: "Info",
};

/** Findings grouped by severity, each line naming the output, the code and the pointer. */
export function formatDiagnostics(outputs: readonly ManifestOutput[]): string {
  const sections: string[] = [];
  for (const severity of ["error", "warning", "info"] as const) {
    const lines: string[] = [];
    for (const output of outputs)
      for (const diagnostic of output.diagnostics)
        if (diagnostic.severity === severity)
          lines.push(
            `  ${output.path} ${diagnostic.code}${diagnostic.pointer ? ` at ${diagnostic.pointer}` : ""}: ${diagnostic.message}`,
          );
    if (lines.length > 0)
      sections.push(
        `${HEADINGS[severity]} (${lines.length}):\n${lines.join("\n")}`,
      );
  }
  return sections.join("\n");
}
