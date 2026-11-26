import type { AuthorizationProvider } from "../../config/index.ts";

const escapeRegExp = (text: string): string =>
  text.replaceAll(/[.*+?^${}()|[\]\\]/g, String.raw`\$&`);

/**
 * A type cast as Postgres deparses it after a literal: `::text`, `::character
 * varying`, `::text[]` or a schema-qualified type.
 */
const CAST = String.raw`(?:\s*::\s*[\w."]+(?:\s+varying)?(?:\s*\[\s*\])?)?`;

const LITERAL = String.raw`'(?:[^']|'')*'`;

/**
 * What `{permission}` matches, captured whole: one literal, `ARRAY['a', 'b']`
 * or `'{a,b}'::text[]`, each with the casts Postgres adds when it deparses a
 * policy (`pg_policies.qual`) or a function body (`pg_get_functiondef`).
 */
const PERMISSION = String.raw`(?:\w+\s*=>\s*)?(ARRAY\s*\[[^\]]*\]${CAST}|${LITERAL}${CAST})`;

/**
 * A pattern for a filled template: `{permission}` captures the key expression
 * (optionally passed by name; read it with `keysOf`), `{scope}` captures the
 * scope name, and whitespace may differ. A schema in front of the function name
 * is optional, because Postgres drops it for a schema on the `search_path` and
 * may quote it.
 */
function templatePattern(template: string): RegExp {
  let first = true;

  const source = template
    .split(/(\{\w+\})/)
    .map((part) => {
      if (part === "{permission}") {
        first = false;

        return PERMISSION;
      }

      if (part === "{scope}") {
        first = false;

        return "([a-z][a-z0-9_]*)";
      }

      if (/^\{\w+\}$/.test(part)) {
        first = false;

        return String.raw`[\s\S]*?`;
      }

      const trimmed = part.trim();
      const qualified = first ? /^"?(\w+)"?\.(.*)$/s.exec(trimmed) : null;
      first = false;

      if (qualified) {
        const rest = escapeRegExp(qualified[2]!).replaceAll(
          /\s+/g,
          String.raw`\s*`,
        );

        return String.raw`(?:"?${escapeRegExp(qualified[1]!)}"?\s*\.\s*)?${rest}`;
      }

      return escapeRegExp(trimmed).replaceAll(/\s+/g, String.raw`\s*`);
    })
    .filter((part) => part !== "")
    .join(String.raw`\s*`);

  return new RegExp(source, "gi");
}

const unescapeLiteral = (text: string): string =>
  text.slice(1, -1).replaceAll("''", "'");

/**
 * The permission keys a captured `{permission}` expression names: one for a
 * literal, one per element for `ARRAY[...]` or a `'{a,b}'` array literal.
 */
export function keysOf(expression: string): string[] {
  const text = expression.trim();

  if (/^ARRAY/i.test(text)) {
    return [...text.matchAll(new RegExp(LITERAL, "g"))].map((match) =>
      unescapeLiteral(match[0]),
    );
  }

  const [, body = "", suffix = ""] = /^('(?:[^']|'')*')(.*)$/s.exec(text) ?? [];

  if (body === "") {
    return [];
  }

  const value = unescapeLiteral(body);

  if (suffix.includes("[")) {
    return value
      .replaceAll(/^\{|\}$/g, "")
      .split(",")
      .map((key) => key.trim().replaceAll(/^"|"$/g, ""))
      .filter((key) => key !== "");
  }

  return [value];
}

export interface ProviderCall {
  readonly key: string;
  /** `platform` for `isPlatform`. */
  readonly scope: string;
}

/**
 * The keys and scopes a policy body passes to the provider's `idsWith` and
 * `isPlatform`.
 */
export function providerCalls(
  provider: AuthorizationProvider,
  body: string,
): ProviderCall[] {
  const calls: ProviderCall[] = [];
  const { idsWith, isPlatform } = provider.functions;

  const groups = (template: string): readonly string[] =>
    [...template.matchAll(/\{(permission|scope)\}/g)].map((match) => match[1]!);

  const idsGroups = groups(idsWith);

  for (const match of body.matchAll(templatePattern(idsWith))) {
    const expression = match[idsGroups.indexOf("permission") + 1];

    if (expression === undefined) {
      continue;
    }

    const scopeIndex = idsGroups.indexOf("scope");

    for (const key of keysOf(expression)) {
      calls.push({
        key,
        scope:
          scopeIndex === -1 ? provider.tenantScope : match[scopeIndex + 1]!,
      });
    }
  }

  const platformGroups = groups(isPlatform);

  for (const match of body.matchAll(templatePattern(isPlatform))) {
    const expression = match[platformGroups.indexOf("permission") + 1];

    if (expression !== undefined) {
      for (const key of keysOf(expression)) {
        calls.push({ key, scope: "platform" });
      }
    }
  }

  return calls;
}
