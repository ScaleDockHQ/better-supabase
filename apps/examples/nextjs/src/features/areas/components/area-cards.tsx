import { useExtracted } from "next-intl";

import { DocumentFlow } from "@/components/record-detail/document-flow";
import { Badge } from "@/components/reui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Link, toAppHref } from "@/i18n/navigation";

import { AREAS, PRESET_AREA } from "../areas";

const presetsOf = (id: string): string[] =>
  Object.entries(PRESET_AREA)
    .filter(([, area]) => area === id)
    .map(([preset]) => preset);

export function AreaCards() {
  const t = useExtracted("areas");

  return (
    <div className="grid gap-4 lg:grid-cols-2">
      {AREAS.map((area) => (
        <Card key={area.id}>
          <CardHeader>
            <CardTitle>
              <Link
                href={toAppHref(`/areas/${area.id}`)}
                className="hover:underline"
              >
                {area.name}
              </Link>
            </CardTitle>
            <p className="text-sm text-muted-foreground">{area.flow}</p>
          </CardHeader>
          <CardContent className="flex flex-col gap-3">
            <DocumentFlow
              label={t("Screens of {area}", { area: area.name })}
              steps={area.steps.map((step) => ({
                label: step.label,
                href: step.route,
                state: "todo" as const,
              }))}
            />
            <div className="flex flex-wrap items-center gap-1">
              <span className="text-xs text-muted-foreground">
                {t("Presets")}
              </span>
              {presetsOf(area.id).map((preset) => (
                <Badge key={preset} variant="secondary">
                  {preset}
                </Badge>
              ))}
            </div>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}
