/** The text that replaces a secret in printed output. */
export const REDACTED = "<redacted>";

/**
 * Keys whose string value is a credential: `accessToken`, `webhookSecret`,
 * `dbPassword`, `apiKey`.
 */
const SECRET_KEY =
  /(?:token|secret|password|passphrase|api_?key|private_?key)$/i;

const URL_WITH_PASSWORD = /^[a-z][a-z\d+.-]*:\/\/[^/\s:@]*:[^/\s@]+@/i;

/** A URL with its password replaced, so a connection string is safe to share. */
export function redactUrl(url: string): string {
  try {
    const parsed = new URL(url);

    if (parsed.password === "") {
      return url;
    }

    parsed.password = "redacted";

    return parsed.toString();
  } catch {
    return REDACTED;
  }
}

/** Whether a value under `key` is a credential. */
export const isSecretKey = (key: string): boolean => SECRET_KEY.test(key);

/**
 * `value` with every credential replaced: strings under a secret-looking key
 * become `<redacted>`, and URLs keep everything but their password. Functions
 * and class instances pass through untouched.
 */
export function redact(value: unknown, key = ""): unknown {
  if (typeof value === "string") {
    if (value !== "" && isSecretKey(key)) {
      return REDACTED;
    }

    return URL_WITH_PASSWORD.test(value) ? redactUrl(value) : value;
  }

  if (Array.isArray(value)) {
    return value.map((item: unknown) => redact(item, key));
  }

  if (
    typeof value === "object" &&
    value !== null &&
    Object.getPrototypeOf(value) === Object.prototype
  ) {
    return Object.fromEntries(
      Object.entries(value).map(([name, item]) => [name, redact(item, name)]),
    );
  }

  return value;
}

/**
 * `text` with every value in `secrets` replaced, for logs that may echo a
 * credential.
 */
export function redactText(text: string, secrets: Iterable<string>): string {
  let redacted = text;

  for (const secret of secrets) {
    if (secret.length >= 8) {
      redacted = redacted.replaceAll(secret, REDACTED);
    }
  }

  return redacted;
}
