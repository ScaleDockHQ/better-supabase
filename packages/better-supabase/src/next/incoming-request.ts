import { cookies, headers } from "next/headers.js";

/**
 * The incoming request, with the cookie header rebuilt from the cookie jar: in
 * a Server Action or a route handler the jar already holds this request's
 * writes (a sign-in, a sign-out), and the header never does.
 */
export async function incomingRequest(): Promise<Request> {
  const [incomingHeaders, jar] = await Promise.all([headers(), cookies()]);
  const forwarded = new Headers(incomingHeaders);

  const cookie = jar
    .getAll()
    .map(({ name, value }) => `${name}=${encodeURIComponent(value)}`)
    .join("; ");

  if (cookie === "") {
    forwarded.delete("cookie");
  } else {
    forwarded.set("cookie", cookie);
  }

  return new Request("http://next.local/", { headers: forwarded });
}
