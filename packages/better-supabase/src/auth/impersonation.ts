/** The admin acting as the user, from the RFC 8693 `act` claim. */
export interface Impersonator {
  readonly id: string;
  readonly reason?: string;
}

/** `actingAs(userId, claims, { actor, reason })`: who acts, and why (recorded by the audit module). */
export interface ImpersonationOptions {
  readonly actor: string;
  readonly reason: string;
}

/** The `act` claim for an impersonated session. */
export function actClaim(options: ImpersonationOptions): {
  readonly sub: string;
  readonly reason: string;
} {
  return { sub: options.actor, reason: options.reason };
}

/** The impersonator in `claims.act`, or `undefined` for a normal session. */
export function impersonatorOf(
  claims: Readonly<Record<string, unknown>>,
): Impersonator | undefined {
  const act = claims['act'];
  if (typeof act !== 'object' || act === null) return undefined;
  const { sub, reason } = act as Record<string, unknown>;
  if (typeof sub !== 'string' || sub === '') return undefined;
  return typeof reason === 'string' ? { id: sub, reason } : { id: sub };
}
