import * as v from "valibot";

/**
 * The profile columns the example reads from `db.profiles.mine()`, by database
 * name. The row holds more columns; the schema keeps these.
 */
export const ProfileRow = v.object({
  full_name: v.nullish(v.string(), null),
  email: v.nullish(v.string(), null),
  username: v.nullish(v.string(), null),
  avatar_url: v.nullish(v.string(), null),
  avatar_path: v.nullish(v.string(), null),
});

export type ProfileRow = v.InferOutput<typeof ProfileRow>;
