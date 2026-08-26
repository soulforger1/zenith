// Fractional-index helpers for drag-and-drop ordering: inserting between two
// existing items only ever touches the moved row (never renumbers a whole
// column), at the cost of position values that can theoretically converge
// over many repeated inserts in the same spot — a non-issue at solo-user
// scale, and cheap to fix later with a one-off "renormalize" pass if needed.
const GAP = 1000;

export function positionAtEnd(maxPosition: number | null): number {
  return maxPosition === null ? GAP : maxPosition + GAP;
}

export function positionBetween(before: number | null, after: number | null): number {
  if (before === null && after === null) return GAP;
  if (before === null) return after! - GAP / 2;
  if (after === null) return before + GAP;
  return (before + after) / 2;
}
