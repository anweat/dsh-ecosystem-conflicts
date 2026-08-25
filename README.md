# DSH ecosystem conflict study

A static survey of the DeepSeek Harness plugin ecosystem, the conflicts it currently produces, and reproducible experiments against the harness's own mechanisms.

Everything here is derived from public repositories and from the harness's own source. No plugin source code is redistributed — the pipeline re-derives it from the original repositories.

**中文摘要在文末。**

---

## Headline findings

**9,873 real plugins** identified out of 12,630 harvested repositories (a repository counts as a real plugin when it declares `package.json#dsh`, ships a `cordis.patch.yml`, or contains actual registration calls).

### The structural finding

```
entry rows inserted at the root:      9,216
entry rows inserted under a group:        0
```

Not one third-party plugin mounts under a group. Every one of them registers into the root context.

This matters because the shipped architecture puts model-facing rows on the **agent plane**, not the host plane. Quantitatively: of the 24 rows `packages/bundle/web-app/cordis.patch.yml` disables at the root, **22 are re-mounted inside `apps/cli/config/agent-presets/standard/agent.cordis.yml`** — the two exceptions are `hmr` and `tool-str-replace-editor`, which are genuinely off. `dsh-agent-presets` warns that an agent which joined no preset resolves "against the empty global layer".

So the global layer is meant to be empty, and the entire ecosystem is registering into it.

### Resulting conflicts

| Kind | Groups | Packages | Runtime consequence |
|---|---:|---:|---|
| `tool-name-collision` | 553 | 855 | `tools.register` throws → **boot failure** |
| `entry-id-collision` | 452 | 1042 | later patch layers can only address one of them |
| `orphan-patch` | 89 | 87 | one stderr warning, then skipped → **silent no-op** |
| `config-row-contention` | 77 | 381 | a patch replaces the whole `config` → silent field loss |
| `slot-key-collision` | 62 | 226 | UI entry shadowed |
| `tool-name-vs-shipped` | 28 | 77 | collides with a shipped tool → **boot failure** |
| `slot-shadow` | 24 | 303 | `single` seat, only one renders |
| `config-key-drop` | 19 | 11 | provable subset of contention |

Most contended tool names: `country_info` (84 packages), `element_info` (55), `bash` (44), `memory_search` (37), `generate_image` (29).

Most contended entry ids are **all infrastructure**: `storage` (29), `storage-json` (29), `storage-domain` (29), `agent-presets` (26), `code-runtime` (25) — plugins each re-inserting what the host is supposed to provide.

### What the ecosystem actually modifies

| Surface | Distinct packages | | Interception point | Packages |
|---|---:|---|---|---:|
| `slots.register` | 4291 | | `session/event` | 995 |
| `tools.register` | 3890 | | `agent/pre-step` | 513 |
| event listeners | 2775 | | `tools/pre-execute` | 349 |
| `webServer.register` | 2702 | | `llm/stream` | 256 |
| `settings.register` | 827 | | `system-prompt/assemble` | 218 |

**19.8% (1,951 packages) intervene in the turn or tool pipeline.**

The strongest co-occurrence by a wide margin: **2,622 packages register a UI slot *and* an HTTP route** — everyone is hand-rolling "a panel plus the endpoint that feeds it".

---

## Mechanism experiments

Ten scripts in [`experiments/`](experiments/) verify how the harness behaves, against a clone of the harness itself. Each prints PASS/FAIL and exits non-zero on failure.

