import * as v from "valibot";

import type { UserName } from "./users";

import { stackStatus } from "./stack";
import { password, users } from "./users";

const Session = v.object({ access_token: v.string() });

/**
 * A Supabase access token for a seeded user, from Auth's password grant: what
 * an API or MCP client sends as `Authorization: Bearer`.
 */
export async function accessToken(name: UserName): Promise<string> {
  const stack = stackStatus();

  const response = await fetch(
    `${stack["API_URL"] ?? ""}/auth/v1/token?grant_type=password`,
    {
      method: "POST",
      headers: {
        apikey: stack["PUBLISHABLE_KEY"] ?? "",
        "content-type": "application/json",
      },
      body: JSON.stringify({ email: users[name].email, password }),
    },
  );

  return v.parse(Session, await response.json()).access_token;
}
