# NoType

NoType is a native macOS voice input app built for people who want the speed of macOS dictation, but with a better final result.

It feels like system dictation when you start speaking:
- fast response
- native macOS experience
- menu bar utility
- lightweight and always ready

It goes further after you finish:
- rewrites messy spoken phrases into cleaner sentences
- supports direct Chinese input and direct English input
- supports Chinese to English and English to Chinese translation input
- works offline as much as macOS allows
- free to use

---

## 中文介绍

NoType 不是“又一个语音输入工具”。

它的目标很明确：

- 像 macOS 原生听写一样快
- 像系统工具一样轻
- 识别和输入过程尽量原生
- 说完以后自动把口语整理成通顺句子
- 一键切换中文、英文、中转英、英转中
- 菜单栏常驻，随时可用
- 尽量离线工作
- 免费使用

如果你已经习惯了 macOS 自带听写，但又觉得它只能“原样打字”、不会整理语句、不能直接做中英互译，那么 NoType 才有存在的意义。

### 适合谁

- 想要全局语音输入的人
- 经常写微信、邮件、笔记、聊天消息的人
- 希望“边说边出字，结束后自动润色”的人
- 想要中英双语输入和互译的人
- 不想长期订阅 Typeless、TypeOff 这类收费工具的人

### 核心卖点

- `macOS 原生感`
  尽量复用系统能力，响应快，体验像系统自带程序。

- `边说边出字`
  输入过程强调实时反馈，不是录完再慢慢转文字。

- `自动整理语句`
  说话里的“那个、嗯、然后、呃”等口语赘词，会在结束后尽量整理成更自然的句子。

- `中英双语 + 中英互译`
  既能直接中文输入、直接英文输入，也能中文说完直接变英文、英文说完直接变中文。

- `轻量、免费、离线优先`
  没有复杂臃肿的界面，不靠重型云端工作流，日常使用更接近一个原生菜单栏工具。

### 为什么比纯系统听写更有价值

macOS 自带听写已经很好用，但它主要解决的是“把你说的话打出来”。

NoType 想解决的是：

1. 说的时候，保持接近系统听写的速度和流畅度  
2. 说完以后，把口语整理成更适合发送和记录的句子  
3. 直接完成中英互译输入  
4. 用一个快捷键完成整套工作流  

### 和 Typeless / TypeOff 这类工具相比

NoType 的定位不是做一个复杂的 AI 写作平台，而是做一个更像系统原生功能的小工具：

- 更轻
- 更直接
- 更接近 macOS 原生体验
- 更适合全局输入场景
- 免费使用

如果你要的是“打开就说、马上出字、结束自动整理、还能翻译”，NoType 的方向会比重型订阅工具更克制，也更高频。

---

## English

NoType is a native-feeling macOS voice input app for users who want more than plain dictation.

It is designed to be:
- as fast as macOS dictation
- small and always available from the menu bar
- fluent during live input
- smarter after you stop speaking

### What makes NoType different

Most dictation tools stop at transcription.

NoType is built around a better end-to-end workflow:

1. Start speaking and see text appear immediately
2. Finish speaking
3. Let NoType clean up filler words and awkward spoken phrasing
4. Output a more natural final sentence

### Features

- Direct Chinese voice input
- Direct English voice input
- Chinese-to-English voice translation
- English-to-Chinese voice translation
- Sentence cleanup after dictation
- Native macOS menu bar app
- Fast hotkey-driven workflow
- Offline-first experience
- Free to use

### Why people may prefer it

Compared with plain system dictation, NoType aims to give you:
- cleaner final text
- built-in bilingual translation
- faster mode switching
- a simpler workflow for real-world messaging and note taking

Compared with paid AI dictation tools such as Typeless or TypeOff, NoType is intentionally:
- lighter
- more native to macOS
- more focused on global voice input
- free

---

## Mode Flow

Default hotkey:

```text
Control + Option + Space
```

Mode rotation:

```text
Direct Chinese -> Direct English -> Chinese to English -> English to Chinese
```

After each completed session, NoType advances to the next mode automatically.

---

## Install

Recommended:

1. Open [NoType.dmg](dist/NoType.dmg)
2. Drag `NoType.app` into `Applications`
3. Launch `/Applications/NoType.app`

On first launch, macOS may ask for:
- Microphone
- Speech Recognition
- Accessibility
- Automation

Grant permissions to the installed app in `Applications`, not to temporary build copies.

---

## Build

```bash
swift build
./scripts/build_dmg.sh
./scripts/build_installer.sh
```

Artifacts:

```text
dist/NoType.dmg
dist/NoType-Installer.pkg
```

`NoType.dmg` is the recommended distribution format.  
`NoType-Installer.pkg` may require administrator approval during installation.

---

## Status

NoType is focused on one thing:

`native-feeling global voice input on macOS, with cleanup and translation built in.`
