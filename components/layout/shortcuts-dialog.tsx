"use client";

import { SHORTCUTS } from "@/lib/shortcuts";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";

export function ShortcutsDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[380px]">
        <DialogHeader>
          <DialogTitle>Keyboard shortcuts</DialogTitle>
        </DialogHeader>
        <div className="flex flex-col overflow-hidden rounded-lg border">
          {SHORTCUTS.map((s) => (
            <div
              key={s.keys}
              className="flex items-center justify-between border-b bg-card px-3.5 py-[9px] text-[12.5px] last:border-b-0"
            >
              <span className="text-muted-foreground">{s.desc}</span>
              <span className="rounded-[5px] border px-[7px] py-px font-mono text-[11px]">{s.keys}</span>
            </div>
          ))}
        </div>
      </DialogContent>
    </Dialog>
  );
}
