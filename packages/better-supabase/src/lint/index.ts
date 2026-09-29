/**
 * Static checks for better-supabase calls, written against the ESLint rule
 * API so it loads in ESLint (flat config) and in oxlint's `jsPlugins`:
 *
 * ```js
 * import betterSupabase from 'better-supabase/lint';
 * export default [betterSupabase.configs.recommended];
 * ```
 *
 * Rules match calls by method name (`.findMany(...)`, `.deleteMany(...)`)
 * with an inline object literal; spread or variable arguments are skipped
 * rather than guessed at. The runtime `rules()` plugin covers the rest.
 */

interface Node {
  readonly type: string;
}

interface Identifier extends Node {
  readonly type: 'Identifier';
  readonly name: string;
}

interface Literal extends Node {
  readonly type: 'Literal';
  readonly value: unknown;
}

interface Property extends Node {
  readonly type: 'Property';
  readonly key: Node;
  readonly value: Node;
  readonly computed: boolean;
}

interface ObjectExpression extends Node {
  readonly type: 'ObjectExpression';
  readonly properties: readonly Node[];
}

interface MemberExpression extends Node {
  readonly type: 'MemberExpression';
  readonly object: Node;
  readonly property: Node;
  readonly computed: boolean;
}

export interface CallExpression extends Node {
  readonly type: 'CallExpression';
  readonly callee: Node;
  readonly arguments: readonly Node[];
}

export interface RuleContext {
  readonly options: readonly unknown[];
  report(descriptor: {
    readonly node: Node;
    readonly messageId: string;
    readonly data?: Readonly<Record<string, string>>;
  }): void;
}

export interface RuleModule {
  readonly meta: {
    readonly type: 'problem' | 'suggestion';
    readonly docs: { readonly description: string; readonly url: string };
    readonly messages: Readonly<Record<string, string>>;
    readonly schema: readonly unknown[];
  };
  create(context: RuleContext): {
    CallExpression(node: CallExpression): void;
  };
}

const DOCS = 'https://bettersupabase.com/docs/plugins/lint';

function methodName(node: CallExpression): string | undefined {
  const callee = node.callee;
  if (callee.type !== 'MemberExpression') return undefined;
  const member = callee as MemberExpression;
  if (member.computed || member.property.type !== 'Identifier')
    return undefined;
  return (member.property as Identifier).name;
}

/** `users` in `db.users.findMany(...)`. */
function receiverName(node: CallExpression): string | undefined {
  const callee = node.callee as MemberExpression;
  if (callee.object.type !== 'MemberExpression') return undefined;
  const receiver = callee.object as MemberExpression;
  if (receiver.computed || receiver.property.type !== 'Identifier')
    return undefined;
  return (receiver.property as Identifier).name;
}

/** Matches `order_items`, `orderItems` and `public.order_items` alike. */
const tableKey = (name: string): string =>
  (name.split('.').at(-1) ?? name).replace(/_/g, '').toLowerCase();

function keyName(property: Property): string | undefined {
  if (property.computed) return undefined;
  if (property.key.type === 'Identifier')
    return (property.key as Identifier).name;
  if (property.key.type === 'Literal') {
    const value = (property.key as Literal).value;
    return typeof value === 'string' ? value : undefined;
  }
  return undefined;
}

/**
 * The call's first argument as a map of literal keys, `{}` when the call has
 * no arguments, or `undefined` when it cannot be read statically.
 */
function argsOf(node: CallExpression): ReadonlyMap<string, Node> | undefined {
  const [first] = node.arguments;
  if (first === undefined) return new Map();
  if (first.type !== 'ObjectExpression') return undefined;
  const keys = new Map<string, Node>();
  for (const property of (first as ObjectExpression).properties) {
    if (property.type !== 'Property') return undefined;
    const name = keyName(property as Property);
    if (name === undefined) return undefined;
    keys.set(name, (property as Property).value);
  }
  return keys;
}

function numberOf(node: Node | undefined): number | undefined {
  if (node?.type !== 'Literal') return undefined;
  const value = (node as Literal).value;
  return typeof value === 'number' ? value : undefined;
}

function rule(
  description: string,
  name: string,
  messages: Readonly<Record<string, string>>,
  create: RuleModule['create'],
  schema: readonly unknown[] = [],
): RuleModule {
  return {
    meta: {
      type: 'problem',
      docs: { description, url: `${DOCS}#${name}` },
      messages,
      schema,
    },
    create,
  };
}

const FIND_METHODS = new Set(['findMany', 'findFirst', 'paginate']);

export type RuleId =
  | 'no-unbounded-find-many'
  | 'no-delete-many-without-where'
  | 'max-limit'
  | 'require-order-by'
  | 'unbounded-read';