| Script | Asserts | Result |
|---|---|---|
| `lab-isolate-proxy.ts` | a remapped isolate symbol yields a separate service instance; `ctx.root` reaches the real one from inside a realm; a service sees the **calling** context, so one realm-level instance can attribute every call to its caller | 10/10 |
| `lab-real-registry.ts` | against the real `ToolRuntime`: two plugin scopes may claim one tool name; an agent whose chain includes a plugin scope sees that tool **under its original name**; the nearer scope on a chain shadows the farther one — precedence is the declared chain order, not activation order | 12/12 |
| `lab-loader-isolate.ts` | end-to-end through the real loader: `cordis:group` + `isolate` places a shim between consumers and the root service, **declared purely in `cordis.yml`** | 6/6 |
| `lab-event-order.ts` | `prepend: true` wins the front seat; a prepend/last sentinel pair detects a waterfall short-circuit; `tools.guard()` still denies after a listener short-circuits the pre-execute waterfall | 5/5 |
| `lab-substrate-e2e.ts` | the whole chain against the real `ToolRuntime`: arbitrate → plan the scope chain → mount along it. Two packages that collide today both register, the tool name is unchanged, the agent resolves the arbitrated winner, and the loser's other tools stay visible | 18/18 |
| `lab-gatekeeper-timing.ts` | *when* a conflict happens: at loader apply, before any agent exists — so an `agent/created` veto never gets its turn. The entry list, however, is complete before those fibers apply, and the conflict is predictable from it | 9/9 |
| `lab-gate-ordering.ts` | whether a gatekeeper can be *guaranteed* to run first. File position guarantees nothing; `inject` is an entry option, so a patch layer can make third-party rows depend on the substrate and the dependency graph enforces the order | 7/7 |
| `lab-gatekeeper-plugin.ts` | the gatekeeper in a real boot: veto refuses and names the contenders, report warns without repairing, a clean composition is undisturbed | 13/13 |
| `lab-preset-host.ts` | repair rather than refusal: `standingKeyFor` composes a preset without binding the agent, so the substrate builds the plugin chain above it and performs the binding itself. The agent resolves the arbitrated winner over the preset's own tool | 18/18 |
| `lab-scale.ts` | the whole corpus against the real registry: 896 scopes on one chain, 7,164 tool registrations, zero throws | 18/18 |
| `lab-client-priority.ts` | a working prototype of `BootPluginRow.priority` (patch included): a contended client seat becomes an ordinary shadow instead of an all-or-nothing plugin disable, an explicit priority still wins, and an un-seeded composition behaves exactly as before | 12/12 |

Run them from a harness clone:

```bash
node --import tsx/esm lab-isolate-proxy.ts
node --import tsx/esm lab-real-registry.ts
node --import tsx/esm lab-loader-isolate.ts
node --import tsx/esm lab-event-order.ts
node --import tsx/esm lab-substrate-e2e.ts
node --import tsx/esm lab-gatekeeper-timing.ts
node --import tsx/esm lab-gate-ordering.ts
node --import tsx/esm lab-gatekeeper-plugin.ts
node --import tsx/esm lab-preset-host.ts
node --import tsx/esm lab-scale.ts
node --import tsx/esm lab-client-priority.ts   # apply experiments/bootpluginrow-priority.patch first
```

**What this establishes**: tool-name collisions are resolvable by scope layering without renaming anything the model sees; the interception layer is declarable from a patch file with no upstream change; and a substrate can intervene in two distinct ways — refusing a composition before it fails (the gatekeeper), or repairing it at agent setup (the preset host).

Two findings here corrected earlier assumptions of ours, and are worth stating because they constrain any design in this space:

- **An `agent/created` veto is too late.** The registrations that fail a boot happen at loader apply, before any agent exists. A gatekeeper has to read the entry list, which is complete before those fibers run.
- **A preset is one scope.** `mount()` binds an agent to a single standing key, so two plugins contending for a name cannot both live in one preset — they collide exactly as they do at the root. Layering them requires a scope per plugin, built above the standing mount via `standingKeyFor`.

---

## Arbitration replay

[`arbitration/`](arbitration/) is a pure function — no harness API, no filesystem — from contributions plus a precedence policy to decisions. It exists so the claim "these conflicts are resolvable" can be checked rather than asserted, by replaying it over the whole corpus.

```bash
node arbitration/arbitrate.spec.mjs     # 41 assertions — normalization, decisions, reserved names
node arbitration/emit-patch.spec.mjs    # 26 assertions — patch rows, replayed through a mirror of applyEntryPatches
node arbitration/scope-chain.spec.mjs   # 24 assertions — scope ordering and cycle detection
node arbitration/realm-proxy.spec.mjs   # 17 assertions — route rewriting for a registry with no scope model
node arbitration/emit-preset.spec.mjs   # 24 assertions — agent-plane composition and its one-scope constraint
node arbitration/predict.spec.mjs       # 26 assertions — predicting conflicts from the entry list alone
node arbitration/baseline.mjs           # replay over the corpus
```

