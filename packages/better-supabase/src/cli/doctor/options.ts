import { CliError, errorText } from "../core/errors.ts";
import { DOCTOR_FORMATS, type DoctorFormat } from "../doctor/format.ts";

/** The formats `--format` takes; `--json` picks the JSON one. */
export const FLAG_FORMATS: readonly DoctorFormat[] = DOCTOR_FORMATS.filter(
  (format) => format !== "json",
);

/** `--json` picks the JSON report; `--format`, then `doctor.format`, picks between the others. */
export function reportFormat(
  args: {
    readonly format: string | undefined;
    readonly json: boolean | undefined;
  },
  configured: DoctorFormat,
): DoctorFormat {
  if (args.format === "json") {
    throw new CliError("usage", "--format json is now the global --json flag");
  }

  if (args.json === true) {
    if (args.format !== undefined) {
      throw new CliError("usage", "Pass --json or --format, not both");
    }

    return "json";
  }

  if (args.format === undefined) {
    return configured;
  }

  const format = FLAG_FORMATS.find((candidate) => candidate === args.format);

  if (!format) {
    throw new CliError(
      "usage",
      `--format must be one of ${FLAG_FORMATS.join(", ")}`,
    );
  }

  return format;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** `--as <uuid>` or `--claims <json>` as `request.jwt.claims`. */
export function explainClaims(args: {
  readonly as: string | undefined;
  readonly claims: string | undefined;
}): Record<string, unknown> | { error: string } {
  const as = args.as;
  const claims = args.claims;

  if (as && claims) {
    return { error: "Pass --as or --claims, not both" };
  }

  if (as) {
    if (!UUID.test(as)) {
      return { error: `--as takes a user id (uuid), got "${as}"` };
    }

    return { sub: as, role: "authenticated" };
  }

  if (!claims) {
    return { role: "anon" };
  }

  try {
    // SAFETY: JSON.parse returns any, and the object check below narrows it.
    const parsed = JSON.parse(claims) as unknown;

    if (
      typeof parsed !== "object" ||
      parsed === null ||
      Array.isArray(parsed)
    ) {
      return { error: "--claims takes a JSON object" };
    }

    // SAFETY: the check above narrows parsed to a plain object.
    return { role: "anon", ...(parsed as Record<string, unknown>) };
  } catch (cause) {
    return {
      error: `--claims is not valid JSON: ${errorText(cause)}`,
    };
  }
}
