/** One check from `import_integrity`. */
export interface IntegrityCheck {
  readonly name: string;
  readonly severity: "error" | "warning";
  readonly count: number;
  readonly ids: readonly string[];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** The CLI shape of an integrity report: one row per check. */
export function integrityReport(value: unknown): {
  readonly checks: readonly IntegrityCheck[];
} {
  if (!isRecord(value) || !Array.isArray(value["checks"])) {
    throw new TypeError("an integrity report has a checks array");
  }

  return {
    checks: value["checks"].map((check) => {
      if (!isRecord(check)) {
        throw new TypeError(
          "an integrity check names a severity, a count and ids",
        );
      }

      const name = check["name"];
      const severity = check["severity"];
      const count = check["count"];
      const ids = check["ids"];

      if (
        typeof name !== "string" ||
        (severity !== "error" && severity !== "warning") ||
        typeof count !== "number" ||
        !Array.isArray(ids)
      ) {
        throw new TypeError(
          "an integrity check names a severity, a count and ids",
        );
      }

      return {
        name,
        severity,
        count,
        ids: ids.map((id: unknown) => {
          if (typeof id !== "string") {
            throw new TypeError("an integrity sample id is text");
          }

          return id;
        }),
      };
    }),
  };
}
