import type { Format, Paint } from "../style.ts";
import type { Finding, Rule, Severity } from "./rules.ts";

import { byCodePoint } from "../compare.ts";
import { plain } from "../style.ts";
import { DOCS_URL } from "./rules.ts";

export type DoctorFormat = "text" | "json" | "sarif" | "github";

export const DOCTOR_FORMATS: readonly DoctorFormat[] = [
  "text",
  "json",
  "sarif",
  "github",
];

const DOCTOR_REPORT_SCHEMA_URL =
  "https://unpkg.com/better-supabase/schemas/doctor-report-v1.json";

const SARIF_SCHEMA_URL =
  "https://docs.oasis-open.org/sarif/sarif/v2.1.0/errata01/os/schemas/sarif-schema-2.1.0.json";

interface DoctorSummary {
  readonly errors: number;
  readonly warnings: number;
  readonly infos: number;
}

function summarize(findings: readonly Finding[]): DoctorSummary {
  return {
    errors: findings.filter((finding) => finding.severity === "error").length,
    warnings: findings.filter((finding) => finding.severity === "warning")
      .length,
    infos: findings.filter((finding) => finding.severity === "info").length,
  };
}

const plural = (count: number, word: string): string =>
  `${count} ${word}${count === 1 ? "" : "s"}`;

const SEVERITY_FORMAT: Readonly<Record<Severity, Format>> = {
  error: "red",
  warning: "yellow",
  info: "cyan",
};

/** A text report this long starts with one line per rule and its count. */
const SUMMARY_FROM = 20;

/** One line per rule, worst severity first, then the largest count. */
function ruleCounts(findings: readonly Finding[], paint: Paint): string[] {
  const order: readonly Severity[] = ["error", "warning", "info"];
  const counts = new Map<string, { finding: Finding; count: number }>();

  for (const finding of findings) {
    const seen = counts.get(finding.code);

    counts.set(finding.code, {
      finding: seen?.finding ?? finding,
      count: (seen?.count ?? 0) + 1,
    });
  }

  return [...counts.values()]
    .toSorted(
      (a, b) =>
        order.indexOf(a.finding.severity) - order.indexOf(b.finding.severity) ||
        b.count - a.count ||
        byCodePoint(a.finding.code, b.finding.code),
    )
    .map(
      ({ finding, count }) =>
        `${paint(SEVERITY_FORMAT[finding.severity], finding.severity.padEnd(7))} ${paint("bold", finding.code)} ${String(count).padStart(5)}  ${finding.title}`,
    );
}

function text(
  findings: readonly Finding[],
  paint: Paint,
  phases: readonly DoctorPhase[] = [],
): string {
  if (findings.length === 0) {
    return "No problems found.";
  }

  const order: readonly Severity[] = ["error", "warning", "info"];

  const body = [...findings]
    .toSorted(
      (a, b) =>
        order.indexOf(a.severity) - order.indexOf(b.severity) ||
        byCodePoint(a.code, b.code),
    )
    .flatMap((finding) => [
      `${paint(SEVERITY_FORMAT[finding.severity], finding.severity.padEnd(7))} ${paint("bold", finding.code)} ${finding.title}${finding.location ? `  ${finding.location.file}:${finding.location.line}` : ""}`,
      `        ${finding.message.replaceAll("\n", "\n        ")}`,
      `        ${finding.help}`,
    ]);

  const lines =
    findings.length >= SUMMARY_FROM
      ? [...ruleCounts(findings, paint), "", ...body]
      : body;

  const summary = summarize(findings);
  lines.push(
    "",
    `${plural(summary.errors, "error")}, ${plural(summary.warnings, "warning")}, ${plural(summary.infos, "note")}.`,
  );

  if (phases.length > 0) {
    lines.push(
      `Time: ${phases.map((phase) => `${phase.name} ${(phase.ms / 1000).toFixed(1)} s`).join(", ")}.`,
    );
  }

  return lines.join("\n");
}

function sarifLevel(severity: Severity): "error" | "warning" | "note" {
  switch (severity) {
    case "error": {
      return "error";
    }

    case "warning": {
      return "warning";
    }

    case "info": {
      return "note";
    }

    default: {
      const unreachable: never = severity;

      return unreachable;
    }
  }
}

