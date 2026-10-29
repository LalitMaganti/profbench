# Contributing

There are three types of contribution to profbench, and each has a different
bar for acceptance.

The simplest is running existing tools in new configurations or on different
machines. Barring any obvious signs of tampering, these PRs will be accepted
promptly and without comment.

Adding a new tool (see [Profiler entries](#profiler-entries) below), run against
the existing workloads, is also fairly lightweight: we'll just need to check
that the tool exists and run it ourselves once to make sure it works correctly.

New workloads, new questions (see below) and changes to the harness need more
care, thought and input from maintainers: for example, whether a workload
overlaps with an existing one, or whether a question is actually appropriate.
Harness changes will be scrutinized especially closely as they can invalidate
existing runs and/or lead to a lack of trust in profbench as a whole if mistakes
are made.

Corrections are separate to all of this. If an existing entry or result is
wrong, a fix will be treated as a high priority and reviewed promptly,
especially if it comes from the maintainer of the tool in question.

## Profiler entries

A tool called `mytool` which can record kernel scheduler behavior and also
sample CPU stacks, with two different unwinders, might have a file called
`profilers/mytool.toml` with the following contents:

```toml
# Metadata about the tool.
[profiler]
# Short identifier, used in results and on the command line.
name = "mytool"
# One sentence on what the tool is.
description = "Records kernel and userspace activity on Linux."
# Where to find out more about the tool.
homepage = "https://example.com"
# Command whose output identifies the installed version. Recorded in results.
version = "mytool --version"

# The questions mytool competes in, and the methods it answers each with.
# Question names come from profbench's fixed set of questions.
[questions]
thread-state = ["sched-tracepoints"]
cpu-time = ["sampling-fp", "sampling-dwarf"]

# How each method works. Every method listed above must be defined here.
[methods.sched-tracepoints]
# One sentence on what this method records and how.
description = "Records the sched_switch and sched_waking kernel tracepoints."
# Runs the workload under the tool. {workload} is the workload's command line
# and {trace_dir} is an empty directory to write the trace into.
record = "mytool record -e sched -o {trace_dir}/trace -- {workload}"
# Turns the trace into profbench's standard records: one JSON object per line
# in the question's schema, for example {"type": "switch", "prev": "pb-x"}.
# Runs from profilers/, so it can call a script kept next to this file.
convert = "python3 mytool_convert.py sched {trace_dir}/trace"

[methods.sampling-fp]
description = "Samples CPU stacks, unwinding with frame pointers."
record = "mytool record --sample --unwind=fp -o {trace_dir}/trace -- {workload}"
convert = "python3 mytool_convert.py samples {trace_dir}/trace"

[methods.sampling-dwarf]
description = "Samples CPU stacks, unwinding with DWARF debug info."
record = "mytool record --sample --unwind=dwarf -o {trace_dir}/trace -- {workload}"
convert = "python3 mytool_convert.py samples {trace_dir}/trace"
```

### Metadata

The `[profiler]` section at the start is metadata about the tool, to help
people understand it or find more information about it.

### Questions

The `[questions]` section lists the questions the tool competes in. Questions
are what a user might want to answer using a profiler, e.g. "which stacks are
consuming the most CPU time?" or "what scheduling state is my app in?".
profbench defines the set of questions; a tool picks the ones it can answer and,
for each, lists the methods it answers it with.

### Methods

Methods are _how_ the profiler can be configured to answer a question. You can
often configure a tool many different ways to answer the same question: a lot
of these might be "implementation details" but are still useful for a user to
know, so listing all of them gives users a sense of their options. Each method
is measured and reported separately.

## Submission rules

profbench should produce numbers users can trust and results should
also be fully reproducible so they can be independently verified.

As such, there's a list of rules we expect everyone to follow:

- **Measure what users would run.** Tools MUST use the parameters provided by
  the harness, such as the sampling rate, and MUST NOT drop data to look
  cheaper.
- **No special-casing.** Tools MUST NOT detect profbench workloads or treat them
  differently.
- **Reproducible from this repository.** Apart from tool installation, every
  method MUST be runnable with just this repo, so anyone can reproduce its
  results.
- **Unedited results.** All results MUST be unedited results from `profbench
  run`, so every number can be traced back to how it was produced.
