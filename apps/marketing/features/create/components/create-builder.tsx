"use client";

import type { ReactElement } from "react";

import {
  decodeDesign,
  encodeDesign,
  encodePreset,
  presetOf,
  resolvePreset,
} from "better-supabase/preset";
import { SlidersHorizontalIcon, TerminalIcon } from "lucide-react";
import { useSearchParams } from "next/navigation";
import { useCallback, useEffect, useMemo, useState } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { Toaster } from "@/components/ui/sonner";
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
import { clearDraft, readDraft, writeDraft } from "@/lib/create-draft";
import {
  authChoiceOf,
  type AuthzLibrary,
  initialAuthz,
  withAuthChoice,
} from "@/lib/create-options";
import { presetPrompt } from "@/lib/create-prompt";
import { EMPTY_DESIGN } from "@/lib/design";
import { site } from "@/lib/site";

import { CanvasBridgeProvider, useCanvasBridgeState } from "./canvas-bridge";
import { DesignProvider, useDesignState } from "./design-provider";
import { GetCodeDialog } from "./get-code-dialog";
import { OptionsPanel, type PackageOption } from "./options-panel";
import { SchemaDiagram } from "./schema-diagram";

function initialPackage(value: string | null): PackageOption {
  const dir = packageDir(value);

  return dir === undefined
    ? { on: false, dir: DEFAULT_PACKAGE }
    : { on: true, dir };
}

type Outcome<T> =
  | { readonly ok: true; readonly value: T }
  | { readonly ok: false; readonly message: string };

async function attempt<T>(run: () => Promise<T>): Promise<Outcome<T>> {
  try {
    return { ok: true, value: await run() };
  } catch (error) {
    return {
      ok: false,
      message: error instanceof Error ? error.message : String(error),
    };
  }
}

/**
 * The options in a rail on the left (a sheet on small screens) and the
 * schema the selection installs on the right. The URL keeps the preset code,
 * the canvas design and the monorepo package, so a link restores them.
 */
