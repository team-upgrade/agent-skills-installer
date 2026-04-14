# agent-skills-installer

team-upgrade 사내 에이전트 스킬 설치 스크립트. Claude Code / OpenClaw(Codex) / Hermes 대응.

실제 스킬 본문은 프라이빗 레포 [`team-upgrade/agent-skills`](https://github.com/team-upgrade/agent-skills)에 있고, 이 레포는 **공개 부트스트랩 설치 스크립트**만 제공합니다.

## 설치

터미널에 아래 한 줄을 붙여넣기 (모든 스킬 설치):

```bash
curl -sSL https://raw.githubusercontent.com/team-upgrade/agent-skills-installer/main/install.sh | bash
```

특정 스킬만 설치:

```bash
curl -sSL https://raw.githubusercontent.com/team-upgrade/agent-skills-installer/main/install.sh | bash -s -- upgrade-api
```

여러 스킬:

```bash
curl -sSL .../install.sh | bash -s -- upgrade-api other-skill
```

## 입력받는 것

1. **GitHub PAT** — `agent-skills` 레포 read 권한. 관리자에게 받아서 붙여넣기.
2. **Upgrade API 토큰** — 백엔드 에이전트 API 호출용.
3. **에이전트 환경 선택** — 체크박스로 여러 개 선택 가능:
   - Claude Code (`~/.claude/skills/`)
   - OpenClaw (`~/.codex/skills/`)
   - Hermes (`~/.hermes/skills/`)

숫자 키로 토글, Enter로 완료. 기본값은 Claude Code만 체크.

## 설치되는 것

- `~/.agents/skills/<skill-name>/` — 스킬 본문 (canonical)
- 선택한 에이전트 환경 경로에 심링크
- rc 파일에 `AGENT_SKILLS_GH_TOKEN`, `UPGRADE_API_TOKEN`, `AGENT_SKILLS_TARGETS` 저장

## 재실행 / 업데이트

같은 커맨드를 다시 실행하면:

- 기존 토큰 감지 → `[Y/n]`으로 재사용 또는 재입력
- 이전에 선택한 에이전트 환경이 pre-check된 상태로 체크박스 등장
- 스킬은 최신 버전으로 덮어쓰기

## 토큰 교체

`[Y/n]`에서 `n`을 선택하면 새 토큰을 입력받습니다. rc 파일의 기존 export 라인은 자동 교체됩니다.

## 문제 해결

- **스크립트가 조용히 꺼짐** — 최신 커밋으로 재실행. 문제 지속되면 Slack 채널에 공유.
- **`GH_TOKEN 인증 실패`** — PAT 만료 가능성. 관리자에게 문의.
- **스킬이 에이전트에서 안 보임** — 에이전트 앱을 완전히 재시작. `ls ~/.claude/skills/` (또는 `.codex`, `.hermes`)로 심링크 확인.

## 관련 레포

- **이 레포 (public)**: 부트스트랩 설치 스크립트만
- **[team-upgrade/agent-skills](https://github.com/team-upgrade/agent-skills) (private)**: 실제 스킬 본문
