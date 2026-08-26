"use client";

import { useRef, useTransition } from "react";
import { Plus, Trash2 } from "lucide-react";
import { toast } from "sonner";

import { addSpaceImageAction, deleteSpaceImageAction } from "@/lib/actions/spaces";
import { Label } from "@/components/ui/label";

export type SpaceImage = { id: string; dataUrl: string; label: string | null };

export function SpaceImageGallery({
  spaceId,
  spaceSlug,
  images,
}: {
  spaceId: string;
  spaceSlug: string;
  images: SpaceImage[];
}) {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [pending, startTransition] = useTransition();

  function handleFile(file: File | undefined) {
    if (!file) return;
    startTransition(() => {
      addSpaceImageAction(spaceId, spaceSlug, file).then((result) => {
        if (result?.error) toast.error(result.error);
      });
    });
  }

  return (
    <div className="space-y-1.5">
      <Label className="text-[13px] font-semibold text-foreground/80">Reference images</Label>
      <p className="text-xs text-muted-foreground">
        Diagrams, mockups, screenshots — sent to the AI alongside your context whenever you
        paste a task in this space.
      </p>
      <div className="flex flex-wrap gap-2.5">
        {images.map((image) => (
          <div key={image.id} className="group relative size-20 shrink-0 overflow-hidden rounded-[7px] border">
            {/* eslint-disable-next-line @next/next/no-img-element -- inline base64 data URLs, not a static asset */}
            <img src={image.dataUrl} alt={image.label ?? "Reference"} className="size-full object-cover" />
            <button
              type="button"
              onClick={() => {
                startTransition(() => {
                  deleteSpaceImageAction(image.id, spaceSlug).catch(() =>
                    toast.error("Couldn't delete image."),
                  );
                });
              }}
              className="absolute inset-0 flex items-center justify-center bg-black/50 text-white opacity-0 transition-opacity group-hover:opacity-100"
            >
              <Trash2 className="size-4" />
              <span className="sr-only">Remove image</span>
            </button>
          </div>
        ))}
        <button
          type="button"
          disabled={pending}
          onClick={() => fileInputRef.current?.click()}
          className="flex size-20 shrink-0 flex-col items-center justify-center gap-1 rounded-[7px] border border-dashed text-muted-foreground transition-colors hover:border-ring/50 hover:text-foreground"
        >
          <Plus className="size-4" />
          <span className="text-[10.5px]">{pending ? "Uploading…" : "Add"}</span>
        </button>
        <input
          ref={fileInputRef}
          type="file"
          accept="image/*"
          className="hidden"
          onChange={(e) => {
            handleFile(e.target.files?.[0]);
            e.target.value = "";
          }}
        />
      </div>
    </div>
  );
}
