# NovelReader HarmonyOS

NovelReader 的 HarmonyOS 版本，基于 ArkTS 与 ArkUI 开发，功能与界面参考 Android 版本进行适配。

- 当前版本：`1.0.0`
- Bundle Name：`com.wjnocal.novelreader`
- 支持设备：HarmonyOS 手机、平板
- Android 版本：[wjnocal/NovelReader](https://github.com/wjnocal/NovelReader)

## 功能

- 本地导入 TXT、EPUB 小说
- 自动解析章节并记录阅读进度
- 滚动阅读与滑动翻页阅读
- 字号、行距、页边距及阅读主题设置
- 目录、书签、笔记和文本标记
- 书架网格/列表展示、搜索、排序、分类、置顶和改名
- 阅读时长、连续阅读天数及每日阅读目标统计
- 在线搜书、下载并加入书架
- WebDAV 双向同步书籍、进度、书签和笔记
- 本地数据备份与恢复
- 手机、平板及横屏布局适配

## 开发环境

- DevEco Studio `6.1.1`
- HarmonyOS SDK `6.1.1 (API 24)`
- 最低兼容版本 `6.1.0 (API 23)`
- ArkTS / ArkUI

## 项目结构

```text
NovelReader/
├─ AppScope/
│  └─ app.json5                      # 应用信息与版本号
├─ entry/src/main/
│  ├─ ets/
│  │  ├─ data/                       # 本地存储、备份、在线书源和 WebDAV
│  │  ├─ entryability/               # 应用入口
│  │  ├─ model/                      # 数据模型
│  │  ├─ pages/                      # 书架、主页和阅读器界面
│  │  └─ parser/                     # TXT、EPUB 解析和导入
│  ├─ resources/base/                # 字符串、图片等资源
│  └─ resources/rawfile/             # 在线书源配置
├─ build-profile.json5
└─ oh-package.json5
```

## 运行项目

1. 使用 DevEco Studio 打开项目目录。
2. 等待工程同步及依赖初始化完成。
3. 在项目结构的“签名配置”中选择或生成自己的调试签名。
4. 连接 HarmonyOS 手机、平板或模拟器。
5. 运行 `entry` 模块。

首次运行后可从主页导入本地 TXT/EPUB，或使用在线搜书功能添加小说。

## WebDAV 同步

在“主页 → WebDAV 同步”中填写服务器地址、用户名和密码，测试连接成功后即可执行双向同步。

同步目录及数据格式与 Android 版本保持兼容，默认使用：

```text
NovelReaderSync/manifest.json
```

建议首次同步前备份本地数据，并避免两台设备同时修改同一本书的阅读数据。

## 在线搜书

在线搜书的规则实现参考 [freeok/so-novel](https://github.com/freeok/so-novel)。书源可能因目标网站结构、访问限制或网络环境变化而失效。

应用需要以下网络权限：

```text
ohos.permission.INTERNET
```

## 数据说明

书籍解析结果、阅读进度、书签、笔记和设置保存在应用沙箱中。卸载应用可能清除这些数据，请提前使用备份或 WebDAV 同步功能保存。

## 说明

本项目用于 NovelReader 的 HarmonyOS 适配与学习交流。在线内容的获取和使用应遵守相关网站规则及当地法律法规。
