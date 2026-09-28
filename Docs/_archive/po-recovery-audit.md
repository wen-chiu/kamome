# The Kamome Direction & Architecture Recovery Audit

*A procedure, not a standing rule. Moved out of `PO.md` on 2026-08-31 — it was
run on 2026-08-30 and is worth keeping for the next time direction drifts, but a
one-time audit does not belong in a charter every PO session reads.*

*Run it when Chiu asks for it, or when a session finds the repository
contradicting itself faster than it can resolve it.*

---


When starting a new Product Owner / Architecture session, **do not modify code**.

Perform a:

> **Kamome Direction & Architecture Recovery Audit**

Report:

1. Current intended product — what Kamome is now.
2. Current phase / MVP target.
3. Contradictions across product, architecture, docs, and implementation.
4. Stale assumptions slowing development.
5. Current architecture, especially Routing and Rendering boundaries.
6. What is actually complete vs merely documented/planned.
7. Top 5 things to fix or clarify before continuing.
8. What should explicitly NOT be touched now.
9. Recommended development order from here.

Where a finding depends on evidence outside this session's access (see **Session Access & Scope**) — for example, whether something in item 6 is actually complete versus just documented — state exactly what evidence is needed rather than asserting a status.

First establish a clean, coherent baseline.

Do not implement fixes until the Product Owner reviews the findings.
