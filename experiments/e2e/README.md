# End-to-end install

Every layer of the substrate was verified on its own; nothing had booted whole.
This installs N corpus packages onto a real shipped profile and boots it twice.

```bash
node e2e/run.mjs 400      # ~40s
node e2e/run.mjs 2768     # the whole tool-registering corpus, ~3.5 min
```

## What is real and what is not

**Real**: the profile (`examples/headless-agent/cordis.yml`, 25 shipped rows), the
loader, the `ToolRuntime`, the `isolate` interception, the scopes, and the tool
names — every name comes from a corpus package's actual registrations.

**Not real**: the plugin bodies. Each generated module registers its package's
real tool names and nothing else. A plugin's business logic cannot make a
registry throw; its registration set can, and that is what the corpus records.

Two consequences. Registrations the scanner could not resolve statically are
absent, so this exercises no more contention than the published data claims. And
a pass means *the composition mounts*, never *these plugins work*.

## Files

| | |
|---|---|
| `generate.mjs` | corpus records to plugin modules plus a composed `cordis.yml` |
| `shipped-tools.mjs` | reads the profile's own tool names from a real boot |
| `compose.mjs` | runs the arbitration and emits `cordis.substrate.yml` |
| `boot-once.mjs` | boots one config and reports, unwrapping the loader aggregate |
| `run.mjs` | the A/B with assertions |

`shipped-tools.mjs` exists because guessing that list is a real failure mode: an
earlier hardcoded version missed `send_message`, and the full-corpus boot failed
on exactly that name.

## Result, full corpus

```
2,768 packages · 11,911 tool registrations · 536 contended names

  without the substrate   654 registration failures, boot fails
  with the substrate      boots · 4,090 entries · 5,806 global tools
                          0 duplicate names · 648 scopes · 5,143 scope-only tools
```

A successful boot is not the claim on its own — an empty registry boots too. The
run reads every scope the substrate minted and counts the tools reachable only
through it, so "no collision" cannot be satisfied by having dropped them.
