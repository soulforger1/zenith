import Link from "next/link";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

export function SpaceCard({
  name,
  slug,
  description,
  openCount,
  totalCount,
}: {
  name: string;
  slug: string;
  description?: string | null;
  openCount: number;
  totalCount: number;
}) {
  return (
    <Link href={`/spaces/${slug}`}>
      <Card className="h-full transition-colors hover:border-primary/40 hover:bg-accent/40">
        <CardHeader>
          <CardTitle>{name}</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          {description ? (
            <p className="line-clamp-2 text-sm text-muted-foreground">
              {description}
            </p>
          ) : null}
          <p className="font-mono text-xs text-muted-foreground">
            {openCount} open · {totalCount} total
          </p>
        </CardContent>
      </Card>
    </Link>
  );
}
