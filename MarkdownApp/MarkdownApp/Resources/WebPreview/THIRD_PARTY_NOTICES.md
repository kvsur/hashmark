# Web preview third-party components

The preview renderer ships the following components locally so Markdown rendering remains available offline:

- Mermaid 11.16.1 — MIT — https://github.com/mermaid-js/mermaid
- KaTeX 0.17.0 — MIT — https://github.com/KaTeX/KaTeX
- marked-katex-extension 5.1.10 — MIT — https://github.com/UziTech/marked-katex-extension

Their complete license texts are included in `ThirdPartyLicenses/`.

KaTeX 0.17.0 is intentionally pinned because marked-katex-extension 5.1.10 declares compatibility with KaTeX versions `>=0.16 <0.18`.
