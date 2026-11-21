/**
 * SQL for how the caller acts, as a label that goes with a row or an event: the
 * profile's own kind (a short lowercase word), `agent` when the token's `act`
 * claim says so, `service`, `system` without a user, or `user`. It labels; no
 * check reads it. `profile` is a `jsonb` expression such as `attrs -> 'actor'`
 * that holds `{ kind, name }` or is null.
 */
export function actorKindSql(profile: string): string {
  return `case
      when ${profile} ->> 'kind' ~ '^[a-z][a-z_-]{0,31}$' then ${profile} ->> 'kind'
      when auth.jwt() -> 'act' ->> 'kind' = 'agent' then 'agent'
      when auth.role() = 'service_role' then 'service'
      when auth.uid() is null then 'system'
      else 'user' end`;
}

/** The profile's name, else the `act` claim's, cut to 120 characters. */
export function actorNameSql(profile: string): string {
  return `left(coalesce(nullif(${profile} ->> 'name', ''), auth.jwt() -> 'act' ->> 'name'), 120)`;
}
