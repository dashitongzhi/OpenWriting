import {Easing, interpolate, useCurrentFrame} from "remotion";
import {colors, fonts} from "../theme";
import {SceneFrame} from "./SceneFrame";

type ReviewSceneProps = {duration: number};

export const ReviewScene: React.FC<ReviewSceneProps> = ({duration}) => {
  const frame = useCurrentFrame();
  const laws = ["大纲是法律", "设定是物理", "新发明必须登记"];
  const review = ["连续性", "角色一致", "节奏", "读下去的力量", "AI 痕迹"];

  return (
    <SceneFrame duration={duration} background={colors.inkSoft}>
      <div
        style={{
          flex: 1,
          padding: "104px 118px 160px",
          display: "grid",
          gridTemplateColumns: "1fr 1px 1fr",
          gap: 82,
          alignItems: "center",
        }}
      >
        <div>
          <div
            style={{
              fontFamily: fonts.serif,
              fontSize: 78,
              letterSpacing: -3,
              lineHeight: 1.12,
              marginBottom: 46,
              opacity: interpolate(frame, [12, 42], [0, 1], {
                extrapolateLeft: "clamp",
                extrapolateRight: "clamp",
                easing: Easing.bezier(0.16, 1, 0.3, 1),
              }),
            }}
          >
            写前有门禁。
          </div>
          {laws.map((law, index) => {
            const start = 40 + index * 18;
            return (
              <div
                key={law}
                style={{
                  padding: "20px 0",
                  borderBottom: `1px solid ${colors.line}`,
                  fontFamily: fonts.sans,
                  fontSize: 36,
                  color: index === 0 ? colors.accent : colors.paperSoft,
                  opacity: interpolate(frame, [start, start + 20], [0, 1], {
                    extrapolateLeft: "clamp",
                    extrapolateRight: "clamp",
                  }),
                }}
              >
                {law}
              </div>
            );
          })}
        </div>
        <div
          style={{
            width: 1,
            height: interpolate(frame, [18, 64], [0, 600], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
              easing: Easing.bezier(0.16, 1, 0.3, 1),
            }),
            background: colors.line,
          }}
        />
        <div>
          <div style={{display: "flex", alignItems: "baseline", gap: 24, marginBottom: 34}}>
            <div
              style={{
                fontFamily: fonts.serif,
                fontSize: 164,
                lineHeight: 0.9,
                color: colors.accent,
                opacity: interpolate(frame, [12, 42], [0, 1], {
                  extrapolateLeft: "clamp",
                  extrapolateRight: "clamp",
                }),
              }}
            >
              9
            </div>
            <div style={{fontFamily: fonts.serif, fontSize: 65, lineHeight: 1.1}}>
              维质量审查
            </div>
          </div>
          <div style={{display: "flex", flexWrap: "wrap", gap: 14}}>
            {review.map((item, index) => {
              const start = 70 + index * 10;
              return (
                <div
                  key={item}
                  style={{
                    padding: "14px 0",
                    marginRight: 26,
                    fontFamily: fonts.sans,
                    fontSize: 31,
                    color: colors.textMuted,
                    opacity: interpolate(frame, [start, start + 18], [0, 1], {
                      extrapolateLeft: "clamp",
                      extrapolateRight: "clamp",
                    }),
                  }}
                >
                  {item}
                </div>
              );
            })}
          </div>
          <div
            style={{
              marginTop: 50,
              fontFamily: fonts.sans,
              fontSize: 34,
              lineHeight: 1.5,
              color: colors.paperSoft,
              maxWidth: 650,
            }}
          >
            把“感觉不对”，变成可以处理的问题。
          </div>
        </div>
      </div>
    </SceneFrame>
  );
};
