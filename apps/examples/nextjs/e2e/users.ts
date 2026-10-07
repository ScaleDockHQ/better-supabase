/**
 * The seeded users from `supabase/seed.sql`, and where their sessions are
 * saved. `admin` owns Acme and is a member of Globex, `member` is a member
 * of Acme, and `globex` owns Globex (the free plan, no beta flag).
 */
export const users = {
  admin: {
    email: "admin@acme.test",
    role: "owner",
    organization: "Acme",
    storageState: "e2e/.auth/admin.json",
  },
  member: {
    email: "member@acme.test",
    role: "member",
    organization: "Acme",
    storageState: "e2e/.auth/member.json",
  },
  globex: {
    email: "owner@globex.test",
    role: "owner",
    organization: "Globex",
    storageState: "e2e/.auth/globex.json",
  },
} as const;

export type UserName = keyof typeof users;

export const password = "password123";
