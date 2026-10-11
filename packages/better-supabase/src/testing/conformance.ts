export interface ConformanceCheck {
  readonly name: string;
  readonly ok: boolean;
  readonly message?: string;
}

export interface ConformanceReport {
  /** `Executor "postgrest"`, `CacheAdapter "next"`, ... */
  readonly subject: string;
  readonly checks: readonly ConformanceCheck[];
}

/** Thrown by a conformance kit when any check fails. Lists every failure, not just the first. */
export class ConformanceError extends Error {
  readonly report: ConformanceReport;

  constructor(report: ConformanceReport) {
    const failed = report.checks.filter((check) => !check.ok);
    super(
      `${report.subject} failed ${failed.length} of ${report.checks.length} conformance checks:\n${failed
        .map((check) => `  - ${check.name}: ${check.message ?? "failed"}`)
        .join("\n")}`,
    );
    this.name = "ConformanceError";
    this.report = report;
  }
}

export type Check = readonly [name: string, run: () => void | Promise<void>];

export class Violation extends Error {}

export function expect(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Violation(message);
}

export async function conform(
  subject: string,
  checks: readonly (Check | false | undefined)[],
): Promise<ConformanceReport> {
  const results: ConformanceCheck[] = [];
  for (const entry of checks) {
    if (!entry) continue;
    const [name, run] = entry;
    try {
      await run();
      results.push({ name, ok: true });
    } catch (cause) {
      const message =
        cause instanceof Violation
          ? cause.message
          : `threw ${cause instanceof Error ? `${cause.name}: ${cause.message}` : String(cause)}`;
      results.push({ name, ok: false, message });
    }
  }
  const report = { subject, checks: results };
  if (results.some((check) => !check.ok)) throw new ConformanceError(report);
  return report;
}

export function deepFreeze<T>(value: T): T {
  if (typeof value === "object" && value !== null && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const key of Reflect.ownKeys(value))
      // SAFETY: value is a non-null object here, and Reflect.ownKeys lists its keys.
      deepFreeze((value as Record<PropertyKey, unknown>)[key]);
  }
  return value;
}

export const frozenCopy = <T>(value: T): T =>
  deepFreeze(structuredClone(value));

export const same = (a: unknown, b: unknown): boolean =>
  JSON.stringify(a) === JSON.stringify(b);