/** The part of `supabase/snapshot.json` that `largeTables` reads. */
export interface LintSnapshot {
  readonly extras: {
    readonly tables: readonly {
      readonly schema: string;
      readonly name: string;
      readonly large?: boolean;
    }[];
  };
}

/**
 * The tables `gen` marked as large (an estimated 10,000 rows or more), as
 * `schema.name`, for the `unbounded-read` rule's `tables` option.
 */
export function largeTables(snapshot: LintSnapshot): string[] {
  return snapshot.extras.tables
    .filter((table) => table.large === true)
    .map((table) => `${table.schema}.${table.name}`);
}

export const rules: Readonly<Record<RuleId, RuleModule>> = {
  'no-unbounded-find-many': rule(
    'Require a limit on findMany',
    'no-unbounded-find-many',
    { unbounded: 'findMany without limit reads every visible row.' },
    (context) => ({
      CallExpression(node) {
        if (methodName(node) !== 'findMany') return;
        const args = argsOf(node);
        if (args && !args.has('limit'))
          context.report({ node, messageId: 'unbounded' });
      },
    }),
  ),
  'no-delete-many-without-where': rule(
    'Require where on deleteMany',
    'no-delete-many-without-where',
    { missing: 'deleteMany without where removes every visible row.' },
    (context) => ({
      CallExpression(node) {
        if (methodName(node) !== 'deleteMany') return;
        const args = argsOf(node);
        if (args && !args.has('where'))
          context.report({ node, messageId: 'missing' });
      },
    }),
  ),
  'max-limit': rule(
    'Cap literal limits',
    'max-limit',
    { tooLarge: 'limit {{limit}} is above the maximum of {{max}}.' },
    (context) => {
      const option = context.options[0] as { max?: number } | undefined;
      const max = option?.max ?? 1000;
      return {
        CallExpression(node) {
          const method = methodName(node);
          if (method === undefined || !FIND_METHODS.has(method)) return;
          const limit = numberOf(argsOf(node)?.get('limit'));
          if (limit !== undefined && limit > max) {
            context.report({
              node,
              messageId: 'tooLarge',
              data: { limit: String(limit), max: String(max) },
            });
          }
        },
      };
    },
    [
      {
        type: 'object',
        properties: { max: { type: 'integer', minimum: 1 } },
        additionalProperties: false,
      },
    ],
  ),
  'require-order-by': rule(
    'Require orderBy when paging with offset',
    'require-order-by',
    { unordered: 'offset without orderBy returns rows in no stable order.' },
    (context) => ({
      CallExpression(node) {
        if (methodName(node) !== 'findMany') return;
        const args = argsOf(node);
        if (args?.has('offset') && !args.has('orderBy'))
          context.report({ node, messageId: 'unordered' });
      },
    }),
  ),
  'unbounded-read': rule(
    'Require limit or paginate on large tables',
    'unbounded-read',
    {
      unbounded:
        'findMany on {{table}} without limit returns at most db-max-rows rows and drops the rest; add limit or use paginate().',
    },
    (context) => {
      const option = context.options[0] as
        | { tables?: readonly string[]; strict?: boolean }
        | undefined;
      const large = new Set((option?.tables ?? []).map(tableKey));
      return {
        CallExpression(node) {
          if (methodName(node) !== 'findMany') return;
          const table = receiverName(node);
          if (table === undefined) return;
          if (!option?.strict && !large.has(tableKey(table))) return;
          const args = argsOf(node);
          if (args && !args.has('limit'))
            context.report({ node, messageId: 'unbounded', data: { table } });
        },
      };
    },
    [
      {
        type: 'object',
        properties: {
          tables: { type: 'array', items: { type: 'string' } },
          strict: { type: 'boolean' },
        },
        additionalProperties: false,
      },
    ],
  ),
};

export const plugin: {
  readonly meta: { readonly name: string };
  readonly rules: Readonly<Record<RuleId, RuleModule>>;
  readonly configs: {
    readonly recommended: {
      readonly plugins: Record<string, unknown>;
      readonly rules: Readonly<
        Partial<Record<`better-supabase/${RuleId}`, 'warn' | 'error'>>
      >;
    };
  };
} = {
  meta: { name: 'better-supabase' },
  rules,
  configs: {
    recommended: {
      plugins: {},
      rules: {
        'better-supabase/no-delete-many-without-where': 'error',
        'better-supabase/no-unbounded-find-many': 'warn',
        'better-supabase/max-limit': 'warn',
        'better-supabase/require-order-by': 'warn',
        'better-supabase/unbounded-read': 'warn',
      },
    },
  },
};
plugin.configs.recommended.plugins['better-supabase'] = plugin;

export default plugin;
