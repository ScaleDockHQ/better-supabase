"use client";

import type {
  ComponentRegistry,
  ComponentRenderProps,
  Spec,
} from "@json-render/react";
import type { JsonRenderSpec } from "better-supabase/json-render";

import { JSONUIProvider, Renderer } from "@json-render/react";

type TextProps = ComponentRenderProps<{ text: string }>;

const registry: ComponentRegistry = {
  Stack: ({ children }) => (
    <div className="flex flex-col gap-2">{children}</div>
  ),
  Heading: ({ element }: TextProps) => (
    <h3 className="text-sm font-medium">{element.props.text}</h3>
  ),
  Text: ({ element }: TextProps) => (
    <p className="text-sm text-muted-foreground">{element.props.text}</p>
  ),
};

function rendererSpec(spec: JsonRenderSpec): Spec {
  // SAFETY: JsonRenderSpec is the structural twin of json-render's Spec.
  return spec as Spec;
}

/** Renders a spec a model streamed as `data-spec` parts (see `specOfMessage`). */
export function SpecView({ spec }: { spec: JsonRenderSpec }) {
  return (
    <JSONUIProvider registry={registry}>
      <Renderer registry={registry} spec={rendererSpec(spec)} />
    </JSONUIProvider>
  );
}
