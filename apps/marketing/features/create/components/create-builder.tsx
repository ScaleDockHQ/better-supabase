"use client";

import type { ReactElement } from "react";

import {
  encodePreset,
  type Preset,
  resolvePreset,
} from "better-supabase/preset";
import { SlidersHorizontalIcon, TerminalIcon } from "lucide-react";
import { useSearchParams } from "next/navigation";
import { useEffect, useMemo, useState } from "react";

import { Button } from "@/components/ui/button";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import {
  applyNamedPreset,
  blockGroups,
  createHref,
  DEFAULT_PACKAGE,
  DEFAULT_PRESET,
  initialPreset,
  matchingPreset,
  packageDir,
  shuffledPreset,
  toggleBlock,
} from "@/lib/create";

import { GetCodeDialog } from "./get-code-dialog";
import { OptionsPanel, type PackageOption } from "./options-panel";
import { SchemaDiagram } from "./schema-diagram";

function initialPackage(value: string | null): PackageOption {
  const dir = packageDir(value);

  return dir === undefined
    ? { on: false, dir: DEFAULT_PACKAGE }
    : { on: true, dir };
}

/**
 * The options in a rail on the left (a sheet on small screens) and the
 * schema the selection installs on the right. The URL keeps the preset code
 * and the monorepo package, so a link restores both.
 */
export function CreateBuilder(): ReactElement {
  const params = useSearchParams();

  const [preset, setPreset] = useState<Preset>(() =>
    initialPreset(params.get("preset")),
  );

  const [pkgOption, setPkgOption] = useState<PackageOption>(() =>
    initialPackage(params.get("package")),
  );

  const [codeOpen, setCodeOpen] = useState(false);
  const [optionsOpen, setOptionsOpen] = useState(false);

  const resolved = useMemo(() => resolvePreset(preset), [preset]);

  const groups = useMemo(
    () => blockGroups(preset, resolved),
    [preset, resolved],
  );

  const code = encodePreset(preset);
  const named = matchingPreset(preset);
  const pkg = pkgOption.on ? packageDir(pkgOption.dir) : undefined;

  useEffect(() => {
    const href = createHref(preset, pkg);

    if (`${window.location.pathname}${window.location.search}` !== href) {
      window.history.replaceState(null, "", href);
    }
  }, [preset, pkg]);

  const openCode = (): void => {
    setOptionsOpen(false);
    setCodeOpen(true);
  };

  const panel = (
    <OptionsPanel
      preset={preset}
      resolved={resolved}
      named={named}
      code={code}
      groups={groups}
      pkg={pkgOption}
      onPreset={setPreset}
      onNamedPreset={(name) => {
        setPreset((current) => applyNamedPreset(current, name));
      }}
      onToggleBlock={(name) => {
        setPreset((current) => toggleBlock(current, name));
      }}
      onPackage={setPkgOption}
      onShuffle={() => {
        const next = shuffledPreset(named);
        setPreset((current) => applyNamedPreset(current, next));
      }}
      onGetCode={openCode}
    />
  );

  return (
    <div className="flex w-full flex-1">
      <aside
        aria-label="Options"
        className="sticky top-14 hidden h-[calc(100svh-3.5rem)] w-80 shrink-0 flex-col border-r border-border lg:flex"
      >
        {panel}
      </aside>

      <Sheet open={optionsOpen} onOpenChange={setOptionsOpen}>
        <SheetContent side="left" className="w-80 gap-0 p-0 sm:max-w-80">
          <SheetHeader className="border-b border-border">
            <SheetTitle>Customize</SheetTitle>
            <SheetDescription>
              The preset, the stack and the blocks.
            </SheetDescription>
          </SheetHeader>
          {optionsOpen ? panel : null}
        </SheetContent>
      </Sheet>

      <section
        aria-label="Schema"
        className="flex min-h-[calc(100svh-3.5rem)] min-w-0 flex-1 flex-col"
      >
        <div className="flex items-center gap-2 border-b border-border px-4 py-2 lg:hidden">
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={() => {
              setOptionsOpen(true);
            }}
          >
            <SlidersHorizontalIcon aria-hidden="true" />
            Customize
          </Button>
          <Button
            type="button"
            size="sm"
            className="ml-auto"
            onClick={openCode}
          >
            <TerminalIcon aria-hidden="true" />
            Get code
          </Button>
        </div>
        <SchemaDiagram
          code={code}
          resolved={resolved}
          pkg={pkg}
          onStart={() => {
            setPreset((current) => applyNamedPreset(current, DEFAULT_PRESET));
          }}
        />
      </section>

      <GetCodeDialog
        open={codeOpen}
        onOpenChange={setCodeOpen}
        code={code}
        resolved={resolved}
        pkg={pkg}
      />
    </div>
  );
}
