/**
 * A callback that decides something a kit would otherwise allow or refuse
 * by default: `authorize`, `canInvite`, `shouldDeliver`, `allowUrl`. Only
 * `true` allows; `false`, any other value, a throw or a rejection denies.
 */
export type Policy<A extends readonly unknown[]> = (
  ...args: A
) => boolean | PromiseLike<boolean>;

export type PolicyDecision =
  | { readonly allowed: true }
  | {
      readonly allowed: false;
      /** `denied`: the policy returned something other than `true`. `threw`: it threw or rejected. */
      readonly reason: "denied" | "threw";
      readonly cause?: unknown;
    };

const ALLOWED: PolicyDecision = { allowed: true };
const DENIED: PolicyDecision = { allowed: false, reason: "denied" };

/**
 * Runs `policy` and fails closed. Without a policy the kit's default
 * applies: `fallback` is true to allow.
 */
export async function decide<A extends readonly unknown[]>(
  policy: Policy<A> | undefined,
  args: A,
  fallback: boolean,
): Promise<PolicyDecision> {
  if (!policy) return fallback ? ALLOWED : DENIED;
  try {
    const allowed: unknown = await policy(...args);
    return allowed === true ? ALLOWED : DENIED;
  } catch (cause) {
    return { allowed: false, reason: "threw", cause };
  }
}
