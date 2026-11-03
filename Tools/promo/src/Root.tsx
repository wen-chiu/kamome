import { Composition } from "remotion";
import { Promo, PromoProps, promoFrames } from "./Promo";

const FPS = 30;

// Three cuts from one set of clips. AppPreview is the App Store size for 6.9"
// iPhones and must stay within 15–30 s of footage captured from the app.
const formats = [
  { id: "AppPreview", width: 886, height: 1920 },
  { id: "Social", width: 1080, height: 1920 },
  { id: "Landscape", width: 1920, height: 1080 },
] as const;

export const Root: React.FC = () => (
  <>
    {formats.map((f) => (
      <Composition
        key={f.id}
        id={f.id}
        component={Promo}
        width={f.width}
        height={f.height}
        fps={FPS}
        // Empty, because Remotion merges --props over these: a default title or
        // end card would leak into every project that leaves it out.
        defaultProps={{ clips: [] } as PromoProps}
        calculateMetadata={({ props }) => ({ durationInFrames: promoFrames(props, FPS) })}
      />
    ))}
  </>
);
