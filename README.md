# agent-skills-installer

team-upgrade 사내 Claude Code / Codex 스킬 설치 스크립트.

실제 스킬 본문은 프라이빗 레포 [`team-upgrade/agent-skills`](https://github.com/team-upgrade/agent-skills)에 있고, 이 레포는 **공개 부트스트랩 설치 스크립트**만 제공합니다.

## 설치

터미널에 아래 한 줄을 붙여넣기:

```bash
curl -sSL https://raw.githubusercontent.com/team-upgrade/agent-skills-installer/main/install.sh | bash
```

설치 중 두 가지 토큰을 입력받습니다 — 둘 다 1Password 공유 vault에 있습니다.

1. **GitHub PAT** — `agent-skills` 레포 read 권한. vault 항목: `agent-skills GH PAT`
2. **Upgrade API 토큰** — 백엔드 에이전트 API 호출용. vault 항목: `Upgrade Agent API Token`

## 설치되는 것

- `~/.agents/skills/<skill-name>/` — 스킬 본문 (agent-skills 레포의 `skills/*`)
- `~/.claude/skills/<skill-name>` → 위 경로로의 심링크
- `~/.zshrc` (또는 쉘에 맞는 rc 파일)에 `export UPGRADE_API_TOKEN="..."`

## 업데이트

같은 커맨드를 다시 실행하세요. 최신 스킬을 다시 받아 덮어쓰고, 토큰도 다시 저장합니다.

## 토큰 교체

토큰이 로테이션되면 재실행 후 새 값을 입력하면 됩니다. `~/.zshrc`의 기존 `UPGRADE_API_TOKEN` 라인은 자동으로 교체됩니다.

## 문제 해결

- **`command not found: curl/tar`** — 맥 기본 내장이므로 거의 발생하지 않음. Xcode Command Line Tools 설치: `xcode-select --install`
- **`GH_TOKEN 인증 실패`** — 1Password에서 PAT를 다시 복사. 만료됐다면 관리자에게 문의.
- **설치 후에도 스킬이 안 뜸** — Claude Code를 완전히 재시작. 그래도 안 되면 `ls ~/.claude/skills/` 로 심링크 확인.

## 관련 레포

- **이 레포 (public)**: 부트스트랩 설치 스크립트만
- **[team-upgrade/agent-skills](https://github.com/team-upgrade/agent-skills) (private)**: 실제 스킬 본문 (`skills/upgrade-api/`, 등)