The remedies are not interchangeable — each is the response the runtime actually permits for that kind. `layer` (scope layering, everyone keeps the name, precedence is the declared chain order) applies to tools; `rename` to entry ids, where nothing addresses them by name from outside; `isolate` to routes, which have no scope model; `drop-client` to client-plane slots, because the browser half has no configuration seam at all.

### Result over 9,617 scanned records (8,540 distinct package names, 52,301 contributions)

**Today, with everything installed:** 581 cells would make a registry throw, involving **896 packages (10.5%)**. One is enough to fail the whole boot.

**After arbitration:**

| Outcome | Packages | Share | Meaning |
|---|---:|---:|---|
| `intact` | 6,614 | 77.4% | every contribution keeps its declared target |
| `adapted` | 1,123 | 13.1% | something was layered, renamed, or isolated; function is complete |
| `degraded` | 803 | 9.4% | browser half withheld |
| **coexisting** | **7,737** | **90.6%** | |

Remedy distribution: `layer` 581, `rename` 453, `drop-client` 90, `report-only` 77.

**Pairwise — the number a user feels.** Nobody installs 9,617 plugins, but installing two that collide happens daily. Of 4,000 sampled pairs that are mutually fatal today, **3,941 (98.5%) coexist after arbitration**; 59 (1.5%) still lose frontend function.

