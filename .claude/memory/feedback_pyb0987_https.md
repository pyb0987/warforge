---
name: pyb0987 HTTPS 연결
description: pyb0987 GitHub 계정은 SSH가 아닌 HTTPS 프로토콜로 연결됨
type: feedback
---

pyb0987 계정으로 GitHub push 시 HTTPS URL 사용.
SSH는 youngbinyeongbin 계정에 연결되어 있어 pyb0987 repo에 push 불가.

**Why:** gh repo create가 SSH로 remote를 설정하면 permission denied 발생.
**How to apply:** pyb0987 repo 생성/push 시 `git remote set-url origin https://github.com/pyb0987/...` 로 전환 후 push.
