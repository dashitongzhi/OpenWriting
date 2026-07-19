import {Easing, Img, interpolate, staticFile, useCurrentFrame} from "remotion";
import {colors, fonts} from "../theme";
import {SceneFrame} from "./SceneFrame";

const memoryKinds = [
  "世界规则",
  "人物状态",
  "关系变化",
  "剧情事实",
  "未解伏笔",
  "读者承诺",
  "时间线",
];

type MemorySceneProps = {duration: number};

export const MemoryScene: React.FC<MemorySceneProps> = ({duration}) => {
  const frame = useCurrentFrame();

  return (
    <SceneFrame duration={duration}>
      <Img
        src={staticFile("generated/story-memory.png")}
        style={{
          width: "100%",
          height: "100%",
          objectFit: "cover",
          scale: interpolate(frame, [0, duration], [1.02, 1.085], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          }),
          translate: interpolate(frame, [0, duration], ["-18px 8px", "14px -12px"], {
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
            "linear-gradient(90deg, rgba(7,11,16,0.12) 0%, rgba(7,11,16,0.25) 50%, rgba(7,11,16,0.94) 78%, rgba(7,11,16,0.98) 100%)",
        }}
      />
      <div
        style={{
          position: "absolute",
          right: 112,
          top: 108,
          width: 620,
          display: "flex",
          flexDirection: "column",
          gap: 24,
        }}
      >
        <div
          style={{
            fontFamily: fonts.serif,
            fontSize: 76,
            lineHeight: 1.12,
            letterSpacing: -3,
            opacity: interpolate(frame, [14, 46], [0, 1], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
              easing: Easing.bezier(0.16, 1, 0.3, 1),
            }),
          }}
        >
          七类记忆，
          <br />
          不让故事失忆。
        </div>
        <div style={{display: "grid", gridTemplateColumns: "1fr 1fr", gap: "0 34px"}}>
          {memoryKinds.map((kind, index) => {
            const start = 48 + index * 15;
            return (
              <div
                key={kind}
                style={{
                  padding: "18px 0",
                  borderBottom: `1px solid ${colors.line}`,
                  fontFamily: fonts.sans,
                  fontSize: 30,
                  color: index === 4 ? colors.accent : colors.paperSoft,
                  opacity: interpolate(frame, [start, start + 22], [0, 1], {
                    extrapolateLeft: "clamp",
                    extrapolateRight: "clamp",
                    easing: Easing.bezier(0.16, 1, 0.3, 1),
                  }),
                  translate: interpolate(frame, [start, start + 22], ["20px 0px", "0px 0px"], {
                    extrapolateLeft: "clamp",
                    extrapolateRight: "clamp",
                    easing: Easing.bezier(0.16, 1, 0.3, 1),
                  }),
                }}
              >
                {kind}
              </div>
            );
          })}
        </div>
      </div>
    </SceneFrame>
  );
};
