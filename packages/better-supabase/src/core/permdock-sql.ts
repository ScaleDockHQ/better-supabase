import { sqlIdent, sqlString } from './template.ts';

const SCOPE = /^[a-z_][a-z0-9_]*$/;
/** PermDock splits a key with row conditions into `key#1`, `key#2`, ...: those need its own policies. */
const SPLIT_KEY = /#\d+$/;

interface PermdockTarget {
  readonly scope: string;
  readonly schema?: string;
}

/**
 * The SQL condition for one PermDock permission key. `id` is the text
 * expression holding the scope id; it is compared as text, so a malformed
 * path never raises a cast error.
 *
 * The helpers check role and scope, not a permission's row conditions, so
 * the condition is only correct for permissions whose grants have none
 * beyond the scope. `#n` keys are refused; other row-conditioned keys can't
 * be detected here.
 */
export function permdockCheck(
  where: string,
  target: PermdockTarget,
  key: string,
  id: string | undefined,
): string {
  if (key === '')
    throw new TypeError(`${where}: a PermDock permission key is empty`);
  if (SPLIT_KEY.test(key)) {
    throw new TypeError(
      `${where}: "${key}" is one part of a permission PermDock splits by row condition. Use PermDock's generated policies for it.`,
    );
  }
  const schema = sqlIdent(target.schema ?? 'public');
  if (target.scope === 'global')
    return `(select ${schema}.permdock_has(${sqlString(key)}))`;
  if (!SCOPE.test(target.scope))
    throw new TypeError(`${where}: invalid PermDock scope "${target.scope}"`);
  if (id === undefined)
    throw new TypeError(`${where}: scope "${target.scope}" needs a segment`);
  return `${id} in (select t.id::text from ${schema}.${sqlIdent(`permitted_${target.scope}_ids`)}(${sqlString(key)}) as t(id))`;
}
