# NoType Architecture V2

## Product core

NoType V2 只围绕一个问题设计：

为什么用户不直接用 macOS 自带听写？

答案必须是：

- NoType 保留系统听写的速度与原生感
- NoType 补上系统听写没有自动做好的“整理”
- NoType 增加系统听写本身不具备的“翻译输出”

## System split

V2 必须拆成两条独立链路。

### A. Native Dictation Path

适用于：

- `directChinese`
- `directEnglish`

目标：

- 最大化复用系统听写
- 让用户在任意输入框里获得接近系统原生的实时出字

流程：

1. 记录当前焦点输入区域。
2. 触发前台应用自己的 `编辑 > 开始听写`。
3. 系统负责实时出字。
4. NoType 在结束时抓取新增文本区间。
5. 本地模型将新增文本整理成更通顺的句子。
6. 将整理后的文本替换回新增区间。

关键点：

- NoType 不负责 direct mode 的逐字识别。
- NoType 负责 direct mode 的“后处理”和“统一工作流”。

### B. Translate Dictation Path

适用于：

- `englishToChinese`
- `chineseToEnglish`

目标：

- 用户说源语言
- 输出直接是目标语言

流程：

1. 自研语音识别引擎开始采集。
2. 得到稳定原文后执行系统翻译。
3. 对目标语言结果做简短润色。
4. 将目标语言文本写入当前焦点应用。

关键点：

- 翻译模式不强求像系统听写一样逐字出字。
- 第一优先级是准确与稳定。
- 可先做“实时预览 + 结束提交”，后续再加增量输出。

## AI layer

V2 的 AI 不该理解成“在线大模型聊天”。

它只做两种有限任务：

1. `Rewrite`
   - 口语转书面语
   - 去掉口头禅
   - 调整标点和断句

2. `Polish Translation`
   - 保持原义
   - 让目标语言更自然

约束：

- 优先走设备端能力
- 响应快
- 不引入复杂提示词系统
- 不把用户从输入流里打断

## Data contracts

### DictationSession

- mode
- captureEngine
- targetApplication
- targetElement
- startSnapshot
- endSnapshot
- rawTranscript
- translatedTranscript
- polishedTranscript

### CaptureEngine

- `systemDictation`
- `customTranscription`

### PostProcessIntent

- `rewrite`
- `rewriteAndTranslate`

## Implementation order

### Phase 1

- 稳定 direct mode 的系统听写触发
- 能识别本次新增文本范围
- 在结束后成功替换新增文本

### Phase 2

- 引入本地 rewrite 服务
- 完成 direct mode 的“说完自动整理”

### Phase 3

- 稳定 translate mode
- 支持中英互译输出

### Phase 4

- 加入自定义词表
- 提升专有词识别率
- 评估 translate mode 的增量输出

## Code reorganization target

### Current files that remain useful

- `AppModel.swift`
- `GlobalHotKeyManager.swift`
- `GlobalTextInjector.swift`
- `SystemDictationController.swift`
- `TextPipeline.swift`

### Files that should be split in the next iteration

- `AppModel.swift`
  - split into session coordinator + menu bar view model

- `SpeechRecognizerService.swift`
  - keep only custom translation capture responsibilities

- `TextPipeline.swift`
  - split into translation service + rewrite service

## Non-goals

V2 不追求这些：

- 在所有第三方应用里强行做完美的逐字回写
- 依赖未公开的 Apple Intelligence 后台接口
- 把 direct mode 和 translate mode 用一套识别引擎强行统一
