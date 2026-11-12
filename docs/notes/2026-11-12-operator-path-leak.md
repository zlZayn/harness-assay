# 为什么操作者路径消不掉，以及为什么 dispatcher 修不了

状态：生效（2026-11-12，宿主 `0.2.2-rc.1`）
结论一句话：**通知是"把子会话设成另一个目录"的必然结果。想去掉它，只能改宿主的发射点，或在会话根上避开。**

## 现象

受试体在每个 trial 里都会收到一条注入消息：

```
The working directory changed from "D:\RDirectory\harness-assay" to "D:\assay\slots\opB-01".
```

`from` 那一侧是操作者会话的根目录。它不在任何自有指纹里，却进入每一条 trial 的上下文——
对一个"目录名就是自变量"的研究来说，这是没人声明过的 cue 通道。

## 机制（代码位置，逐行可查）

`@deepseek-ai/dsh-subagent/lib/index.js`：

```js
// childSessionMeta：子会话的 header.cwd 直接复制父会话的
...parentHeader.cwd !== void 0 ? { cwd: parentHeader.cwd } : {},

// setup：随后把子会话改成请求的目录
const workingDirectory = childCtx.get("workingDirectory");
await workingDirectory.set(child, create.cwd, inputs.signal);
```

`@deepseek-ai/dsh-working-directory/lib/index.js`：

```js
commit(agent, directory, recovered, signal) {
  const previous = this.get(agent.session);   // = header.cwd = 父会话的根
  if (previous === directory) return;         // 相等才不发通知
  agent.session.append("working-directory/change", { cwd: directory });
  const notice = createUserMessage({
    text: `... changed from ${JSON.stringify(previous)} to ${JSON.stringify(directory)}.`,
    source: { kind: "working-directory" },
  });
  agent.inject(notice);
}
```

**闭环：** dispatcher 对子会话唯一的杠杆是 `cwd`。给槽位 ⇒ `previous !== directory` ⇒ 必发通知；
不发通知 ⇒ 只能让 cwd 等于父目录 ⇒ 槽位不存在，实验没有自变量。

## 三条断言（都是查过的，不是推测）

| 问题 | 结论 | 依据 |
|---|---|---|
| 有开关吗 | 没有 | `WorkingDirectoryService.Config` 只有 `defaultDirectory` |
| 能换 provider 绕开吗 | 不能 | 本机只有 `spawn-in-process` / `fork-in-process`，无进程外 |
| 通知里的 `previous` 是必需的吗 | 不是 | 受试体另有 runtime-context 的 `Current working directory: "X"` |

## 两条死路（别重走）

### 死路一：harness 的行遮蔽 `workingDirectory` 服务

思路正当：`dsh-subagent` 在 `childCtx.get("workingDirectory")` 之前**确实先应用了 preset**
（1803 行在 1808 行之前），所以行里的服务理应先生效。

实验对照：

| 实验 | 结果 |
|---|---|
| `probe-wd.yml`：行只 `inject: ['workingDirectory']` 并读该服务 | **挂载成功**，`1 tool(s)` —— 说明行能拿到服务 |
| 子类化 `WorkingDirectoryService` 并在行内重新 provide | **挂载失败**：`cannot get property "workingDirectory" without inject` |

失败是结构性的，原因在 cordis 的 `provide`：

```js
const key = this.ctx[symbols.isolate][name];          // 默认是全局同一个 symbol
if (this.store[key]) throw new Error(`service "${name}" has been registered at <...>`);
```

服务按 isolate symbol 存储，而**消费者（`dsh-subagent`）用默认 key 查**。于是：
默认 key 重新 provide ⇒ 重复注册；换一个 isolate key ⇒ 消费者查不到这一份。
**"遮蔽"对作用域外的消费者不成立**——只有读写双方在同一 scope 才行。行在子作用域，消费者在别处。

### 死路二：给 `dsh-subagent` 找 cwd 覆盖钩子

它的 `Config` 只有 `maxDepth` / `maxActiveSubagents`，没有 cwd 相关项；
`childSessionMeta` 对父 cwd 的复制是无条件的。要在这里挂钩，改的仍是**宿主包**，而不是 dispatcher。

## 能用的三条路

| 方案 | 宿主是否被碰 | 代价 |
|---|---|---|
| **窗口补丁**（`tools/patch_host_notice.py`） | 开窗期间改一行；关窗逐字节还原、连备份一起删 | 升级后要重测哈希 |
| 换会话根（在中性路径下开会话） | 完全不碰 | 需要新会话 |
| 接受并声明该常量为协变量 | 完全不碰 | cue 实验做不干净 |

选窗口补丁，因为它做到了**静止态零残留**：实测关窗后 `state: original  backup: none`，
包目录只剩 npm 装的 `index.js`，哈希回到 `76b2f535…`。

## 三条操作纪律（都踩过）

1. **子串不等于字节。** 第一版 revert 见原文片段在就跳过，而文件实际大了 171 字节、
   每行都被换成 CRLF。状态改由 sha256 判定，并记下 `0.2.2-rc.1` 的两个已知哈希。
2. **文本模式写入就是换行的源头。** 补丁与还原都改成纯字节操作。
3. **磁盘不是宿主。** 进程把模块持在内存里，窗口边界是 `dsh_hot_reload` 而不是写文件。
   三次 run 把这件事钉住：`opA-01`（原始）泄漏、`patch-check-01`（开窗）不泄漏、
   `revert-check-01`（关窗 + 重载）又泄漏。

## 为什么还要留一个 guard

**残留的补丁和干净的会话，在记录里长得一模一样**——两者都是"通知里没有操作者路径"。
所以不能靠"我记得我关过窗"判断。`tools/exposure_check.py` 读最新一条 run 的通知：
`FAIL` 说明当前环境不能做 cue 实验，`PASS` 也只是说这一条干净。
