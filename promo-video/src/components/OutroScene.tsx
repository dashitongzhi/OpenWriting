import {Easing, Img, interpolate, staticFile, useCurrentFrame} from "remotion";
import {colors, fonts} from "../theme";
import {SceneFrame} from "./SceneFrame";

type OutroSceneProps = {duration: number};

export const OutroScene: React.FC<OutroSceneProps> = ({duration}) => {
  const frame = useCurrentFrame();

  return (
    <SceneFrame duration={duration} background="#10151c">
      <Img
        src={staticFile("generated/writer-desk.png")}
        style={{
          position: "absolute",
          inset: 0,
          width: "100%",
          height: "100%",
          objectFit: "cover",
          opacity: 0.25,
          filter: "grayscale(0.35) contrast(1.08)",
          scale: interpolate(frame, [0, duration], [1.08, 1.02], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          }),
        }}
      />
      <div
        style={{
          position: "absolute",
          inset: 0,
          background: "rgba(8, 13, 20, 0.72)",
        }}
      />
      <div
        style={{
          flex: 1,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          flexDirection: "column",
          gap: 30,
          paddingBottom: 70,
          opacity: interpolate(frame, [18, 58], [0, 1], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          }),
          scale: interpolate(frame, [8, 64], [0.94, 1], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          }),
        }}
      >
        <Img
          src={staticFile("branding/app-icon.png")}
          style={{
            width: 166,
            height: 166,
            borderRadius: 38,
            boxShadow: "0 28px 75px rgba(0,0,0,0.45)",
          }}
        />
        <div
          style={{
            fontFamily: fonts.sans,
            fontSize: 68,
            fontWeight: 720,
            letterSpacing: -2,
          }}
        >
          OpenWriting
        </div>
        <div
          style={{
            fontFamily: fonts.serif,
            fontSize: 62,
            lineHeight: 1.2,
            color: colors.paperSoft,
          }}
        >
          为长篇而生的专业写作系统
        </div>
        <div
          style={{
            width: interpolate(frame, [64, 116], [0, 120], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
              easing: Easing.bezier(0.16, 1, 0.3, 1),
            }),
            height: 5,
            borderRadius: 999,
            background: colors.accent,
          }}
        />
      </div>
    </SceneFrame>
  );
};

