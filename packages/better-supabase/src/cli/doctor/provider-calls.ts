import type { AuthorizationProvider } from "../../config/index.ts";

const escapeRegExp = (text: string): string =>
  text.replaceAll(/[.*+?^${}()|[\]\\]/g, String.raw`\$&`);

/**
 * A pattern for a filled template: `{permission}` captures the key literal
 * (optionally passed by name), `{scope}` captures the scope name, and
 * whitespace may differ.
 */
function templatePattern(template: string): RegExp {
  const source = template
    .split(/(\{\w+\})/)
    .map((part) => {
      if (part === "{permission}") {
        return String.raw`(?:\w+\s*=>\s*)?'((?:[^']|'')*)'`;
      }

      if (part === "{scope}") {
        return "([a-z][a-z0-9_]*)";
      }

      if (/^\{\w+\}$/.test(part)) {
        return String.raw`[\s\S]*?`;
      }

      return escapeRegExp(part.trim()).replaceAll(/\s+/g, String.raw`\s*`);
    })
    .filter((part) => part !== "")
    .join(String.raw`\s*`);

  return new RegExp(source, "gi");
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
    const key = match[idsGroups.indexOf("permission") + 1];

    if (key === undefined) {
      continue;
    }

    const scopeIndex = idsGroups.indexOf("scope");
    calls.push({
      key: key.replaceAll("''", "'"),
      scope: scopeIndex === -1 ? provider.tenantScope : match[scopeIndex + 1]!,
    });
  }

  const platformGroups = groups(isPlatform);

  for (const match of body.matchAll(templatePattern(isPlatform))) {
    const key = match[platformGroups.indexOf("permission") + 1];

    if (key !== undefined) {
      calls.push({ key: key.replaceAll("''", "'"), scope: "platform" });
    }
  }

  return calls;
}
