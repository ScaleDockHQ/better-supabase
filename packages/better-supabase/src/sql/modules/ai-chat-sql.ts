import { sqlString } from "../../core/template.ts";

/** SQL that grants a function to signed-in users and the service role. */
export const userGrant = (signature: string): string =>
  `revoke execute on function ${signature} from public, anon;
grant execute on function ${signature} to authenticated, service_role;`;

/** SQL that grants a function to the service role only. */
export const serviceGrant = (signature: string): string =>
  `revoke execute on function ${signature} from public, anon, authenticated;
grant execute on function ${signature} to service_role;`;

/** `raise exception` with an errcode and a hint the TypeScript side maps. */
export const raise = (
  message: string,
  errcode: string,
  hint: string,
  ...args: readonly string[]
): string =>
  `raise exception ${sqlString(message)}${args.map((arg) => `, ${arg}`).join("")} using errcode = '${errcode}', hint = '${hint}';`;

/** `coalesce(can('tenant', tenant, permission), false)`. */
export const canIn = (tenant: string, permission: string): string =>
  `coalesce(better_supabase.can('tenant', ${tenant}, ${permission}), false)`;
