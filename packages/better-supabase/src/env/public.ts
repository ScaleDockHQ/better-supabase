export interface EnvIssue {
  /** The variable names that were checked, first one preferred. */
  readonly variables: readonly string[];
  readonly message: string;
}

const LOOPBACK = /^(localhost|127(?:\.\d{1,3}){3}|\[::1\])$/;

export class EnvValidationError extends Error {
  override readonly name = "EnvValidationError";
  readonly issues: readonly EnvIssue[];

  constructor(issues: readonly EnvIssue[]) {
    super(
      `Invalid Supabase environment:\n${issues.map((issue) => `  - ${issue.variables[0] ?? "env"}: ${issue.message}`).join("\n")}`,
    );
    this.issues = issues;
  }
}

export function checkUrl(
  value: string,
  variables: readonly string[],
  issues: EnvIssue[],
): URL | undefined {
  let url: URL;

  try {
    url = new URL(value);
  } catch {
    issues.push({ variables, message: "is not a valid URL" });

    return undefined;
  }

  if (url.protocol === "https:") {
    return url;
  }

  if (url.protocol === "http:" && LOOPBACK.test(url.hostname)) {
    return url;
  }

  issues.push({
    variables,
    message:
      "must use https (http is only allowed for localhost / 127.0.0.1 / [::1])",
  });

  return undefined;
}

export function checkKey(
  value: string,
  kind: "publishable" | "secret",
  variables: readonly string[],
  issues: EnvIssue[],
): boolean {
  if (value.startsWith(`sb_${kind}_`)) {
    return true;
  }

  if (value.startsWith("eyJ")) {
    issues.push({
      variables,
      message: `is a legacy JWT key; use the new sb_${kind}_ key (Project Settings > API Keys)`,
    });
  } else if (
    value.startsWith(kind === "publishable" ? "sb_secret_" : "sb_publishable_")
  ) {
    issues.push({
      variables,
      message:
        kind === "publishable"
          ? "holds a secret key; never expose sb_secret_ keys as publishable"
          : "holds a publishable key, not a secret key",
    });
  } else {
    issues.push({ variables, message: `must start with sb_${kind}_` });
  }

  return false;
}

/**
 * Validates the URL and publishable key the browser client is given. The full
 * `parseEnv` in `better-supabase/env` also reads the server settings, which a
 * browser bundle does not need.
 */
export function parsePublicEnv(env: {
  readonly url: string;
  readonly publishableKey: string;
}): { readonly url: string; readonly publishableKey: string } {
  const issues: EnvIssue[] = [];
  const rawUrl = env.url.trim();
  const url = rawUrl ? checkUrl(rawUrl, ["SUPABASE_URL"], issues) : undefined;

  if (!rawUrl) {
    issues.push({ variables: ["SUPABASE_URL"], message: "is not set" });
  }

  const key = env.publishableKey.trim();

  if (key) {
    checkKey(key, "publishable", ["SUPABASE_PUBLISHABLE_KEY"], issues);
  } else {
    issues.push({
      variables: ["SUPABASE_PUBLISHABLE_KEY"],
      message: "is not set",
    });
  }

  if (issues.length > 0 || !url) {
    throw new EnvValidationError(issues);
  }

  return { url: url.href.replace(/\/+$/, ""), publishableKey: key };
}
