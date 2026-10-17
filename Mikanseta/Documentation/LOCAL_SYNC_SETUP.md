# 共享文件夹同步（与原生 Mikansei / 其它 Mikanseta 设备）

Mikanseta 0.4.0 起支持“共享文件夹同步”：每台设备**一次性**选择一个文件夹，之后自动与原生 Mikansei 以及其它 Mikanseta 设备交换、合并数据，不需要手动导出或导入 JSON。

同步使用原生 Mikansei 已有的文件夹同步协议，因此和原版的 iCloud Drive 文件夹同步完全互通：

- 每台设备只在 `<所选文件夹>/Mikansei-sync/` 下写自己的 `replica-<设备UUID>.json`；
- 每次交换读取并合并该目录下所有设备的文件；
- 冲突按修订号（counter + 设备 UUID）判定，删除带永久墓碑，不会因离线旧副本复活。

## 设置

### Mac（Mikanseta）

1. 打开 Mikanseta → 设置 → **本机同步（与 Mikansei）** → **选择共享文件夹**；
2. 选择原生 Mikansei 正在使用的同一个文件夹（例如 iCloud Drive 里的 `Mikansei Cloud`）；
3. 原版 Mikansei 侧：设置 → **iCloud Drive · 跨设备同步** → 选择同一文件夹（若尚未选择）。

### iPhone（Mikanseta）

1. 设置 → 本机同步 → 选择共享文件夹 → 在“文件”选择器里选同一个 iCloud Drive 文件夹；
2. 原版 Mikansei 手机上同样连接这个文件夹后，两个 App 即自动互通。

### Android（Mikanseta）

1. 设置 → 本机同步 → 选择共享文件夹 → 系统文件选择器里选择文件夹；
2. Android 无法访问 iCloud。要与 Apple 设备互通，请选择 Google Drive / OneDrive / Dropbox 等三端都能访问的云盘文件夹：
   - Mac / iPhone 在文件选择器里选择该云盘同步到本机的文件夹；
   - Android 用系统选择器（SAF）选择同一个云盘文件夹。

## 行为

- 本机保存后约 2 秒写出同步文件；每 30 秒检查一次；回到前台和“立即同步”也会触发。
- 首次连接会把两端已有内容合并，不会清空任何一端。
- 同一事项按修订号保留较新版本；删除会同步。
- 可与 Supabase 账户同步同时开启：本机文件夹负责与原生 Mikansei 互通，Supabase 负责账号内的其它设备；两者最终会收敛到同样的数据。
- 系统日历来源等按设备设置不参与同步。

## 注意

- 每台设备只需选择一次文件夹，授权由系统持久化（macOS/iOS 安全作用域书签、Android SAF 持久授权）。
- 请选择个人云盘中的私有文件夹，不要选择公开共享目录。
- 换文件夹或停止同步只影响当前设备，已写入的同步文件与两端数据都会保留。
- iPhone 与 Mac 的 Mikanseta 需要同一 App 版本；旧版（0.3.x 及以前）不支持该功能。
- 原生协议的日历导入跨设备去重尚未移植：若两台设备分别导入同一系统日历，可能出现重复条目。
