import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";

import { DocumentFlow } from "@/components/record-detail/document-flow";
import { KpiBand } from "@/components/record-list/kpi-band";
import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

import { areaKpis } from "../area-kpis";
import { AREAS, PRESET_AREA } from "../areas";

/** The figures of one area: how many records each list of its flow holds. */
export async function AreaKpis({ id }: { id: string }) {
  const area = AREAS.find((candidate) => candidate.id === id);

  if (!area) {
    notFound();
  }

  return <KpiBand kpis={await areaKpis(area.id)} />;
}

/** The flow, the presets and the composite actions of one area. */
export async function AreaFlow({ id }: { id: string }) {
  const area = AREAS.find((candidate) => candidate.id === id);

  if (!area) {
    notFound();
  }

  const t = await getExtracted("areas");

  const presets = Object.entries(PRESET_AREA)
    .filter(([, owner]) => owner === area.id)
    .map(([preset]) => preset);

  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <Card>
        <CardHeader>
          <CardTitle>{t("Flow")}</CardTitle>
          <CardDescription>{area.flow}</CardDescription>
        </CardHeader>
        <CardContent>
          <DocumentFlow
            label={t("Screens of {area}", { area: area.name })}
            steps={area.steps.map((step) => ({
              label: step.label,
              href: step.route,
              state: "todo" as const,
            }))}
          />
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t("Presets and composites")}</CardTitle>
          <CardDescription>
            {t(
              "The blocks this area is built from, and the actions that span them.",
            )}
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-3">
          <div className="flex flex-wrap items-center gap-1">
            {presets.map((preset) => (
              <Badge key={preset} variant="secondary">
                {preset}
              </Badge>
            ))}
          </div>
          {area.actions.length === 0 ? null : (
            <div className="flex flex-wrap items-center gap-1">
              {area.actions.map((action) => (
                <Badge key={action} variant="outline">
                  {action}
                </Badge>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
