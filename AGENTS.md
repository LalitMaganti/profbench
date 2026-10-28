# Agent instructions

_This file is AI-generated and was reviewed by a human._

## Commit messages

Subject: `<subsystem>: <title>`, for example `profilers: add perf`.
Subsystems: `harness`, `questions`, `profilers`, `workloads`, `shim`, `docs`.

Body: a **Why** section, then a **Changes** section. No Testing section.
Wrap at 72 columns. Be short and to the point.

- **Why**: the problem or motivation, in a few sentences.
- **Changes**: bullets for what a reader needs to know, not a restatement
  of the diff.

```
profilers: add a frame-pointer method for perf

**Why**

Frame-pointer unwinding is the cheapest way to get full stacks from
perf, but cpu-time only measured the DWARF unwinder.

**Changes**

- `perf.toml` gains a `sampling-fp` method for cpu-time.
```
