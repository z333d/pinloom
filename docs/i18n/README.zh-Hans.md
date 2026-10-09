# Pinloom

把图片、便签和待办挂在工作界面旁边，方便随时对照。适用于 macOS 14 及以上，支持 Apple silicon 和 Intel。

[English](../../README.md) · [Español](README.es.md)

![Pinloom 的挂绳和便签](../images/preview.png)

## 使用

点击菜单栏的图钉图标，打开或收起挂绳；右键打开菜单。打开后会保持显示，包括其他应用的全屏界面，直到你主动收起。移动鼠标到屏幕顶部不会自动唤出。

- **粘贴图片**：从剪贴板添加图片。
- **添加图片…**：选择图片文件，也可以拖到挂绳或菜单栏图标上。
- **新建便签**：编辑正文、添加可勾选的待办，内容保存在本地。
- 拖动图片或便签的夹子来移动；拖动右下角来调整大小。位置和尺寸都会保存。
- 选中便签文字后按 **⌘C** 复制；顶部的复制按钮可复制整张便签，包括待办和完成状态。
- 单击图片复制，双击查看可缩放的预览，长按进入系统标注编辑。
- 将图片固定成独立参考窗口，方便对照。参考窗口使用自己的副本，移动原文件后仍可查看。
- 收起挂绳不会删除内容。移除图片会保留原文件；只有明确选择「移到废纸篓」才会删除原文件。

「整理」包含恢复位置和取下图片；「选项」包含声音和开机启动。恢复便签、参考图开关按需出现。手动添加的图片会一直保留，数量较多时可横向滚动。

应用不监听截图目录、不接管系统截图、不注册全局快捷键。继续使用习惯的截图工具，需要时再把图片添加进来。当前尚不支持视频。

## 大小范围

图片保持原比例，默认适配 136×104 逻辑点的区域，可调为默认的 0.65～3 倍，另加边框。便签默认 240×220，可调宽度 200～480、高度 160～600，也会受屏幕可用空间限制。

## 构建和安装

```sh
git clone https://github.com/z333d/pinloom.git
cd pinloom
swift test
swift scripts/check-strings.swift
SIGN_IDENTITY=- scripts/build-app.sh release
open build/Pinloom.app
```

把 `build/Pinloom.app` 拖入「应用程序」即可日常使用。`scripts/make-dmg.sh` 可生成安装磁盘映像。GitHub [Actions](https://github.com/z333d/pinloom/actions) 也会生成应用 ZIP 构建产物。

本地与 CI 构建默认使用临时签名，尚未通过 Apple 公证。脚本不会自动从钥匙串选择 Developer ID；正式签名需要明确指定自己的证书，仓库不包含签名凭据。

## 从早期本地版本迁移

Pinloom 使用独立的应用标识 `io.github.z333d.pinloom` 和数据目录。首次打开时，会从之前使用 `app.tendedero.Tendedero` 的本地版本复制图片、便签、尺寸位置和参考图副本，原数据保留。不会覆盖已经存在的 Pinloom 数据；文件复制失败时，下次启动会重试。

如果旧版仍在接管截图，会按保存的记录恢复截图设置一次。Pinloom 不会开启该模式。请先退出旧版，再打开 Pinloom。

## 来源

由 [z333d](https://github.com/z333d) 独立维护，基于 Alejandro Buján 的 [Tendedero](https://github.com/alejandrobujan/tendedero) MIT 授权源码开发。保留原版权与许可声明，使用自己的名称、图标和文档图片，与原作者不存在官方背书关系。详见 [LICENSE](../../LICENSE) 和 [NOTICE](../../NOTICE)。