function sarif(
  findings: readonly Finding[],
  rules: readonly Rule[],
  version: string,
  fallback: string,
): unknown {
  return {
    $schema: SARIF_SCHEMA_URL,
    version: "2.1.0",
    runs: [
      {
        tool: {
          driver: {
            name: "better-supabase doctor",
            version,
            informationUri: DOCS_URL,
            rules: rules.map((rule) => ({
              id: rule.code,
              name: rule.title.replaceAll(
                /[^A-Za-z0-9]+(.)?/g,
                (_, char: string | undefined) => (char ?? "").toUpperCase(),
              ),
              shortDescription: { text: rule.title },
              fullDescription: { text: rule.description },
              helpUri: `${DOCS_URL}#${rule.code.toLowerCase()}`,
              defaultConfiguration: { level: sarifLevel(rule.severity) },
            })),
          },
        },
        results: findings.map((finding) => ({
          ruleId: finding.code,
          ruleIndex: rules.findIndex((rule) => rule.code === finding.code),
          level: sarifLevel(finding.severity),
          message: { text: finding.message },
          locations: [
            {
              physicalLocation: {
                artifactLocation: { uri: finding.location?.file ?? fallback },
                region: { startLine: finding.location?.line ?? 1 },
              },
            },
          ],
          partialFingerprints: {
            target: `${finding.code}:${finding.target ?? finding.message}`,
          },
        })),
      },
    ],
  };
}

const escapeData = (value: string): string =>
  value.replaceAll("%", "%25").replaceAll("\r", "%0D").replaceAll("\n", "%0A");

const escapeProperty = (value: string): string =>
  escapeData(value).replaceAll(":", "%3A").replaceAll(",", "%2C");

function github(findings: readonly Finding[]): string {
  return findings
    .map((finding) => {
      const command = finding.severity === "info" ? "notice" : finding.severity;

      const properties = [
        ...(finding.location
          ? [
              `file=${escapeProperty(finding.location.file)}`,
              `line=${finding.location.line}`,
            ]
          : []),
        `title=${escapeProperty(`${finding.code} ${finding.title}`)}`,
      ];

      return `::${command} ${properties.join(",")}::${escapeData(`${finding.message} (${finding.help})`)}`;
    })
    .join("\n");
}

/** How long one doctor phase took. */
export interface DoctorPhase {
  readonly name: string;
  readonly ms: number;
}

export interface FormatOptions {
  /** The phases to print under the text report and list in the JSON one. */
  readonly phases?: readonly DoctorPhase[];
  readonly format: DoctorFormat;
  readonly rules: readonly Rule[];
  readonly version: string;
  /** File SARIF results point at when a finding has no location. */
  readonly fallbackFile: string;
  /** Colors the text format's severities; plain by default. */
  readonly paint?: Paint;
}

/** The `doctor-report-v1.json` document that `--json` prints. */
export interface DoctorReport {
  readonly $schema: string;
  readonly version: 1;
  readonly tool: { readonly name: string; readonly version: string };
  readonly summary: DoctorSummary;
  readonly findings: readonly Finding[];
  readonly phases?: readonly DoctorPhase[];
}

export function jsonReport(
  findings: readonly Finding[],
  version: string,
  phases?: readonly DoctorPhase[],
): DoctorReport {
  return {
    $schema: DOCTOR_REPORT_SCHEMA_URL,
    version: 1,
    tool: { name: "better-supabase", version },
    summary: summarize(findings),
    findings,
    ...(phases && phases.length > 0 ? { phases } : {}),
  };
}

export function formatReport(
  findings: readonly Finding[],
  options: FormatOptions,
): string {
  switch (options.format) {
    case "text": {
      return text(findings, options.paint ?? plain, options.phases);
    }

    case "json": {
      return JSON.stringify(
        jsonReport(findings, options.version, options.phases),
        null,
        2,
      );
    }

    case "sarif": {
      return JSON.stringify(
        sarif(findings, options.rules, options.version, options.fallbackFile),
        null,
        2,
      );
    }

    case "github": {
      return github(findings);
    }

    default: {
      const unreachable: never = options.format;

      return unreachable;
    }
  }
}
