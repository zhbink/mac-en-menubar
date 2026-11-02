# Gloss

菜单栏里的英语纠正。按快捷键截下题目和你的回答，交给 DeepSeek 看图：英文回答检查语法和地不地道，中文回答给出保留原意的地道英文。记录留在本机，方便复习。

## 运行

需要 macOS 14 和 Swift 命令行工具。

```sh
scripts/build-app.sh
open dist/EnTrans.app
```

第一次打开后，菜单栏会出现一本书的图标。

1. 点图标，打开「设置」，填入 DeepSeek API Key。Key 写进钥匙串，不会进仓库。
2. 系统询问屏幕录制时选允许。如果截图失败，到 系统设置 → 隐私与安全性 → 录屏与系统录音 里打开 Gloss。本机用「EnTrans Local」证书签名时，重新打包不会丢掉这项权限。
3. 默认快捷键是 `⌃⌥E`。拖一块区域框住题目和回答，或按空格再点一个窗口。Esc 取消。看完后，结果从菜单栏图标下面展开。
4. 更早的记录在「纠正本」里，可以按错误类型复习，也可以把中文回答和推荐英文对照着看。

整屏模式在设置里。画面太大时模型会把图缩小，小字可能认错，练习时用框选。

数据在 `~/Library/Application Support/EnTrans/`：`reviews.json` 和 `shots/`。

## 开发

```sh
swift run EnTransCheck
```

这台机器只有命令行工具，没有 Xcode 自带的 XCTest，所以检查程序是 `EnTransCheck`。

`open dist/EnTrans.app --args --show-samples` 会用 `/tmp/entrans-preview` 打开纠正本并载入两条示例，不写你的正式记录。
