import { execFile } from "node:child_process";

import type { FindingInput, Rule } from "./rules.ts";

import { isRecord } from "../guards.ts";

const SEVERITIES = new Set(["error", "warning", "info"]);
const TIMEOUT_MS = 60_000;

function run(
  command: readonly string[],
  cwd: string,
): Promise<{ readonly stdout: string } | { readonly failure: string }> {
  const [file, ...args] = command;

  if (file === undefined) {
    return Promise.resolve({ failure: "the command is empty" });
  }

  return new Promise((done) => {
    execFile(
      file,
      args,
      { cwd, timeout: TIMEOUT_MS, maxBuffer: 16 * 1024 * 1024 },
      (error, stdout) => {
        // A provider doctor exits non-zero when it has findings, so the output
        // decides; only a missing or empty output is a failure.
        if (stdout.trim() === "") {
          done({ failure: error?.message ?? "it printed nothing" });
        } else {
          done({ stdout });
        }
      },
    );
  });
}

/** The findings in a provider doctor's JSON: `{ findings: [...] }` or a list. */
export function providerFindings(stdout: string): FindingInput[] | undefined {
  let parsed: unknown;

  try {
    parsed = JSON.parse(stdout);
  } catch {
    return undefined;
  }

  const list = Array.isArray(parsed)
    ? parsed
    : isRecord(parsed)
      ? parsed["findings"]
      : undefined;

  if (!Array.isArray(list)) {
    return undefined;
  }

  const found: FindingInput[] = [];

  // SAFETY: Array.isArray narrowed `list` to any[]; each entry is checked below.
  for (const entry of list as unknown[]) {
    if (
      !isRecord(entry) ||
      typeof entry["code"] !== "string" ||
      typeof entry["message"] !== "string"
    ) {
      return undefined;
    }

    const where = entry["target"];

    const given = entry["severity"];

    // SAFETY: SEVERITIES holds exactly these three strings.
    const severity =
      typeof given === "string" && SEVERITIES.has(given)
        ? (given as "error" | "warning" | "info")
        : "warning";

    found.push({
      severity,
      title:
        typeof entry["title"] === "string" ? entry["title"] : entry["code"],
      message: entry["message"],
      // The provider's own code leads the target, so each finding keeps its own
      // baseline entry under the one BS705 code.
      target:
        typeof where === "string" ? `${entry["code"]} ${where}` : entry["code"],
      ...(typeof entry["help"] === "string" ? { help: entry["help"] } : {}),
    });
  }

  return found;
}

async function providerDoctor(
  context: Parameters<Rule["check"]>[0],
): Promise<FindingInput[]> {
  const command = context.config.authorization?.doctor?.command;

  if (command === undefined) {
    return [];
  }

  const result = await run(command, context.config.root);

  if ("failure" in result) {
    return [
      {
        message: `The authorization provider's doctor (${command.join(" ")}) gave no findings: ${result.failure}.`,
        target: command.join(" "),
      },
    ];
  }

  return (
    providerFindings(result.stdout) ?? [
      {
        message: `The authorization provider's doctor (${command.join(" ")}) printed JSON that is not { findings: [{ code, message }] }.`,
        target: command.join(" "),
      },
    ]
  );
}

export const PROVIDER_DOCTOR_RULES: readonly Rule[] = [
  {
    code: "BS705",
    severity: "warning",
    title: "The authorization provider's doctor reports a finding",
    description:
      "When `authorization.doctor.command` is set, doctor runs it in the project root and reads `{ findings: [{ code, severity?, title?, message, target?, help? }] }` from its output. Each finding is reported under BS705 with the provider's code first in its target, and the baseline can accept it like any other finding.",
    check: providerDoctor,
  },
];
