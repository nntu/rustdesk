# RustDesk Server Program

[![build](https://github.com/rustdesk/rustdesk-server/actions/workflows/build.yaml/badge.svg)](https://github.com/rustdesk/rustdesk-server/actions/workflows/build.yaml)

[**Download**](https://github.com/rustdesk/rustdesk-server/releases)

[**Manual**](https://rustdesk.com/docs/en/self-host/)

[**FAQ**](https://github.com/rustdesk/rustdesk/wiki/FAQ)

[**How to migrate OSS to Pro**](https://rustdesk.com/docs/en/self-host/rustdesk-server-pro/installscript/#convert-from-open-source)

Self-host your own RustDesk server, it is free and open source.

## How to build manually

```bash
cargo build --release
```

Three executables will be generated in target/release.

- hbbs - RustDesk ID/Rendezvous server
- hbbr - RustDesk relay server
- rustdesk-utils - RustDesk CLI utilities

You can find updated binaries on the [Releases](https://github.com/rustdesk/rustdesk-server/releases) page.

If you want extra features, [RustDesk Server Pro](https://rustdesk.com/pricing.html) might suit you better.

If you want to develop your own server, [rustdesk-server-demo](https://github.com/rustdesk/rustdesk-server-demo) might be a better and simpler start for you than this repo.

## Installation

Please follow this [doc](https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/)

## Fork Information & Licensing / Thông tin các bản Fork và Bản quyền

Because RustDesk Server is licensed under the **GNU Affero General Public License v3 (AGPL-3.0)**, anyone is permitted to fork the project.

### Notable Forks / Các bản Fork nổi bật:
- **HopToDesk**: A popular fork that provides free remote desktop services. Early in its lifecycle, it faced community criticism for lack of attribution to the original RustDesk project. It has since diverged technically (relying on WebRTC).
- **Commercial Managed Forks (e.g., Tenvo)**: Managed service providers that package RustDesk Server with commercial support.

If you modify and run this server publicly on a network, please ensure you comply with the AGPL-3.0 requirements by making the source code available to your users.