All 581 tool-name conflicts resolve to `layer` — **not one requires changing a name the model sees**. Every remaining functional loss is on the client plane, which is exactly the gap [`BootPluginRow` priority](#three-things-the-config-layer-cannot-reach) would close.

### One preset is one scope

A preset is mounted once under a single standing scope and an agent binds to that one key, so every row in a preset shares one registration layer. Two plugins contending for a name therefore cannot both live in one preset — they collide exactly as they do at the root. The preset emitter composes a conflict-free set and reports what it excluded, rather than emitting a composition that fails to mount. Layering contenders is the scope-chain path, not the preset path.

### One linear scope chain is enough

`dsh-scope` binds each key to at most one parent and `scopeChainOf` returns a line, so every layered decision has to be satisfiable by a single ancestor order. Two decisions can disagree — A ahead of B for one tool, B ahead of A for another — and then no linear chain satisfies both.

Over the corpus that never happens:

```
chain length 896 | ordering constraints 1,492
satisfiable    1,492 (100.0%)
unsatisfiable      0
packages on a cycle 0
```

Which follows: an ordering constraint only arises when two scopes claim the *same* name, and a cycle needs two packages to beat each other on two different names. The planner still detects cycles and reports which constraints it had to sacrifice rather than emitting an order that looks correct — that path is covered by assertions, just not exercised by this ecosystem.

### At full scale, against the real registry

Replaying decisions offline shows they are consistent; it does not show they work. [`experiments/lab-scale.ts`](experiments/lab-scale.ts) takes the same corpus, mints **896 real scopes** on one chain with the real `dsh-scope`, and performs **7,164 tool registrations** against the real `ToolRuntime`:

```
arbitration    71 ms      chain planning   48 ms
minting 896 scopes  114 ms      7,164 registrations  1,188 ms
registration throws  0          agent-visible tools  5,589   duplicate names  0
contended tools 553 | resolved to a non-winner 0 | missing 0
```

Every one of those 553 contended tools resolves to the arbitrated winner, under its original name, with the global layer left empty.

**Scale found a conflict class that reading the source did not.** One package registers a tool named `run_code`, which the registry refuses unconditionally — "reserved for the Code Mode presentation transport and cannot be registered or shadowed". Scope layering, the remedy for every other tool-name conflict, does not apply: reserved is not "taken in this layer", it is refused everywhere. Arbitration now models it as its own outcome (`drop`, winner `<reserved>`), because the honest answer is that nobody gets the name.

### What the one upstream request is worth

Request 3 below — `BootPluginRow` carrying a priority — is the only one of the three with a measured payoff, and [`experiments/bootpluginrow-priority.patch`](experiments/bootpluginrow-priority.patch) is a working 37-line prototype of it (two files: the manifest row, and the default the slot service applies when a registration sets none).

Re-running the same arbitration with client seats shadowing instead of withholding ([`arbitration/whatif-client-priority.mjs`](arbitration/whatif-client-priority.mjs)):

```
                              intact   adapted   degraded
  today (no manifest rank)      6,618     1,122        804
  with BootPluginRow.priority   6,618     1,925          1

  degraded  804 → 1   (803 packages, 9.4% of the corpus)
  coexisting  90.6% → 100.0%
```

The single remaining degraded package is the reserved-name case, which no ranking can fix. Everything else the client plane costs today is this one missing field.

Raw output: [`data/arbitration-baseline.json`](data/arbitration-baseline.json).

---

## The design tokens are ambient but unpublished

The shell defines its design tokens on `body` and redefines them under `body[data-ds-dark-theme]`, so every plugin's CSS inherits the whole vocabulary for free. `ui-primitives` and `ui-slots` are platform seed words alongside `react`, shared as single instances. The design system is real and already at platform level.

What it has no export surface for is the vocabulary itself. Nothing tells a plugin author which token names exist, which of them a theme redefines, or which references have gone stale. [`arbitration/tokens.mjs`](arbitration/tokens.mjs) turns the ambient definitions into a checkable contract.

```
350 tokens over 7 tiers
  alias      78    66 redefined under the dark theme
  static     73     1
  specific   11    10
  font      181     0   (markdown typography)
```

The tier split is what a plugin author needs and cannot currently discover: `alias` names a role and flips between themes, `static` names a fixed palette entry and does not.

### Three rules, one of them a proven defect

| rule | severity | what it means |
|---|---|---|
| `dangling` | **error** | the token is defined nowhere and the reference has no fallback |
| `static-on-themed` | advisory | a fixed palette entry on a property the theme should drive |
| `pinned-literal` | advisory | an opaque colour written where a token belongs |

Only `dangling` is self-evidently wrong: the declaration is invalid at computed-value time and resolves to nothing. The other two have legitimate exceptions — a brand accent is deliberately identical in both themes, and a surface that stays dark in both (`--dsw-alias-tooltip-bg` is `neutral-bluish-850` light and `-750` dark) correctly carries light text as a literal. Flagging those as errors is how a lint gets discarded by its first user, so they advise and never decide an exit status.

### First run against the shipped client

**10 defects and 13 advisories** over `packages/client`. The heaviest: `--dsw-alias-label-error` is defined nowhere in the repository, and is used bare by `ui-settings-plugins` in `fields.module.css:98,105` and `PluginCard.module.css:116`.

Measured in a browser against those exact rules:

```
error text   today          rgb(26, 26, 26)     <- body black
error text   if defined     rgb(220, 38, 38)    <- the intended red
input border today          rgb(0, 0, 0)        <- currentColor
```

**Validation errors in the plugin settings panel do not render red today.** That is one of ten, found on the contract's first run.

```bash
node arbitration/tokens-cli.mjs emit <dsh-root> [out.d.ts]
node arbitration/tokens-cli.mjs lint <dsh-root> [scan-root]
```

Tests: [`arbitration/tokens.spec.mjs`](arbitration/tokens.spec.mjs), 49 assertions.

---

## The panel scaffold

A panel — a slot entry plus the backend feeding it — is the ecosystem's most repeated shape: **2,155 packages register both**. They write the path three times, in three places, with nothing checking the three agree.

Two runtime facts shape [`arbitration/panel.mjs`](arbitration/panel.mjs), and both were measured rather than assumed.

**No backend seam is additive.** `webServer.register` throws on a duplicate path, `connection.rpc.handle` becomes a prefix route and throws the same way, and `intercept('/api')` holds one interceptor for the whole process. A path is therefore not a name a plugin may pick freely.

**Identity comes from the calling fiber.** `SlotRegistry` stamps `registrant` from `this.ctx.fiber.name`; `connection.rpc` captures `owner = this.ctx`. A scaffold that registered on a plugin's behalf from its own fiber would stamp the whole ecosystem with its own name and leave arbitration unable to tell two plugins apart. Verified against the real registry:

```
mountPanelClient(pluginCtx,   …)   registrant = plugin-a        <- identity kept
mountPanelClient(scaffoldCtx, …)   registrant = the-scaffold    <- the wrapping failure
```

So the scaffold is a function a plugin calls with its own `ctx`. It emits registrations; it never wraps them.

### Deriving the channel

`channelFor('@scope/thing', 'main')` yields `/scope-thing.main`. The two halves join with `.` rather than nesting because the connection's grammar is `^\/[A-Za-z0-9._~-]+$` — exactly one segment. Slugging maps every separator to `-`, so `.` cannot occur inside either half and one `(pkg, panel)` pair yields one channel.

Measured over the route sample ([`arbitration/whatif-panel-channels.mjs`](arbitration/whatif-panel-channels.mjs)):

```
503 repositories · 845 distinct literal paths

  contended paths        49    involving 32 packages
  separable by deriving  49    100.0%
  still colliding         0    two copies of one package, which must collide
```

The contended paths are shared-ancestry forks — `/sidebar/*` is claimed by four packages, `/dsh-market/*` by four more — but the forks renamed their packages, so deriving from the package name does separate them. Today installing two of them is a boot failure; derived, both work, each serving its own copy. Four of the 49 are `/plugins`, claimed by host wrappers that replace the harness rather than coexist with it; a plugin-side convention was never going to reach those.

### What it does not do

The scaffold does not hide a real conflict. One package mounting the same panel twice still throws, and a handler map that disagrees with the declared endpoints fails at mount rather than at first request.

Tests: [`arbitration/panel.spec.mjs`](arbitration/panel.spec.mjs) (44 assertions) and [`experiments/lab-panel.ts`](experiments/lab-panel.ts) (11, against the real `SlotRegistry`, `WebServer`, and connection — including a real HTTP round trip and channel removal on plugin disposal).

---

## What one substrate decision costs at runtime

The substrate writes its decisions into the user patch layer, and its emitter owns that file wholly — it regenerates rather than appends, because patch rows carry no conditional guard and stacking them would build a group twice. That contract is only affordable if re-applying a rewritten file touches the rows that changed and leaves the rest alone.

Measured in [`experiments/lab-no-restart.ts`](experiments/lab-no-restart.ts) (21 assertions), against the real watcher wiring:

| edit | cost |
|---|---|
| disable one row | that row disposes; nothing else disposes or re-applies |
| clear the patch | only the disabled row comes back |
| **rewrite the whole file** | unchanged rows are untouched |
| change one row's config | that row disposes and re-applies; others do not |
| write a malformed patch | the tree survives, and the next good patch still applies |

The third row is why the experiment exists. If rewriting the file rebuilt the tree, every substrate decision would cost a full restart and nobody would run it interactively.

### The browser is not told

The dev channel `/plugins/events` carries two frame types, `graph` and `rebuilt`. A roster change produces neither:

```
PASS  the host does subscribe to graph changes — onGraphChanged fires
PASS  the host is notified, and writes nothing to the channel
PASS  a rebuilt frame still arrives on the same channel — the silence is real
```

The host writes `graph` exactly once, when a connection opens (`packages/client/hmr/src/index.ts:160`); its only ongoing subscription is `onRebuilt`. `onGraphChanged` *is* subscribed, but only to re-sync bundle watches (`:138`). The browser half ignores the frame outright:

```js
case 'graph':
  // Connect-time snapshot, unused.
  break
```

**So host-plane decisions are live and client-plane decisions need a page reload.**

That is where a fourth upstream request sits, structurally like the `BootPluginRow.priority` one: the host already knows, it just does not forward. It is not the same size, though — acting on the frame needs roster reconciliation in the browser, which reaches into the loader's add/remove semantics. No prototype is offered here, because half a fix is not one.

---

## Method

[`pipeline/`](pipeline/) contains the scanner that produced `data/`.

1. **Harvest** — GitHub search with adaptive date slicing (search caps at 1,000 results per query).
2. **Stream** — shallow-clone, analyze, delete. Peak disk stays at roughly one repo per worker rather than the whole corpus. A free-space floor stops the run cleanly.
3. **Extract**, two planes:
   - *Declarative, authoritative*: `package.json#dsh` and `cordis.patch.yml`, replayed through a mirror of the harness's own `applyEntryPatches`, so insert / override / disable classification cannot drift from what actually boots.
   - *Implementation, heuristic*: registration call sites. Bundlers rename identifiers but never property names, so matching keys on the property-chain suffix (`.slots.register`) and the string literals passed to it — never on a `ctx` variable name.
4. **Baseline** — the known-component tables are exported from the harness checkout itself (generated slot catalog, service/event catalogs, composed bundle patches), never hand-written.
5. **Arbitrate** — a conflict is only counted where the runtime actually makes it one: a `single`/`keyed` seat, a registry that throws, or a config row two layers both rewrite. `list`/`chain` seats are additive by construction and are counted, never flagged.

### Limitations, stated plainly

- **63% of route registrations carry a literal path**; the other 37% pass a non-literal and are statically undecidable. Route findings are a **sample of 503 repositories**, not the full corpus.
- Route contention is dominated by **forks**, not independent collisions: `/sidebar/*` and `/dsh-market/*` are whole route surfaces shared by forks of one plugin, and `/plugins` collisions are mostly full-host wrappers that replace the harness rather than coexist with it.
- Slot `key` and `priority` are frequently non-literal; those registrations are reported as *undecidable*, never as conflicts.
- Packages shipping both `src/` and `lib/` were initially double-counted (14.6% of plugins, ~11% of registration points). The pipeline now drops the build plane when sources sit beside it, and the published data is corrected.
- 22 of 12,630 repositories failed to clone and are simply absent.
- One package's `dsh` manifest can describe a monorepo root rather than a plugin; those appear in the data as ordinary packages.

Being named in `data/conflicts.json` is not a judgement about a plugin. The dominant cause is structural — the two-plane split is not visible to plugin authors — and most of these packages work fine in isolation.

---

## Data files

| File | Contents |
|---|---|
| `data/summary.json` | headline counts, branching factors, contribution mix |
| `data/conflicts.json` | every conflict group with its severity, target, and named parties |
| `data/surfaces.json` | slot occupancy, tool namespace, event usage, contended config rows |
| `data/routes.json` | route sample: distinct paths and their claimants |

The per-repository raw extraction is deliberately not published. The pipeline reproduces it from public sources.

---

## 中文摘要

对 DeepSeek Harness 插件生态的静态调查:从 12,630 个仓库中识别出 **9,873 个真实插件**,并对照 harness 自身源码验证其机制。

**结构性发现**:9,216 个 entry 行插入到根,**插入到分组下的为 0**。而出厂架构把模型可见的行放在 agent 平面——web-app 在根上禁用的 24 行里,22 行在 `standard` 预设中重新挂上。也就是说全局层设计上应为空,而整个生态都注册在里面。

**由此产生**:553 起工具名撞车 + 28 起撞官方工具(均导致启动失败)、452 起 entry id 撞车、89 起孤儿补丁静默失效、77 起配置行争用。撞得最狠的 entry id 全是基础设施(`storage`、`agent-presets`、`code-runtime`)——插件在各自重新插入宿主本该提供的东西。

**机制实验**(`experiments/`,共 33 项断言全部通过)证明:工具名冲突可以靠 scope 分层解决而**无需改动模型可见的名字**,且拦截层可以**纯从补丁文件声明**,不需要上游改动。

局限已在上文 Limitations 一节列明:路由数据是 503 个仓库的抽样且 37% 静态不可判定;路由争用以分叉为主而非独立撞车。**被列入 `data/conflicts.json` 不代表对该插件的评判**——主因是结构性的,大多数插件单独使用都正常。

---

## License

MIT. The pipeline and experiments are original work; the data is derived from public repositories and from the MIT-licensed DeepSeek Harness source.
