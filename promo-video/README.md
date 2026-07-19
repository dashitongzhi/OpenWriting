# OpenWriting Remotion 宣传片

本目录包含 OpenWriting 的 68 秒中文宣传片工程。画面使用实际 OpenWriting Debug 构建截图，并以生成图补充写作氛围和结构化记忆表达。

## 安装与预览

```bash
npm install
npm run dev
```

生成静帧预览：

```bash
npm run still
```

## 旁白与字幕

旁白文本位于 `voiceover.txt`。重新生成旁白、VTT 和 Remotion 字幕数据：

```bash
npm run voiceover
```

TTS 使用 Microsoft Edge 在线神经语音服务：

- Voice：`zh-CN-XiaoxiaoNeural`
- Rate：`+4%`
- Pitch：`-2Hz`

## 视频版本

无背景节奏的原版：

```bash
npm run render
```

输出：`out/OpenWriting-Promo.mp4`

带 CC0 曼波节奏床的新版：

```bash
npm run manbo-track
npm run render:manbo
```

输出：`out/OpenWriting-Promo-Manbo.mp4`

曼波节奏使用 VCSL 的 conga、quinto、bongo、cowbell、claves 和 shaker 单击采样重新编排，不包含从抖音或其他短视频平台提取的音频。素材及许可证说明见 `public/audio/manbo/README.md`。

## 素材目录

- `public/screenshots/`：OpenWriting 实际应用截图
- `public/generated/`：辅助叙事的生成图片
- `public/audio/`：中文旁白、字幕及曼波节奏床
- `public/branding/`：应用图标

## 验证

```bash
npm run lint
ffmpeg -v error -i out/OpenWriting-Promo-Manbo.mp4 -f null -
```
