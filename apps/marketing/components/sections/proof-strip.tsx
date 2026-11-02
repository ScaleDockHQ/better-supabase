import { Frame, FramePanel } from "@/components/reui/frame";
import { blockCategories, blocks, catalogPresets } from "@/lib/blocks";
import { availableRecipes } from "@/lib/recipes";

const proof: readonly { readonly value: number; readonly label: string }[] = [
  { value: blocks.length, label: "blocks, each with SQL, policies and tests" },
  { value: blockCategories.length, label: "categories, from identity to ERP" },
  {
    value: catalogPresets.length,
    label: "presets that install a whole product",
  },
  {
    value: availableRecipes.length,
    label: "recipes for the UI on web and native",
  },
];

export function ProofStrip() {
  return (
    <section
      aria-label="The catalog in numbers"
      className="mx-auto w-full max-w-7xl px-6 md:px-8"
    >
      <Frame>
        <FramePanel>
          <dl className="grid grid-cols-2 gap-6 lg:grid-cols-4">
            {proof.map((item) => (
              <div key={item.label} className="flex flex-col gap-0.5">
                <dt className="sr-only">{item.label}</dt>
                <dd className="text-3xl font-semibold tracking-tight tabular-nums">
                  {item.value}
                </dd>
                <dd className="text-sm text-muted-foreground">{item.label}</dd>
              </div>
            ))}
          </dl>
        </FramePanel>
      </Frame>
    </section>
  );
}
