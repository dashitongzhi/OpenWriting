import {mkdirSync} from "node:fs";
import {resolve} from "node:path";
import {spawnSync} from "node:child_process";

const root = resolve(import.meta.dirname, "..");
const sampleRoot = resolve(root, "public/audio/manbo/samples");
const outputRoot = resolve(root, "public/audio/manbo");
const tempRoot = resolve(root, "out");

mkdirSync(outputRoot, {recursive: true});
mkdirSync(tempRoot, {recursive: true});

const sources = [
  {
    file: "conga.wav",
    events: [
      [0.75, 0.74],
      [1.0, 0.58],
      [1.75, 0.82],
      [2.75, 0.74],
      [3.0, 0.58],
      [3.75, 0.86],
    ],
  },
  {
    file: "quinto.wav",
    events: [
      [0.5, 0.48],
      [1.5, 0.62],
      [2.5, 0.5],
      [3.5, 0.66],
    ],
  },
  {
    file: "bongo-high.wav",
    events: [
      [0.25, 0.38],
      [1.25, 0.42],
      [1.5, 0.46],
      [2.25, 0.4],
      [3.25, 0.44],
      [3.5, 0.5],
    ],
  },
  {
    file: "bongo-low.wav",
    events: [
      [0.0, 0.42],
      [1.0, 0.48],
      [2.0, 0.44],
      [3.0, 0.52],
    ],
  },
  {
    file: "cowbell.wav",
    events: Array.from({length: 8}, (_, index) => [index * 0.5, index % 2 === 0 ? 0.19 : 0.13]),
  },
  {
    file: "claves.wav",
    events: [
      [0.0, 0.38],
      [0.75, 0.38],
      [1.5, 0.4],
      [2.5, 0.38],
      [3.0, 0.4],
    ],
  },
  {
    file: "shaker-up.wav",
    events: Array.from({length: 8}, (_, index) => [index * 0.5 + 0.25, 0.22]),
  },
  {
    file: "shaker-down.wav",
    events: Array.from({length: 8}, (_, index) => [index * 0.5, 0.18]),
  },
];

const inputArgs = sources.flatMap(({file}) => ["-i", resolve(sampleRoot, file)]);
const filters = [];
const mixLabels = [];
let eventIndex = 0;

sources.forEach(({events}, sourceIndex) => {
  const splitLabels = events.map((_, index) => `s${sourceIndex}_${index}`);
  filters.push(`[${sourceIndex}:a]aformat=sample_rates=48000:sample_fmts=fltp:channel_layouts=stereo,asplit=${events.length}${splitLabels.map((label) => `[${label}]`).join("")}`);

  events.forEach(([time, gain], index) => {
    const output = `event${eventIndex++}`;
    const delay = Math.round(time * 1000);
    filters.push(`[${splitLabels[index]}]atrim=start=0:end=0.7,volume=${gain},adelay=${delay}|${delay}[${output}]`);
    mixLabels.push(`[${output}]`);
  });
});

const melody = [
  [0.0, 220.0],
  [0.5, 261.63],
  [1.25, 329.63],
  [1.5, 392.0],
  [2.0, 329.63],
  [2.75, 261.63],
  [3.0, 246.94],
  [3.5, 220.0],
];

melody.forEach(([time, frequency], index) => {
  const output = `tone${index}`;
  const delay = Math.round(time * 1000);
  filters.push(`sine=frequency=${frequency}:duration=0.22:sample_rate=48000,afade=t=out:st=0.04:d=0.18,volume=0.032,pan=stereo|c0=c0|c1=c0,adelay=${delay}|${delay}[${output}]`);
  mixLabels.push(`[${output}]`);
});

[
  [0.0, 110.0],
  [1.0, 130.81],
  [2.0, 110.0],
  [3.0, 123.47],
].forEach(([time, frequency], index) => {
  const output = `bass${index}`;
  const delay = Math.round(time * 1000);
  filters.push(`sine=frequency=${frequency}:duration=0.34:sample_rate=48000,afade=t=out:st=0.06:d=0.28,volume=0.055,pan=stereo|c0=c0|c1=c0,adelay=${delay}|${delay}[${output}]`);
  mixLabels.push(`[${output}]`);
});

filters.push(`${mixLabels.join("")}amix=inputs=${mixLabels.length}:duration=longest:normalize=0,atrim=duration=4,alimiter=limit=0.88[pattern]`);

const patternPath = resolve(tempRoot, "manbo-pattern.wav");
const patternResult = spawnSync(
  "ffmpeg",
  ["-y", "-v", "error", ...inputArgs, "-filter_complex", filters.join(";"), "-map", "[pattern]", "-c:a", "pcm_s16le", patternPath],
  {stdio: "inherit"},
);

if (patternResult.status !== 0) {
  process.exit(patternResult.status ?? 1);
}

const outputPath = resolve(outputRoot, "manbo-bed.mp3");
const renderResult = spawnSync(
  "ffmpeg",
  [
    "-y",
    "-v",
    "error",
    "-stream_loop",
    "-1",
    "-i",
    patternPath,
    "-t",
    "68",
    "-af",
    "highpass=f=65,lowpass=f=12500,acompressor=threshold=0.11:ratio=2.5:attack=5:release=90:makeup=1.35,afade=t=in:st=0:d=1.5,afade=t=out:st=65:d=3,loudnorm=I=-24:LRA=6:TP=-2",
    "-c:a",
    "libmp3lame",
    "-b:a",
    "192k",
    outputPath,
  ],
  {stdio: "inherit"},
);

if (renderResult.status !== 0) {
  process.exit(renderResult.status ?? 1);
}

console.log(`Wrote ${outputPath}`);
