# profbench

A suite of benchmarks for understanding the cost of various profiling tools and
APIs. Designed to:

- help end users understand the overhead of running profilers
- help tool authors understand the costs of APIs they are using
- help API maintainers to understand the usage of their APIs and how efficiently
  tools are using them

profbench is maintained by [Lalit Maganti](https://lalitm.com), who works on
[Perfetto](https://perfetto.dev), one of the tools measured here.
However, this project is meant to be a neutral and objective place where all
tools can be compared fairly.

Contributions or corrections from anyone, especially maintainers of other tools
are very welcome; see [CONTRIBUTING.md](CONTRIBUTING.md).

NOTE: the word "profiler" is used here purely as a catch-all convenience
covering both traditional profiling tools (e.g. sampling based) _and_ tracing
tools (e.g. instrumentation/tracepoint based).

## Why I built this

One of the first questions I hear when I talk to people about using a
profiler is "what is the overhead?" I always have to say "it depends" and
explain how there are many different conditions and cases profilers can run
under and how much environmental factors can also have an impact.

I've long looked enviously at the database world, which has industry standard
benchmarks like ClickBench and TPC-H, and at the browser world with Speedometer,
and wished we had something similar in the performance tooling space.

profbench is my attempt to build that for profilers.

## The spirit

Unlike databases, profiling doesn't have a "standard language" like SQL we can
test all tools against. However, profiling generally _does_ have a standard set
of questions users might be interested in asking. So profbench categorizes tools
based on these.

For example, the user might be interested in a question like "which stacks are
consuming the most CPU time?". Any profiler which can answer this question can
submit an entry to profbench providing a command line invocation or script which
can set up the tool to answer this question.

The harness runs a set of workloads (small test programs) tuned to the question
with and without the profiler, properly interleaving the runs, and reports a
bunch of metrics.
For example:

- the slowdown in the workload, measuring direct impact.
- the change in system-wide CPU usage, measuring indirect impact caused by the
  profiler on the system as a whole.
- a fidelity score, measuring how well the tool did at actually answering the
  question.

## Goals

**Primary**

- I would like to expand this to as many different profiling tools and APIs as
  is feasible
- I would like to increase the number of machines/environments on which the
  benchmarks are run
- I would like to increase the number of workloads which are run
- I would like to increase the _quality_ of the workloads, especially those used
  to test instrumentation.
- I would like to make this not just maintained by me in a solo fashion but if
  there are others who want to also share in the contributor burden (especially
  if they build performance tools or APIs), that would be _very_ much
  appreciated. I'm interested in setting up some sort of formal governance and
  maintenance structure as soon as there is interest in this.

**Secondary**

- I would like to extend profbench to also cover the _analysis_ side of
  profiling: generating reports, charts, flamegraphs etc. and how much time
  each takes
  - this is generally considered _less_ important by the industry today but I
    think it is just as important to the broader industry, especially with the
    rise of AI automatically doing performance in a loop.

## AI Usage and Policy

A significant amount of AI assistance was used in building the project as
nothing here is that difficult or revolutionary. All of this code was then
reviewed by humans.

The prose in human-consumed markdown was written entirely by a human with AI
being used for editing assistance (e.g. spelling, grammar, minor rewordings
etc). AI assistance was used to compile tables/charts/examples but all of these
were then reviewed by a human.

Contributions using AI are welcomed _if_ there is a human understanding the
changes being made and taking responsibility. AI contributions without human
understanding are _not_ welcome.
