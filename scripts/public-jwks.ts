import * as v from "valibot";

const SigningKeys = v.array(
  v.looseObject({
    d: v.optional(v.string()),
    key_ops: v.optional(v.array(v.string())),
  }),
);

/**
 * The public half of `supabase/signing_keys.json` as the one-line JSON that
 * `SUPABASE_JWKS` takes, or `undefined` when the file holds no usable key. The
 * private member `d` never leaves the file.
 */
export const publicJwks = (signingKeys: string): string | undefined => {
  let json: unknown;

  try {
    json = JSON.parse(signingKeys);
  } catch {
    return undefined;
  }

  const parsed = v.safeParse(SigningKeys, json);

  if (!parsed.success || parsed.output.length === 0) {
    return undefined;
  }

  const keys = parsed.output.map(({ d: _private, key_ops: _ops, ...rest }) => ({
    ...rest,
    key_ops: ["verify"],
  }));

  return JSON.stringify({ keys });
};
