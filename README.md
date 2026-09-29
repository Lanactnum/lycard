<div align="center">

# lycard

**Lycee Overture 卡组助手**

离线优先的卡库 · 卡图 · 中文翻译 · 卡组构筑 · 局内数值计算

[**中文**](README.md) ｜ [English](README.en.md) ｜ [日本語](README.ja.md)

[下载 APK](https://github.com/Lanactnum/lycard-updates/releases) · [更新日志](CHANGELOG.md) · [卡图数据包](../../releases/tag/cards-pack-v1)

</div>

---

## 这是什么

`lycard` 是一个给 **LYCEE OVERTURE** 玩家用的安卓（arm64）小工具。

所有数据都在本地，**没网也能查卡、组卡、算数**。卡图用双层方案：安装包里带一份
压缩过的 WebP（够看），想要 372×520 的**官方 PNG 原图**就另外挂一个数据包 ——
所以安装包没有膨胀到好几个 GB。

> 非官方作品。卡片数值、效果原文与卡图的权利归 LYCEE OVERTURE 官方及各作品权利人所有，
> 本项目仅供个人收藏与对局查阅，不得用于商业用途。详见[许可](#许可)。

## 功能

### 检索

- 按**卡名 / 卡号 / 效果文本**搜索，中文名也能搜到（自带中文搜索索引）
- 按属性（日 / 月 / 花 / 雪 / 星 / 宙）、费用、EX、卡种、系列、稀有度等多维筛选
- 卡详情：卡图、数值、效果原文 + 中文翻译；效果文本里提到的**卡名可以点着跳过去**
- 卡图四级回退：**数据包原图 → 安装包内置图 → 联网官网 → 占位图**，
  任何一环缺失都不会崩
- 卡图可以批量保存到相册

### 构筑

- 主卡组 60 张、同编号最多 4 张、leader 最多 1 张；
  **限定赛**自动切成 30 张 / 同编号最多 2 张 / 不能带备卡区
- 卡组收藏夹按**卡牌所属系列**（作品 / 游戏 / 会社）分类，不是按 LO 编号
- 起手模拟、卡组统计图（属性 / 费用 / 卡种占比）
- 卡组导入：官方卡组码和常见分享文本**两套识别系统**，一套认不准可以手动换另一套
- 卡组导出：二维码分享、文本分享
- 卡组表打印（PDF）

### 计算器

对局中把牌摆到场上，实时算数。

- **上卡即自动算**：卡面效果里「放上场就生效」的（`[常時]` 或没写标签的）直接算进数值；
  `[誘発]` / `[宣言]` 这类**要用才生效**的不会替你猜，留在卡的面板里一键或逐条套用
- **场地一变就整体重算**：「味方キャラ全てにＡＰ＋１」这种全场效果，**后上场的卡也吃得到**；
  把来源卡拿掉，它给的加成会从别人身上一起收回
- **每一步都能看、能改、能删**：每条修正都标着来源（手动 / 效果 / 自动）和时机
  （上回合 / 此回合 / 应对 / 常时），数值随手改
- 每张卡下面的**充能**张数、**储存区（置き場）**张数 —— 和实体牌一样挂在卡下面
- 局面**不保存**，退出即清空

### 其它

- 对战规则速查、禁限卡表（可联网更新）
- 词条 / 效果片段速查
- 相机扫描：识别卡面文字或二维码，直接跳到那张卡
- 界面多语言（简体中文 / 繁體中文 / English / 日本語 / 한국어 / Русский）
- 数据热更新：卡表、翻译、禁限表等可联网增量更新，也可从文件管理器导入数据包
- 本地备份 / 恢复（zip）、打印、反馈通道

## 下载与安装

只发 **arm64**（现在的手机基本都是）。

**安装包在更新仓库里**：[`Lanactnum/lycard-updates` → Releases](https://github.com/Lanactnum/lycard-updates/releases)
—— App 里的「检查更新」连的也是它。本仓库的 Releases 只放**卡图数据包**。

| 文件 | 说明 |
|---|---|
| `lycard-<版本>.apk` | 安装包，约 **600 MB** —— 里面已经带了压缩卡图，只装它也能用 |
| `lycard-<版本>.apk.sha256` | 校验值 |

装完请**先启动一次**，让 App 把自己的数据目录建出来。

## 卡图数据包

安装包里的是**压缩过**的卡图。想要官方 **372×520 PNG 原图**，去本仓库的 Release
[**cards-pack-v1**](../../releases/tag/cards-pack-v1) 下：

| 文件 | 大小 |
|---|---|
| `lycee_cards.pack.part01` + `.part02` | 合起来 **3.65 GB**（3,919,354,515 字节） |

GitHub 单个附件上限 2 GB，所以拆成了两卷。**合并**（三选一）：

**Windows（推荐，用仓库里的脚本）**

```bat
python tools\join_cards_pack.py %USERPROFILE%\Downloads
```

**Windows（没有 Python）**

```bat
copy /b lycee_cards.pack.part01+lycee_cards.pack.part02 lycee_cards.pack
```

**Linux / macOS / WSL**

```bash
cat lycee_cards.pack.part* > lycee_cards.pack
```

合并后的大小应该是 **3,919,354,515 字节**，SHA256 应该是：

```
49b26768074e345710ec7d6d9599a6bf3c9aaf2111114017d7b05c599170f5a9
```

> 一定要对一下。下载断在中间是真实会发生的，而它的症状是「**有些卡图是空白的**」，
> 很容易被当成 App 的 bug。

**放哪儿**（任选其一）：

1. **在手机上**（推荐，全程不用数据线）：把 `lycee_cards.pack` 丢进手机「下载」文件夹，
   然后 App 里 **我的 → 数据与备份 → 从文件管理器选择数据包**。
2. **用电脑**：`adb push lycee_cards.pack /sdcard/Android/data/com.lycard.app/files/`
   —— App 必须**先启动过一次**，否则这个目录还不存在。

放好后 App 会自动认，也可以在设置里点「重新扫描」。

> 为什么不让大家用数据线：Android 11 以后 `Android/data` 在文件管理器里根本看不见，
> 所以第 1 种方式才是给普通玩家的。

## 从源码构建

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
```

只出 arm64：全架构包会大一倍多、装的时间也翻倍，而现在的手机基本都是 arm64。

**签名**：仓库里**没有**签名密钥（`android/key.properties`、`android/*.jks` 都在 `.gitignore` 里）。
想出自己的包，自己生成一份：

```bash
keytool -genkey -v -keystore android/my-release.jks -keyalg RSA -keysize 2048 \
        -validity 10000 -alias mykey
```

然后照着 `android/app/build.gradle.kts` 里的 `signingConfigs` 写一份 `android/key.properties`。

**测试**：

```bash
flutter analyze     # 应当 No issues found
flutter test        # 200+ 条
python tools/check_bottom_pad.py   # 底栏遮挡自检
```

## 数据来源

- 卡片数据与卡图：**LYCEE OVERTURE 官方网站**（`lycee-tcg.com`）
- 中文翻译：**本项目自行翻译**，术语按官方《基本能力及字段说明》统一
- 部分历史数据用 **Wayback Machine** 补齐

`tools/` 下是一次性的数据流水线（抓取 / 翻译 / 打包 / 体检），见下面的工具链。

## 项目结构

```
lib/
  data/       卡库加载、中文搜索索引、数据包读取
  l10n/       界面多语言表
  models/     卡片、卡组等模型
  pages/      各页面（检索 / 构筑 / 计算器 / 我的 / 规则 …）
  services/   扫描识别、打印、备份等
  state/      应用状态；计算器的数据模型与效果解析器
  widgets/    统一外观组件（玻璃面板 / 标签 / 布局常量 …）
assets/
  data/       卡表、翻译、搜索索引、禁限表、词条
  cards/      内置压缩卡图（约 517 MB）
tools/        数据流水线 + 体检脚本
test/         测试
```

## 工具链

| 脚本 | 作用 |
|---|---|
| `tools/fetch_list.py` | 从官网抓卡表（列表页一次拿全字段） |
| `tools/make_app_data.py` | 生成 App 用的 `cards_app.json`（白名单挑字段） |
| `tools/build_pack.py` | 把 PNG 原图打成 `lycee_cards.pack` |
| `tools/join_cards_pack.py` | 把 Release 里的分卷合并回数据包 |
| `tools/build_search_keys.py` | 重建中文搜索索引 |
| `tools/check_bottom_pad.py` | 底栏遮挡自检 |

## 许可

- **代码**：MIT，见 [LICENSE](LICENSE)
- **卡片数据 / 效果原文 / 卡图**：版权归 LYCEE OVERTURE 官方及各作品权利人所有，
  **不在 MIT 范围内**，仅供个人收藏与对局查阅，不得用于商业用途
- **本项目的中文翻译**：自行翻译，随本项目一并按 MIT 提供

