import type { ReactNode } from "react";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

export interface Property {
  readonly label: string;
  readonly value: ReactNode;
}

/**
 * The properties rail of a record page: label and value pairs in a Card, for
 * the `aside` of `RecordDetailFrame`. A value that is empty shows a dash.
 */
export function PropertiesRail({
  title,
  properties,
}: {
  title: string;
  properties: readonly Property[];
}) {
  return (
    <Card size="sm">
      <CardHeader>
        <CardTitle>{title}</CardTitle>
      </CardHeader>
      <CardContent>
        <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-sm">
          {properties.map((property) => (
            <div key={property.label} className="contents">
              <dt className="text-muted-foreground">{property.label}</dt>
              <dd className="min-w-0 truncate text-right font-medium">
                {property.value ?? "–"}
              </dd>
            </div>
          ))}
        </dl>
      </CardContent>
    </Card>
  );
}
