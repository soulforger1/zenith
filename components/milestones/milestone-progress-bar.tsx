export function MilestoneProgressBar({ closed, total }: { closed: number; total: number }) {
  const pct = total === 0 ? 0 : Math.round((closed / total) * 100);

  return (
    <div className="flex items-center gap-2">
      <div className="h-1.5 w-full max-w-40 overflow-hidden rounded-full bg-muted">
        <div className="h-full rounded-full bg-primary" style={{ width: `${pct}%` }} />
      </div>
      <span className="font-mono text-xs whitespace-nowrap text-muted-foreground">
        {closed}/{total}
      </span>
    </div>
  );
}
