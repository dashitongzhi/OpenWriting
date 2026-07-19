import {Composition} from "remotion";
import {OpenWritingPromo} from "./OpenWritingPromo";

export const MyComposition: React.FC = () => {
  return (
    <>
      <Composition
        id="OpenWritingPromo"
        component={OpenWritingPromo}
        durationInFrames={2040}
        fps={30}
        width={1920}
        height={1080}
      />
      <Composition
        id="OpenWritingPromoManbo"
        component={OpenWritingPromo}
        durationInFrames={2040}
        fps={30}
        width={1920}
        height={1080}
        defaultProps={{
          backgroundMusic: "audio/manbo/manbo-bed.mp3",
          backgroundMusicVolume: 0.3,
        }}
      />
    </>
  );
};
