# NoType Product Blueprint

## One-line positioning

NoType 是一个基于 macOS 原生听写体验之上的全局语音输入增强器。

## Why it should exist

系统听写已经足够快。  
NoType 必须提供系统听写没有直接提供的能力：

- 说完自动整理
- 说完自动翻译
- 全局热键和模式切换
- 统一的轻量菜单栏交互

## User promise

用户按下热键后的感觉应该是：

1. 立即开始
2. 不需要学习复杂操作
3. 文字很快出现
4. 说完后句子更自然
5. 需要翻译时直接输出目标语言

## Core UX

### Direct Dictation

- 开始快
- 出字快
- 结束自动整理

### Translate Dictation

- 允许略慢于 direct mode
- 但要保证最终结果准确、自然、可直接发送

## Success metrics

- direct mode 启动延迟接近系统听写
- direct mode 整理后文本不改变原意
- translation mode 结果可以直接发送，不需要再手改
- 菜单栏 app 长时间常驻稳定
