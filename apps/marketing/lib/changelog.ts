export type ChangelogChange = {
  readonly text: string;
  readonly hash?: string;
};

export type ChangelogKind = 'Major' | 'Minor' | 'Patch';

export type ChangelogRelease = {
  readonly version: string;
  readonly kind: ChangelogKind;
  readonly changes: readonly ChangelogChange[];
};

const versionHeading =
  /^## (?<version>[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?)$/u;
const kindHeading = /^### (?<kind>Major|Minor|Patch) Changes$/u;
const changeLine = /^- (?:(?<hash>[0-9a-f]{7,40}): )?(?<text>.+)$/u;
const continuation = /^ {2}\S/u;

/** Parses the CHANGELOG.md that changesets writes, one entry per version and kind. */
export function parseChangelog(markdown: string): ChangelogRelease[] {
  const releases: ChangelogRelease[] = [];
  let version: string | undefined;
  let kind: ChangelogKind | undefined;
  let changes: ChangelogChange[] = [];

  function flush(): void {
    if (version !== undefined && kind !== undefined && changes.length > 0) {
      releases.push({ version, kind, changes });
    }
    changes = [];
  }

  for (const line of markdown.split('\n')) {
    const versionMatch = versionHeading.exec(line);
    if (versionMatch?.groups?.version !== undefined) {
      flush();
      version = versionMatch.groups.version;
      kind = undefined;
      continue;
    }
    const kindMatch = kindHeading.exec(line);
    if (kindMatch?.groups?.kind !== undefined) {
      flush();
      kind = kindMatch.groups.kind as ChangelogKind;
      continue;
    }
    if (kind === undefined) {
      continue;
    }
    const changeMatch = changeLine.exec(line);
    if (changeMatch?.groups?.text !== undefined) {
      const { hash, text } = changeMatch.groups;
      changes.push(hash === undefined ? { text } : { text, hash });
      continue;
    }
    const last = changes.at(-1);
    if (last !== undefined && continuation.test(line)) {
      changes[changes.length - 1] = {
        ...last,
        text: `${last.text} ${line.trim()}`,
      };
    }
  }
  flush();
  return releases;
}
