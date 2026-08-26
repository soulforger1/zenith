"use client";

import { useState, useTransition } from "react";
import { format } from "date-fns";
import { RefreshCw, Trash2 } from "lucide-react";
import { toast } from "sonner";

import { createRepoAction, deleteRepoAction, syncRepoContextAction } from "@/lib/actions/repos";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";

export type RepoSummary = { id: string; name: string; url: string; cachedAt: string | null };

export function RepoManager({
  spaceId,
  spaceSlug,
  repos,
}: {
  spaceId: string;
  spaceSlug: string;
  repos: RepoSummary[];
}) {
  const [name, setName] = useState("");
  const [url, setUrl] = useState("");
  const [syncingId, setSyncingId] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function handleAdd() {
    if (!name.trim() || !url.trim()) return;
    startTransition(() => {
      createRepoAction(spaceId, spaceSlug, { name: name.trim(), url: url.trim() }).then((result) => {
        if (result?.error) {
          toast.error(result.error);
          return;
        }
        setName("");
        setUrl("");
      });
    });
  }

  function handleDelete(id: string) {
    startTransition(() => {
      deleteRepoAction(id, spaceSlug).catch(() => toast.error("Couldn't remove that repo."));
    });
  }

  function handleSync(id: string) {
    setSyncingId(id);
    syncRepoContextAction(id, spaceSlug)
      .then((result) => {
        if (result?.error) toast.error(result.error);
        else toast.success("Repo context synced");
      })
      .catch(() => toast.error("Couldn't sync from GitHub."))
      .finally(() => setSyncingId(null));
  }

  return (
    <div className="space-y-1.5">
      <Label className="text-[13px] font-semibold text-foreground/80">GitHub repos</Label>
      <p className="text-xs text-muted-foreground">
        Link one or more repos to this space. When you paste a task that names one, the AI uses
        its synced context — repo content is only ever fetched when you hit Sync, never per task.
      </p>

      {repos.length > 0 ? (
        <div className="flex flex-col overflow-hidden rounded-lg border">
          {repos.map((repo) => (
            <div
              key={repo.id}
              className="flex items-center justify-between gap-2 border-b bg-card px-3 py-2 text-[12.5px] last:border-b-0"
            >
              <div className="min-w-0">
                <div className="font-medium">{repo.name}</div>
                <div className="truncate text-muted-foreground">{repo.url}</div>
              </div>
              <div className="flex shrink-0 items-center gap-2">
                <span className="text-[11px] text-muted-foreground">
                  {repo.cachedAt ? `Synced ${format(new Date(repo.cachedAt), "MMM d")}` : "Not synced"}
                </span>
                <button
                  type="button"
                  disabled={syncingId === repo.id}
                  onClick={() => handleSync(repo.id)}
                  className="flex items-center gap-1 rounded-[5px] border px-1.5 py-1 text-[11px] text-muted-foreground transition-colors hover:text-foreground disabled:opacity-50"
                >
                  <RefreshCw className={syncingId === repo.id ? "size-3 animate-spin" : "size-3"} />
                  {syncingId === repo.id ? "Syncing…" : "Sync"}
                </button>
                <button
                  type="button"
                  onClick={() => handleDelete(repo.id)}
                  className="text-muted-foreground transition-colors hover:text-destructive"
                >
                  <Trash2 className="size-3.5" />
                  <span className="sr-only">Remove {repo.name}</span>
                </button>
              </div>
            </div>
          ))}
        </div>
      ) : null}

      <div className="flex gap-1.5">
        <Input
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="Label, e.g. web"
          className="w-[140px] text-[13px]"
        />
        <Input
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          placeholder="owner/repo or https://github.com/owner/repo"
          className="flex-1 text-[13px]"
        />
        <Button
          type="button"
          variant="outline"
          disabled={pending || !name.trim() || !url.trim()}
          onClick={handleAdd}
        >
          Add
        </Button>
      </div>
    </div>
  );
}
