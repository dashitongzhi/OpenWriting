import {readFile, writeFile} from "node:fs/promises";
import {resolve} from "node:path";

const root = resolve(import.meta.dirname, "..");
const source = resolve(root, process.argv[2] ?? "public/audio/voiceover.vtt");
const target = resolve(root, process.argv[3] ?? "public/audio/captions.json");

const toMs = (timestamp) => {
  const [hours, minutes, rest] = timestamp.split(":");
  const [seconds, millis] = rest.split(/[.,]/);
  return (
    Number(hours) * 3_600_000 +
    Number(minutes) * 60_000 +
    Number(seconds) * 1_000 +
    Number(millis)
  );
};

const text = await readFile(source, "utf8");
const lines = text.replaceAll("\r", "").split("\n");
const captions = [];

for (let index = 0; index < lines.length; index += 1) {
  const match = lines[index].match(
    /^(\d{2}:\d{2}:\d{2}[.,]\d{3}) --> (\d{2}:\d{2}:\d{2}[.,]\d{3})$/,
  );
  if (!match) continue;

  const content = [];
  index += 1;
  while (index < lines.length && lines[index].trim() !== "") {
    content.push(lines[index].trim());
    index += 1;
  }

  captions.push({
    text: content.join(" "),
    startMs: toMs(match[1]),
    endMs: toMs(match[2]),
    timestampMs: null,
    confidence: null,
  });
}

await writeFile(target, `${JSON.stringify(captions, null, 2)}\n`, "utf8");
console.log(`Wrote ${captions.length} captions to ${target}`);
