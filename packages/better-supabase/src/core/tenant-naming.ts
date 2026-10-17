/** The default name of the tenant concept in SQL and method names. */
const DEFAULT_TENANT_NAME = "organization";

const TENANT_NAME = /^[a-z][a-z0-9_]{0,40}$/;
const DEFAULT_PATTERN = /organization(s?)/g;

/** The tenant concept's names, and how they rename a default identifier. */
export interface TenantNames {
  /** `organization`, or the configured name such as `workspace`. */
  readonly singular: string;
  /** `organizations`, `workspaces`, `companies`. */
  readonly plural: string;
  /** Whether the names differ from `organization`. */
  readonly renamed: boolean;
  /**
   * A default identifier with the tenant concept renamed:
   * `create_organization` becomes `create_workspace`, `organizations`
   * becomes `workspaces` and `organization_id` becomes `workspace_id`.
   */
  rename(identifier: string): string;
}

function pluralOf(word: string): string {
  if (/[^aeiou]y$/.test(word)) {
    return `${word.slice(0, -1)}ies`;
  }
  if (/(s|x|z|ch|sh)$/.test(word)) {
    return `${word}es`;
  }
  return `${word}s`;
}

/**
 * The tenant concept's names for `sql.naming.tenant`. Throws on a name that
 * isn't a lowercase identifier.
 */
export function tenantNames(name: string = DEFAULT_TENANT_NAME): TenantNames {
  if (!TENANT_NAME.test(name)) {
    throw new TypeError(
      `sql.naming.tenant: "${name}" is not a lowercase identifier (letters, digits and underscores)`,
    );
  }
  const plural = pluralOf(name);
  const renamed = name !== DEFAULT_TENANT_NAME;
  return {
    singular: name,
    plural,
    renamed,
    rename: (identifier) =>
      renamed
        ? identifier.replaceAll(DEFAULT_PATTERN, (_, s: string) =>
            s === "" ? name : plural,
          )
        : identifier,
  };
}
