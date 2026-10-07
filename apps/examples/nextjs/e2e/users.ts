/** The seeded users from `supabase/seed.sql`, and where their sessions are saved. */
export const users = {
  admin: { email: "admin@acme.test", storageState: "e2e/.auth/admin.json" },
  member: { email: "member@acme.test", storageState: "e2e/.auth/member.json" },
} as const;

export const password = "password123";
