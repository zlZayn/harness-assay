# 依据：操作者路径为何消不掉（2026-11-12）

状态：生效

## 背景

研究"目录名里的语言提示"时发现：受试体在每个 trial 里都会收到一条注入消息，把**操作者会话的根目录**也写进去。

```
The working directory changed from "D:\RDirectory\harness-assay" to "D:\assay\slots\opB-01".
```

`RDirectory` 本身就是一个 R 提示，于是每一条 trial 都被这个没人声明的通道污染。

## 结论

### 机制（代码位置可查）

`dsh-subagent/lib/index.js`：子会话的 header cwd 复制父会话的，随后 `workingDirectory.set(child, create.cwd)` 改成槽位。

`dsh-working-directory/lib/index.js`：`commit()` 读 `previous = header.cwd`，`previous === directory` 就直接返回，否则发通知并把 `previous` 写进正文。

**闭环**：给槽位 ⇒ `previous !== directory` ⇒ 必发通知；不发通知 ⇒ 只能让 cwd 等于父目录 ⇒ 没有自变量。

### 三条查过的事实

- 没有开关：`WorkingDirectoryService.Config` 只有 `defaultDirectory`。
- 没有进程外 provider 可绕：本机只有 `spawn-in-process` / `fork-in-process`。
- `previous` 对受试体无信息价值：runtime-context 另有 `Current working directory: "X"`。

### 两条死路（别重走）

**harness 的行遮蔽服务。** 时序是对的（`dsh-subagent` 先应用 preset 再查服务），而且只 inject 读该服务的探针**挂载成功**。但重新 provide 同一服务名失败：cordis 按 isolate symbol 存服务，消费者用默认 key 查——默认 key 撞重复注册，私有 key 消费者看不见。**遮蔽不跨作用域边界。**

**找 `dsh-subagent` 的 cwd 钩子。** 它的 `Config` 只有 `maxDepth` / `maxActiveSubagents`，`childSessionMeta` 对父 cwd 的复制是无条件的。

## 支撑的决策

- [窗口补丁](../../tools/patch_host_notice.py)：`--apply --expect patched` / `--revert --expect original`，关窗后逐字节等于 npm 原件。
- [通道体检](../../tools/exposure_check.py)：残留补丁与干净会话在记录里同形，只能靠读最新一条 run 判定。

## 影响

三条纪律由此固化（都已踩过）：子串不等于字节、文本模式写入会改换行、磁盘不是宿主。

宿主升级会换掉文件哈希，`patch_host_notice.py` 会拒绝改它认不出的文件——那时需要重新测量并更新脚本里的两个已知哈希。
