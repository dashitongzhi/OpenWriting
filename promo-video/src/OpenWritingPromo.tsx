import {Audio} from "@remotion/media";
import {AbsoluteFill, Sequence, staticFile} from "remotion";
import {MemoryScene} from "./components/MemoryScene";
import {OpeningScene} from "./components/OpeningScene";
import {OutroScene} from "./components/OutroScene";
import {ReviewScene} from "./components/ReviewScene";
import {ScreenshotScene} from "./components/ScreenshotScene";
import {SubtitleOverlay} from "./components/SubtitleOverlay";
import {colors} from "./theme";

type OpenWritingPromoProps = {
  backgroundMusic?: string;
  backgroundMusicVolume?: number;
};

export const OpenWritingPromo: React.FC<OpenWritingPromoProps> = ({
  backgroundMusic,
  backgroundMusicVolume = 0.3,
}) => {
  return (
    <AbsoluteFill style={{background: colors.ink}}>
      <Sequence durationInFrames={270}>
        <OpeningScene duration={270} />
      </Sequence>

      <Sequence from={240} durationInFrames={280}>
        <ScreenshotScene
          duration={280}
          image="screenshots/home.png"
          title="一个原生的长篇写作空间"
          body="大纲、正文、设定、项目状态与 AI 协作，在同一个 macOS 工作台持续推进。"
          detail="真实 OpenWriting 首页"
        />
      </Sequence>

      <Sequence from={470} durationInFrames={345}>
        <MemoryScene duration={345} />
      </Sequence>

      <Sequence from={760} durationInFrames={240}>
        <ScreenshotScene
          duration={240}
          image="screenshots/writing-desk.png"
          title="写作，仍然是主角"
          body="大纲生成、参考文本与正文编辑在同一条创作链路里协同，但不会抢走作者的注意力。"
          align="left"
        />
      </Sequence>

      <Sequence from={930} durationInFrames={230}>
        <ReviewScene duration={230} />
      </Sequence>

      <Sequence from={1090} durationInFrames={310}>
        <ScreenshotScene
          duration={310}
          image="screenshots/chapter-tree.png"
          title="让结构长期可见"
          body="章节推进、角色弧线、伏笔回收与三线节奏，都有持续维护的位置。"
          detail="Quest 60% / Fire 20% / Constellation 20%"
        />
      </Sequence>

      <Sequence from={1310} durationInFrames={380}>
        <ScreenshotScene
          duration={380}
          image="screenshots/skill-market.png"
          title="把方法放进创作链路"
          body="题材模板、参考资料与 Writing Skill 可以参与续写、修订、大纲生成和质量审查。"
          align="left"
          detail="支持 Apple ID 与 iCloud 私密项目同步"
        />
      </Sequence>

      <Sequence from={1620} durationInFrames={420}>
        <OutroScene duration={420} />
      </Sequence>

      <Audio src={staticFile("audio/voiceover.mp3")} volume={1} />
      {backgroundMusic ? (
        <Audio src={staticFile(backgroundMusic)} volume={backgroundMusicVolume} />
      ) : null}
      <SubtitleOverlay />
    </AbsoluteFill>
  );
};
