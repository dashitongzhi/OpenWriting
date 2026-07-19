import type {ReactNode} from "react";
import {AbsoluteFill, Easing, interpolate, useCurrentFrame} from "remotion";
import {colors} from "../theme";

type SceneFrameProps = {
  children: ReactNode;
  duration: number;
  background?: string;
};

export const SceneFrame: React.FC<SceneFrameProps> = ({
  children,
  duration,
  background = colors.ink,
}) => {
  const frame = useCurrentFrame();

  return (
    <AbsoluteFill
      style={{
        background,
        color: colors.text,
        opacity: interpolate(frame, [0, 24, duration - 28, duration], [0, 1, 1, 0], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
          easing: Easing.bezier(0.16, 1, 0.3, 1),
        }),
        overflow: "hidden",
      }}
    >
      {children}
      <AbsoluteFill
        style={{
          pointerEvents: "none",
          background:
            "radial-gradient(circle at 50% 42%, transparent 48%, rgba(3, 7, 12, 0.34) 100%)",
        }}
      />
    </AbsoluteFill>
  );
};

