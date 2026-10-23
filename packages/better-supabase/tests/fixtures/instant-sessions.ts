import { writeSession } from "../../src/auth/session.ts";
import { signer, USER } from "./test-server.ts";

export const COOKIE: string = "sb-abcdefghijklmnopqrst-auth-token";

const NAVIGATION = {
  "sec-fetch-dest": "document",
  "sec-fetch-mode": "navigate",
};

/** A session cookie whose access token expired a minute ago. */
export async function expiredCookie(refreshToken: string): Promise<string> {
  const token = await signer.sign({ sub: USER, expiresIn: -60 });

  return writeSession([], COOKIE, {
    access_token: token,
    refresh_token: refreshToken,
    expires_at: Math.floor(Date.now() / 1000) - 60,
    token_type: "bearer",
    user: { id: USER },
  })
    .map((write) => `${write.name}=${encodeURIComponent(write.value)}`)
    .join("; ");
}

/**
 * A page load of `url` with an expired session cookie, or a speculation-rules
 * prefetch of it, which must never refresh.
 */
export async function expiredRequest(
  url: string,
  prefetch: boolean,
): Promise<Request> {
  const headers = new Headers({
    ...NAVIGATION,
    cookie: await expiredCookie(prefetch ? "r-prefetch" : "r-navigate"),
  });

  if (prefetch) {
    headers.set("sec-purpose", "prefetch");
  }

  return new Request(url, { headers });
}
