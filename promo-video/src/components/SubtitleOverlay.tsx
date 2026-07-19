import type {Caption} from "@remotion/captions";
import {Easing, interpolate, useCurrentFrame, useVideoConfig} from "remotion";
import captionsJson from "../../public/audio/captions.json";
import {colors, fonts} from "../theme";

const captions = captionsJson as Caption[];

export const SubtitleOverlay: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const timeMs = (frame / fps) * 1000;
  const caption = captions.find((item) => timeMs >= item.startMs && timeMs <= item.endMs);

  if (!caption) return null;

  const startFrame = (caption.startMs / 1000) * fps;
  const endFrame = (caption.endMs / 1000) * fps;

  return (
    <div
      style={{
        position: "absolute",
        left: 140,
        right: 140,
        bottom: 42,
        display: "flex",
        justifyContent: "center",
        pointerEvents: "none",
        opacity: interpolate(
          frame,
          [startFrame, startFrame + 7, endFrame - 6, endFrame],
          [0, 1, 1, 0],
          {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          },
        ),
      }}
    >
      <div
        style={{
          maxWidth: 1480,
          padding: "15px 28px 17px",
          borderRadius: 18,
          border: "1px solid rgba(255,255,255,0.14)",
          background: "rgba(8, 12, 18, 0.78)",
          color: colors.text,
          fontFamily: fonts.sans,
          fontSize: 31,
          lineHeight: 1.45,
          textAlign: "center",
          textShadow: "0 2px 8px rgba(0,0,0,0.6)",
        }}
      >
        {caption.text}
      </div>
    </div>
  );
};

