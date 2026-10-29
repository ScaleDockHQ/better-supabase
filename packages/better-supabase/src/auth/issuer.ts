/**
 * The hosts a local Auth server is reached through: the loopback names and the
 * Android emulator's (`10.0.2.2`) and Genymotion's (`10.0.3.2`) host aliases.
 */
const LOOPBACK_HOSTS: ReadonlySet<string> = new Set([
  "127.0.0.1",
  "localhost",
  "[::1]",
  "10.0.2.2",
  "10.0.3.2",
]);

const PRIVATE_IPV4 =
  /^(?:127\.|10\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.)\d{1,3}\.\d{1,3}$/u;

/** A loopback or private host, never one a public project uses. */
function isLocalHost(hostname: string): boolean {
  return (
    LOOPBACK_HOSTS.has(hostname) ||
    hostname.endsWith(".localhost") ||
    PRIVATE_IPV4.test(hostname)
  );
}

function parse(url: string): URL | undefined {
  try {
    return new URL(url);
  } catch {
    return undefined;
  }
}

/**
 * Whether `iss` names the project's local Auth server through another host: a
 * loopback name or one of `aliases` (such as the LAN IP a device uses), on the
 * same scheme, port and path. Only a loopback or private project URL
 * qualifies.
 */
export function isLoopbackAlias(
  expected: string,
  iss: string,
  aliases: readonly string[] = [],
): boolean {
  const project = parse(expected);
  const issued = parse(iss);

  if (!project || !issued || !isLocalHost(project.hostname)) {
    return false;
  }

  return (
    issued.protocol === project.protocol &&
    issued.port === project.port &&
    issued.pathname === project.pathname &&
    (LOOPBACK_HOSTS.has(issued.hostname) ||
      aliases.includes(issued.hostname) ||
      aliases.includes(issued.host))
  );
}
