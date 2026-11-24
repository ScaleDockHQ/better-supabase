import { useExtracted } from "next-intl";

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { AREAS } from "@/features/areas/areas";
import { Link, toAppHref } from "@/i18n/navigation";

/** One link per product area, from the static area list: it reads nothing. */
export function AreasCard() {
  const t = useExtracted("dashboard");

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("Areas")}</CardTitle>
        <CardDescription>
          {t("Open the hub of an area to walk its flow.")}
        </CardDescription>
      </CardHeader>
      <CardContent>
        <ul className="grid gap-2 text-sm sm:grid-cols-2">
          {AREAS.map((area) => (
            <li key={area.id}>
              <Link
                href={toAppHref(`/areas/${area.id}`)}
                className="flex flex-col rounded-md px-2 py-1 transition-colors hover:bg-muted"
              >
                <span className="font-medium">{area.name}</span>
                <span className="text-xs text-muted-foreground">
                  {area.flow}
                </span>
              </Link>
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  );
}
