# ERA Research Direction

This document records a research direction for studying continuous assurance of safety properties in autonomous tool-using AI systems. It is a research note, not a claim that the listed mechanisms are novel.

Core question: when an agentic system changes its model, tools, context, permissions, delegation structure, or execution horizon, when does previously collected safety evidence stop being trustworthy?

Potential safety properties:
- unauthorized tool invocations are blocked by an enforcement layer
- delegated agents do not gain authority beyond the parent scope
- revoked permissions cannot be used after revocation propagates
- untrusted tool outputs cannot directly expand authority
- safety-relevant policy state survives context reduction
- monitors detect policy violations with measurable latency

The initial benchmark should compare controlled configurations across model version, tool catalogue, context budget, delegation depth, and task horizon. Primary metrics should include unauthorized-action rate, post-revocation action rate, privilege-expansion rate, detection rate, intervention latency, and task success.

The intended research contribution is not a generic agent-security framework. The goal is to measure whether safety guarantees remain valid under realistic system changes and to identify which changes invalidate previous evaluation evidence.
