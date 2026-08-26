import { createSpaceAction } from "@/lib/actions/spaces";
import { SpaceForm } from "@/components/spaces/space-form";

export default function NewSpacePage() {
  return (
    <div className="space-y-6 p-8">
      <h2 className="text-xl font-semibold">New space</h2>
      <SpaceForm action={createSpaceAction} />
    </div>
  );
}
