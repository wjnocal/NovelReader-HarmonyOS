# 小说阅读器 HarmonyOS

小说阅读器（NovelReader）的 HarmonyOS 版本，基于 ArkTS 与 ArkUI 开发，功能与界面参考 Android 版本进行适配。

- 当前版本：`1.0.0`
- Bundle Name：`com.wjnocal.novelreader`
- 支持设备：HarmonyOS 手机、平板
- Android 版本：[wjnocal/NovelReader](https://github.com/wjnocal/NovelReader)

## 功能

- 本地导入 TXT、EPUB 小说
- 自动解析中英文常见章节标题，支持 EPUB 2 NCX 与 EPUB 3 Navigation 目录
- 重复导入或重复下载同名同作者书籍时更新内容，并保留书架实体和阅读进度
- 滚动阅读与滑动翻页阅读
- 字号、行距、页边距及阅读主题设置
- 目录、书签、笔记和文本标记
- 书架网格/列表展示、搜索、排序、分类、置顶和改名
- 阅读时长、连续阅读天数及每日阅读目标统计，切入后台时自动保存本次阅读
- 在线搜书、分页目录与多页正文解析，按书源限流规则下载并加入书架
- 内置小说浏览器，支持网址/关键词访问、前进后退、刷新和加载进度，可将当前章节直接切换为净化阅读模式
- 在线阅读支持书源规则匹配、通用正文识别、广告文本过滤、上下章网页跳转，以及分页/滚动、字号、行距和主题设置
- WebDAV 双向同步书籍、进度、书签、笔记与阅读统计，包含删除同步和并发冲突保护
- 本地数据备份与幂等恢复（同名书合并，书签和笔记去重）
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

也可从“主页 → 内置浏览器”访问小说站点，在具体章节页点击右下角“在线阅读”进入正文模式。在线模式不会写入书签、笔记和阅读进度；需要长期保存时请通过在线搜书下载到书架。

## WebDAV 同步

在“主页 → WebDAV 同步”中填写服务器地址、用户名和密码，测试连接成功后即可执行双向同步。

同步目录及数据格式与 Android 版本保持兼容，默认使用：

```text
NovelReaderSync/manifest.json
```

建议首次同步前备份本地数据，并避免两台设备同时修改同一本书的阅读数据。

同步清单使用 ETag 条件写入；如果发布前服务器数据已被其他设备更新，本次同步会停止并提示重试，避免静默覆盖。

## 在线搜书

在线搜书内置 25 个与 [wjnocal/NovelReader](https://github.com/wjnocal/NovelReader) 安卓版同步的书源，底层规则参考 [freeok/so-novel](https://github.com/freeok/so-novel)。当前已适配 CSS 选择器、动态搜索参数、JSONP 搜索结果、Base64 正文、`data-id` 段落重排及脚本分页；书源仍可能因目标网站结构、Cloudflare、代理要求或网络环境变化而失效。

下载过程会遵守书源配置中的请求间隔，并支持目录分页、正文分页以及失败重试。限流严格的书源下载时间会相应延长。

应用需要以下网络权限：

```text
ohos.permission.INTERNET
```

## 数据说明

书籍解析结果、阅读进度、书签、笔记和设置保存在应用沙箱中。卸载应用可能清除这些数据，请提前使用备份或 WebDAV 同步功能保存。

书架主数据和章节数据采用临时文件替换写入；主数据损坏时会尝试读取最近一次可用备份。

## 验证

- 在 DevEco Studio 的 Hvigor 任务中运行 `entry:test` 执行本地单元测试。
- 运行 `entry:assembleHap` 生成调试 HAP。
- 为避免测试产物与打包产物争用源映射文件，请按上述顺序串行执行两个任务。

## 说明

本项目用于 NovelReader 的 HarmonyOS 适配与学习交流。在线内容的获取和使用应遵守相关网站规则及当地法律法规。
