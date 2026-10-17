import { Badge } from "@/components/reui/badge";
import { LinkButton } from "@/components/site/link-button";
import { loadChangelog } from "@/lib/changelogs";
import { site } from "@/lib/site";

/** The release timeline, read from the package changelog at build time. */
export async function ChangelogReleases() {
  const releases = await loadChangelog();

  return releases.length === 0 ? (
    <div className="flex flex-col items-start gap-4 rounded-xl border border-border bg-card p-6">
      <p className="text-sm font-semibold">No releases yet</p>
      <p className="text-sm leading-6 text-muted-foreground">
        The first release is on its way. Follow the repository to hear when it
        ships.
      </p>
      <LinkButton variant="outline" href={`${site.github}/releases`}>
        GitHub releases
      </LinkButton>
    </div>
  ) : (
    <ol className="flex flex-col border-l border-border">
      {releases.map((release) => (
        <li
          key={`${release.version}-${release.kind}`}
          className="relative flex flex-col gap-3 pb-10 pl-6 last:pb-0"
        >
          <span
            aria-hidden="true"
            className="absolute top-1.5 -left-1.25 size-2.5 rounded-full bg-brand ring-4 ring-background"
          />
          <div className="flex items-center gap-2">
            <h2 className="font-mono text-base font-semibold">
              {release.version}
            </h2>
            <Badge variant="outline">{release.kind}</Badge>
          </div>
          <ul className="list-disc space-y-1 pl-4 text-sm leading-6">
            {release.changes.map((change) => (
              <li key={change.text}>
                {change.hash ? (
                  <a
                    href={`${site.github}/commit/${change.hash}`}
                    className="font-mono text-xs text-muted-foreground hover:text-foreground"
                  >
                    {change.hash}
                  </a>
                ) : null}
                {change.hash ? " " : null}
                {change.text}
              </li>
            ))}
          </ul>
        </li>
      ))}
    </ol>
  );
}
