import { BoardSkeleton } from "@/components/layout/page-skeleton";

// The view type isn't known until the row loads, so this covers all three
// (Table/Board/Roadmap) with one reasonably generic column skeleton.
export default function Loading() {
  return <BoardSkeleton />;
}
