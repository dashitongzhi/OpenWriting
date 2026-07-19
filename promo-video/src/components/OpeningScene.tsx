import {Easing, Img, interpolate, staticFile, useCurrentFrame} from "remotion";
import {colors, fonts} from "../theme";
import {SceneFrame} from "./SceneFrame";

type OpeningSceneProps = {duration: number};

export const OpeningScene: React.FC<OpeningSceneProps> = ({duration}) => {
  const frame = useCurrentFrame();

  return (
    <SceneFrame duration={duration}>
      <Img
        src={staticFile("generated/writer-desk.png")}
        style={{
          width: "100%",
          height: "100%",
          objectFit: "cover",
          scale: interpolate(frame, [0, duration], [1.035, 1.09], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          }),
          translate: interpolate(frame, [0, duration], ["0px 0px", "-26px -8px"], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          }),
        }}
      />
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "linear-gradient(90deg, rgba(7,12,19,0.98) 0%, rgba(7,12,19,0.82) 32%, rgba(7,12,19,0.18) 70%, rgba(7,12,19,0.22) 100%)",
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 116,
          top: 150,
          width: 980,
          opacity: interpolate(frame, [18, 58], [0, 1], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          }),
          translate: interpolate(frame, [10, 62], ["-28px 0px", "0px 0px"], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          }),
        }}
      >
        <div
          style={{
            fontFamily: fonts.sans,
            fontSize: 27,
            fontWeight: 650,
            letterSpacing: 10,
            color: colors.paperSoft,
            marginBottom: 30,
          }}
        >
          OPENWRITING
        </div>
        <div
          style={{
            fontFamily: fonts.serif,
            fontSize: 96,
            lineHeight: 1.08,
            letterSpacing: -5,
          }}
        >
          <div style={{whiteSpace: "nowrap"}}>长篇真正困难的，</div>
          <div style={{whiteSpace: "nowrap"}}>是始终记得。</div>
        </div>
        <div
          style={{
            width: 72,
            height: 6,
            borderRadius: 999,
            background: colors.accent,
            marginTop: 42,
          }}
        />
      </div>
    </SceneFrame>
  );
};
