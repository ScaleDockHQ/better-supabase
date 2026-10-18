/** The anchor rail beside a long catalog page. Plain links: no scroll spy. */
export function OnThisPage({
  items,
}: {
  items: readonly { id: string; label: string }[];
}) {
  return (
    <nav
      aria-label="On this page"
      className="sticky top-24 hidden w-44 shrink-0 flex-col gap-2 self-start text-sm xl:flex"
    >
      <p className="text-xs font-medium text-muted-foreground">On this page</p>
      <ul className="flex flex-col gap-1 border-l border-border">
        {items.map((item) => (
          <li key={item.id}>
            <a
              href={`#${item.id}`}
              className="-ml-px block border-l border-transparent py-0.5 pl-3 text-muted-foreground transition-colors hover:border-foreground hover:text-foreground focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
            >
              {item.label}
            </a>
          </li>
        ))}
      </ul>
    </nav>
  );
}