export function CreateBuilder(): ReactElement {
  const params = useSearchParams();

  const designValue = useDesignState(
    () => initialPreset(params.get("preset")),
    EMPTY_DESIGN,
  );

  const { preset, design } = designValue.state;
  const { reset, restore, setPreset } = designValue.actions;

  const [linkedDesign] = useState(() => params.get("design"));

  const [linked] = useState(
    () => params.get("preset") !== null || linkedDesign !== null,
  );

  const [designLoaded, setDesignLoaded] = useState(linkedDesign === null);

  const [designCode, setDesignCode] = useState("");

  const [authzOption, setAuthzOption] = useState<AuthzLibrary | undefined>(() =>
    initialAuthz(params.get("authz"), initialPreset(params.get("preset"))),
  );

  const [pkgOption, setPkgOption] = useState<PackageOption>(() =>
    initialPackage(params.get("package")),
  );

  const [codeOpen, setCodeOpen] = useState(false);
  const [optionsOpen, setOptionsOpen] = useState(false);

  const bridge = useCanvasBridgeState(
    useCallback(() => {
      // The rail shows from `lg` up; below that the options are a sheet.
      if (!window.matchMedia("(min-width: 64rem)").matches) {
        setOptionsOpen(true);
      }
    }, []),
  );

  const resolved = useMemo(() => resolvePreset(preset), [preset]);

  const groups = useMemo(
    () => blockGroups(preset, resolved),
    [preset, resolved],
  );

  const code = encodePreset(preset);
  const named = matchingPreset(preset);
  const pkg = pkgOption.on ? packageDir(pkgOption.dir) : undefined;
  const authz = preset.access === "provider" ? authzOption : undefined;

  const aiPrompt = useMemo(
    () =>
      presetPrompt({
        resolved,
        design,
        designCode,
        ui: false,
        manager: "pnpm",
        pkg,
        authz,
        siteUrl: site.url,
      }),
    [resolved, design, designCode, pkg, authz],
  );

  useEffect(() => {
    if (linkedDesign === null) {
      return;
    }

    let current = true;

    void attempt(() => decodeDesign(linkedDesign)).then((outcome) => {
      if (!current) {
        return;
      }

      if (outcome.ok) {
        reset(outcome.value);
      } else {
        toast.error("The design in this link can't be read", {
          description: outcome.message,
        });
      }

      setDesignLoaded(true);
    });

    return () => {
      current = false;
    };
  }, [linkedDesign, reset]);

  useEffect(() => {
    if (linked) {
      return;
    }

    const draft = readDraft(window.localStorage);

    if (draft === undefined) {
      return;
    }

    const restoreDraft = async (): Promise<void> => {
      const outcome = await attempt(async () => ({
        saved: presetOf(draft.preset),
        decoded: await decodeDesign(draft.design),
      }));

      if (outcome.ok) {
        restore(outcome.value.saved, outcome.value.decoded);
      } else {
        clearDraft(window.localStorage);
        toast.error("The saved design can't be read", {
          description: outcome.message,
        });
      }
    };

    toast("Your last design is saved in this browser", {
      duration: 10_000,
      action: {
        label: "Restore",
        onClick: () => {
          void restoreDraft();
        },
      },
    });
  }, [linked, restore]);

  useEffect(() => {
    let current = true;

    void attempt(() => encodeDesign(design)).then((outcome) => {
      if (!current) {
        return;
      }

      if (outcome.ok) {
        setDesignCode(outcome.value);
      } else {
        toast.error("The design is too large for a link", {
          id: "design-code",
          description: outcome.message,
        });
      }
    });

    return () => {
      current = false;
    };
  }, [design]);

  useEffect(() => {
    if (!designLoaded) {
      return;
    }

    const href = createHref(preset, pkg, authz, designCode);

    if (`${window.location.pathname}${window.location.search}` !== href) {
      window.history.replaceState(null, "", href);
    }

    if (designCode !== "") {
      writeDraft(window.localStorage, { preset: code, design: designCode });
    }
  }, [preset, pkg, authz, code, designCode, designLoaded]);

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
      authChoice={authChoiceOf(preset, authz)}
      onPreset={setPreset}
      onAuthChoice={(choice) => {
        setPreset((current) => withAuthChoice(current, choice).preset);
        setAuthzOption(withAuthChoice(preset, choice).authz);
      }}
      onNamedPreset={(name) => {
        setPreset((current) => applyNamedPreset(current, name));
      }}
      onToggleBlock={(name) => {
        setPreset((current) => toggleBlock(current, name));
      }}
      onPackage={setPkgOption}
      aiPrompt={aiPrompt}
      onShuffle={() => {
        const next = shuffledPreset(named);
        setPreset((current) => applyNamedPreset(current, next));
      }}
      onGetCode={openCode}
    />
  );

  return (
    <DesignProvider value={designValue}>
      <CanvasBridgeProvider value={bridge}>
        <div className="flex w-full flex-1">
          <aside
            aria-label="Options"
            className="sticky top-14 hidden h-[calc(100svh-3.5rem)] w-80 shrink-0 flex-col border-r border-border lg:flex"
          >
            {panel}
          </aside>

          <Sheet open={optionsOpen} onOpenChange={setOptionsOpen}>
            <SheetContent
              side="left"
              className="gap-0 p-0 data-[side=left]:w-full data-[side=left]:sm:max-w-80"
            >
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
              designCode={designCode}
              resolved={resolved}
              pkg={pkg}
              onStart={() => {
                setPreset((current) =>
                  applyNamedPreset(current, DEFAULT_PRESET),
                );
              }}
              onRemoveBlock={(name) => {
                setPreset((current) => toggleBlock(current, name));
              }}
            />
          </section>

          <GetCodeDialog
            open={codeOpen}
            onOpenChange={setCodeOpen}
            code={code}
            resolved={resolved}
            pkg={pkg}
            authz={authz}
            design={design}
            designCode={designCode}
          />
          <Toaster />
        </div>
      </CanvasBridgeProvider>
    </DesignProvider>
  );
}
