# MacRelay Project Rules

## Mac APP 启动规则（CRITICAL）

**禁止**直接启动 `.build/debug/AgentClientMacShell` 裸可执行文件。

裸启动会导致：
- macOS IME 候选窗出现在屏幕左下角
- marked text 无法提交
- 输入法相关各种诡异问题

**必须**使用以下命令构建并启动：
```bash
bash scripts/build-mac-shell-app.sh --launch
```

确认运行路径为：
```
.build/AgentClientMacShell.app/Contents/MacOS/AgentClientMacShell
```

## IME 防护

保留 `PlainComposerTextEditor.updateNSView()` 中的 `hasMarkedText()` 防护。
IME 组合期间不能写入 `textView.string`。
