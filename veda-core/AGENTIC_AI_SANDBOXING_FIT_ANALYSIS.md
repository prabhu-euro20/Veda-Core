# Domain 3 Analysis: Agentic AI Tool-Sandboxing

**Date:** 2026-07-27
**Scope:** third of four "out-of-the-box" directions — real, WebSearch
-verified research into how AI-agent code-execution sandboxing actually
works today, then critically checked against what Veda-Core's real
mechanism can and cannot contribute (a narrower, more precise claim than
"good for AI safety" in general).

## What real, current agent sandboxing actually is — verified, not assumed

Live research confirms the real 2025-2026 state of practice: AI-agent code
-execution sandboxes are built from **gVisor** (software syscall
interception) or **microVMs** (Firecracker, "used by roughly 50% of
Fortune 500 companies for AI agent workloads") — both running on ordinary,
unmodified x86/ARM hardware. A real, current, escalating threat backs the
need: frontier-model success on cybersecurity tasks rose from under 10%
(late 2023) to roughly 50% (2025), and a 2025 Veracode report found 45% of
AI-generated code fails security tests. Cold-start speed is a real,
named operational requirement (top platforms target under 200ms), since
agentic workflows spin up and tear down many short-lived sandboxes.

## The critical, narrowing question: what kind of bug does the "45% fails security tests" figure actually mean?

Most AI-generated and AI-agent-orchestrated code today is Python or
JavaScript — memory-safe at the language level. A logic bug or an
insecure API call in that code is a real problem, but it is **not** the
class of bug Veda-Core's object-centric bounds/ownership model addresses
at all. Claiming Veda-Core makes "AI-generated code safe" in general would
be exactly the kind of overclaim this analysis must avoid.

## Where the real fit actually is — verified with current, active CVEs, not hypothetical

The real question is not "is the AI's Python code safe" but **"is the
native runtime that enforces the sandbox boundary itself safe."** This
year's own real vulnerability record answers that directly: V8 (Chrome's
JavaScript engine, written in C++, the same class of runtime used to
execute untrusted/agent-generated code in many real sandboxes) has had
multiple 2024-2025 CVEs — **CVE-2024-7965** (heap corruption granting
arbitrary memory read/write inside the renderer, chained into a sandbox
escape), **CVE-2025-5419** (critical, 9.6-severity type confusion enabling
out-of-bounds access and sandbox escape, actively exploited in the wild),
**CVE-2025-10585** and **CVE-2025-13223** (further type-confusion RCE,
also actively exploited) — all describing the identical real pattern: a
native C++ runtime's own heap-management bug lets code that was supposed
to stay inside the sandbox corrupt adjacent memory and escape it. This is
precisely the vulnerability shape `SECURITY_COMPARISON_STUDY.md` already
demonstrated Veda-Core's hardware bounds/ownership enforcement blocks, on
real RTL, this session.

## Verdict — a narrower, more precise, and more defensible claim than "AI agent safety"

Veda-Core's real contribution to this domain is not "restricting what an
AI agent can do" (that is a policy/permissions problem, resolved today at
the OS/orchestration layer — filesystem namespaces, network egress
control, credential scoping — none of which a memory-object capability
ISA changes). It is: **hardening the native, C/C++-class sandbox/runtime
implementation itself against exactly the heap-corruption and
type-confusion bug class that has, this year, repeatedly and actively
been used to escape real production sandboxes.** OCInvoke and PCC
compartment bounding (Milestones 10 and 14, already real and verified)
are the concrete mechanism: if a sandbox/interpreter runtime's own trusted
code ran as a Veda-Core object-centric program, an attacker-triggered
heap-corruption bug in *that* runtime would hard-trap instead of silently
corrupting adjacent sandbox state — the same real property already shown
in this session's own OOB-write experiment.

This is structurally the *same* finding as Domain 1 (Confidential
Computing): Veda-Core hardens the trusted implementation of an isolation
boundary against being broken from inside by its own memory bugs — it
does not replace the policy/orchestration layer above it. A real,
consistent pattern across two independently-researched domains, not
coincidence.

## Honest gaps

- No Veda-Core port of any real interpreter/runtime (V8, a WASM engine,
  Python's CPython) exists or has been attempted — this is a large,
  real, unstarted engineering effort, not a small step.
- OS-level resource isolation (filesystem, network, credentials) is
  outside what this architecture's memory-object model addresses at all;
  a real deployment would still need gVisor/Firecracker-class isolation
  *alongside* Veda-Core, not instead of it.
- Cold-start speed (a real, named requirement for this domain) was never
  measured for OCInvoke at any realistic scale — this session's own
  cycle counts are for single, small compartment entries, not a full
  runtime bring-up.

## Sources

- [Best Code Execution Sandboxes for AI Agents in 2026 (Modal)](https://modal.com/resources/best-code-execution-sandboxes-ai-agents)
- [AI Agent Sandbox: How to Safely Run Autonomous Agents in 2026 (Firecrawl)](https://www.firecrawl.dev/blog/ai-agent-sandbox)
- [CVE-2024-7965: Google Chrome V8 RCE Vulnerability](https://www.sentinelone.com/vulnerability-database/cve-2024-7965/)
- [CVE-2025-5419 - V8 Out-of-Bounds Read/Write Vulnerability](https://dev.to/abhinavsingwal/cve-2025-5419-google-chrome-v8-engine-out-of-bounds-readwrite-vulnerability-36bi)
- [Inside Chrome's 2025 Vulnerability Landscape (80 CVEs in V8 and Core Components)](https://blog.quttera.com/post/inside-chrome-80-vulnerabilities-since-jan-2025)
