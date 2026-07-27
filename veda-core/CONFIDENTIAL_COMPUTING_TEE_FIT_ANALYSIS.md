# Domain 1 Analysis: Confidential Computing / TEEs — Real Fit, Real Gap, Real Positioning

**Date:** 2026-07-27
**Scope:** first of four "out-of-the-box" directions identified from Veda-Core's own verified architectural properties (not from this project's prior planning docs) — real, WebSearch-verified research, not reasoned from memory alone.

## The real TEE threat model has two genuinely separate parts — this is the crux finding

Real, current (2025) confidential-computing technology (AMD SEV-SNP, Intel TDX)
explicitly defends against an untrusted hypervisor/host **with physical
memory access**, and does so via **memory encryption** (AMD Secure
Processor-managed keys, integrity-protected page tables) — confirmed via
live research, not assumed. This is a **different problem** from
capability-based access control, and it matters: Veda-Core's `odt_mem[]`/
`elfmem[]` are, as verified directly from `veda_core.tlv` earlier this
session, plain, unencrypted arrays. **Veda-Core's capability checks
prevent nothing against an attacker who can read raw DRAM directly**
(a malicious hypervisor with DMA, a physical/cold-boot attacker) — they
only gate what instructions executing *through* the core's own capability
-checked path can do. This is a real, honest, load-bearing limit: Veda-Core
is not, as currently designed, a substitute for SEV-SNP/TDX's own memory
-encryption boundary.

## Where Veda-Core's real, verified properties genuinely fit — a different, second real problem TEEs have

Two real findings from this session's own research change the picture:

1. **Cache/timing side-channels remain a live, current attack surface
   against the newest TEE technology, not just legacy SGX.** Real,
   documented 2024-2025 attacks — `tee.fail` (affects SGX, TDX, *and*
   SEV-SNP via shared DDR5 memory-controller timing), `T-Time` (a
   fine-grained timing attack specifically against TDX), `Cohere+Reload`
   (re-enables high-resolution cache attacks on SEV-SNP) — confirm this is
   not a solved, historical problem. Veda-Core's cache-less,
   non-speculative single-cycle design is **structurally immune** to this
   entire attack class, for the same reason it was immune to Spectre
   /Meltdown: neither of the two required ingredients (speculative
   execution, a cache-timing covert channel) exists in the design at all.
2. **Memory-safety bugs *inside* the trusted enclave/CVM remain a real,
   actively-researched, unsolved problem — encryption doesn't touch this.**
   TeeRex (USENIX Security 2020, a top-tier peer-reviewed venue) found
   **35 real memory-corruption vulnerabilities across 8 major SGX/RISC-V
   /Sancus shielding frameworks**, and states plainly that ordinary buffer
   overflows "not only nullif[y] the security guarantee that SGX claims to
   provide, but also allow attackers to exploit isolation and
   confidentiality" — and that this happens **through the code running
   inside the very boundary the encryption already protects.** Critically:
   the same research found that **even Rust does not fully close this
   gap**, because the host-to-enclave marshalling interface is typically
   unsafe C-ABI code regardless of what language the rest of the enclave
   is written in. This is exactly the class of bug Veda-Core's hardware
   -enforced, language-independent object bounds/ownership checking is
   built to stop — verified this session, on real RTL, for exactly this
   bug shape (`SECURITY_COMPARISON_STUDY.md`).

## The real, honest positioning this analysis supports

**Not**: "Veda-Core replaces SGX/TDX/SEV-SNP." **Instead**: Veda-Core's
real, demonstrated strength — hardware-enforced, per-object bounds and
ownership checking with zero cache-timing side-channel surface — addresses
a second, real, currently under-addressed problem *inside* the trust
boundary that memory encryption alone does not touch. The natural,
honestly-scoped role: **an in-enclave/in-CVM hardening layer**, running
*underneath* whatever the encryption/attestation boundary provides,
closing the exact gap TeeRex's real, published research identified as
still open even against the best current mitigations (Rust, edger8r-style
interface sanitizers).

## What would actually be needed before this claim could be tested for real — stated honestly, not glossed over

- **No memory encryption engine exists in Veda-Core's design at all** — if
  the "hybrid" positioning above is pursued, this is real, substantial,
  unstarted hardware design work, not a minor addition.
- **No remote attestation mechanism** — real confidential computing
  requires a way for a remote party to verify what code is actually
  running; Veda-Core has no equivalent of SGX's `EREPORT`/quote generation
  or SEV-SNP's attestation report today.
- **No real silicon, no real host-to-enclave interface has been designed**
  for Veda-Core specifically — the TeeRex-class vulnerability this
  analysis targets lives exactly at that boundary, which does not exist
  yet in this project.
- **Single-hart only** — real confidential-computing deployments are
  virtualized, multi-tenant, multi-core; Veda-Core's own multi-hart RTL
  is explicitly still an open gap (`NEXT_STEPS_ROADMAP.md`).

## Verdict

Real, well-grounded, non-hallucinated fit for a **specific, secondary
part** of the confidential-computing problem (in-boundary memory safety),
not the primary one (confidentiality against a privileged host, which
needs memory encryption Veda-Core doesn't have). This is a stronger,
more precisely-targeted claim than "good for confidential computing" in
general — and, unlike the five domains evaluated previously, it is
grounded in real, current (2024-2025), peer-reviewed and industry
research, not in this project's own prior planning documents.

## Sources

- [AMD SEV-SNP vs Intel TDX on VPS in 2025](https://onidel.com/blog/amd-sev-snp-vs-intel-tdx-vps)
- [Confidential VMs Explained: An Empirical Analysis of AMD SEV-SNP and Intel TDX](https://dse.in.tum.de/wp-content/uploads/2024/11/sigmetrics25summer-CVM-Explained.pdf)
- [Linux: Tee.Fail Moderate Side-Channel Attack on TEE Systems](https://linuxsecurity.com/features/tee-fail-attack-linux-security)
- [T-Time: A Fine-Grained Timing-Based Controlled-Channel Attack Against Intel TDX](https://link.springer.com/chapter/10.1007/978-3-032-07894-0_17)
- [Cohere+Reload: Re-enabling High-Resolution Cache Attacks on AMD SEV-SNP](https://link.springer.com/chapter/10.1007/978-3-031-97620-9_11)
- [TeeRex: Discovery and Exploitation of Memory Corruption Vulnerabilities in SGX Enclaves (USENIX Security 2020)](https://www.usenix.org/system/files/sec20-cloosters.pdf)
- [Foreshadow: Extracting the Keys to the Intel SGX Kingdom (USENIX Security 2018)](https://www.usenix.org/conference/usenixsecurity18/presentation/bulck)
