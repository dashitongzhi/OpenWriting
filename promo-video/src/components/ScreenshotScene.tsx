import {Easing, Img, interpolate, staticFile, useCurrentFrame} from "remotion";
import {colors, fonts} from "../theme";
import {SceneFrame} from "./SceneFrame";

type ScreenshotSceneProps = {
  duration: number;
  image: string;
  title: string;
  body: string;
  align?: "left" | "right";
  detail?: string;
};

export const ScreenshotScene: React.FC<ScreenshotSceneProps> = ({
  duration,
  image,
  title,
  body,
  align = "right",
  detail,
}) => {
  const frame = useCurrentFrame();
  const screenshotFirst = align === "left";

  const copy = (
    <div
      style={{
        width: 520,
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        gap: 28,
        opacity: interpolate(frame, [16, 48], [0, 1], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
          easing: Easing.bezier(0.16, 1, 0.3, 1),
        }),
        translate: interpolate(
          frame,
          [10, 54],
          [screenshotFirst ? "36px 0px" : "-36px 0px", "0px 0px"],
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
          width: 64,
          height: 5,
          borderRadius: 999,
          background: colors.accent,
        }}
      />
      <div
        style={{
          fontFamily: fonts.serif,
          fontSize: 76,
          lineHeight: 1.12,
          letterSpacing: -3,
          maxWidth: 520,
        }}
      >
        {title}
      </div>
      <div
        style={{
          fontFamily: fonts.sans,
          fontSize: 34,
          lineHeight: 1.55,
          color: colors.textMuted,
          maxWidth: 500,
        }}
      >
        {body}
      </div>
      {detail ? (
        <div
          style={{
            paddingTop: 18,
            borderTop: `1px solid ${colors.line}`,
            fontFamily: fonts.sans,
            fontSize: 25,
            lineHeight: 1.5,
            color: colors.paperSoft,
          }}
        >
          {detail}
        </div>
      ) : null}
    </div>
  );

  const screenshot = (
    <div
      style={{
        width: 1120,
        height: 660,
        borderRadius: 34,
        overflow: "hidden",
        border: "1px solid rgba(255,255,255,0.2)",
        boxShadow: "0 42px 110px rgba(0,0,0,0.44)",
        background: colors.paper,
        scale: interpolate(frame, [0, duration], [0.94, 1.015], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
        }),
        translate: interpolate(
          frame,
          [0, duration],
          [screenshotFirst ? "-28px 12px" : "28px 12px", "0px -8px"],
          {extrapolateLeft: "clamp", extrapolateRight: "clamp"},
        ),
      }}
    >
      <Img
        src={staticFile(image)}
        style={{
          width: "100%",
          height: "100%",
          objectFit: "cover",
        }}
      />
    </div>
  );

  return (
    <SceneFrame duration={duration}>
      <div
        style={{
          flex: 1,
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          gap: 92,
          padding: "96px 104px 150px",
        }}
      >
        {screenshotFirst ? screenshot : copy}
        {screenshotFirst ? copy : screenshot}
      </div>
    </SceneFrame>
  );
};
