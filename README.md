# agent-skills-installer

team-upgrade 사내 에이전트 스킬 설치 스크립트. 실제 설치는 [`vercel-labs/skills`](https://github.com/vercel-labs/skills)(`npx skills`)에 위임하므로 Claude Code / Codex / OpenClaw / Gemini CLI 등 **45+ 에이전트**에 대응합니다.

실제 스킬 본문은 프라이빗 레포 [`team-upgrade/agent-skills`](https://github.com/team-upgrade/agent-skills)에 있고, 이 레포는 **공개 부트스트랩 스크립트**만 제공합니다.

## 사전 요구사항

- **Node.js** — `npx`가 필요합니다. 없으면: `brew install node` 또는 https://nodejs.org

## 설치

### 인터랙티브 (권장)

```bash
curl -sSL https://raw.githubusercontent.com/team-upgrade/agent-skills-installer/main/install.sh | bash
```

토큰 2종 입력받은 뒤 `npx skills`가 자체 TUI로 스킬·에이전트 선택을 안내합니다.

### 특정 스킬만

```bash
curl -sSL .../install.sh | bash -s -- upgrade-api
```

### 스킬·에이전트 지정 + 비대화식

```bash
curl -sSL .../install.sh | bash -s -- upgrade-api -a claude-code -a codex -y
```

### 사용 가능한 스킬 목록 확인

```bash
curl -sSL .../install.sh | bash -s -- -l
```

## 입력받는 것

1. **GitHub PAT** — `agent-skills` 레포 read 권한 (classic `repo` 스코프)
2. **Upgrade API 토큰** — 백엔드 에이전트 API 호출용

한 번 입력하면 rc 파일(`~/.zshrc` 등)에 저장되어 다음 실행부터는 자동으로 쓰입니다. GH 토큰은 재실행마다 GitHub에 검증 호출을 보내며, 여전히 유효하면 재입력 없이 통과합니다.

## 인자 포맷

| 인자                         | 의미                                                                                 |
| ---------------------------- | ------------------------------------------------------------------------------------ |
| 위치 인자 (`upgrade-api` 등) | 설치할 스킬 이름 (여러 개 가능)                                                      |
| `-a, --agent <name>`         | 설치할 에이전트 지정 (`claude-code`, `codex`, `openclaw`, `gemini-cli`, `cursor` 등) |
| `-g, --global`               | 전역 설치 — 이 스크립트가 기본으로 추가함                                            |
| `-y, --yes`                  | 확인 프롬프트 건너뛰기                                                               |
| `--all`                      | 모든 스킬 × 모든 에이전트                                                            |
| `--copy`                     | 심링크 대신 복사                                                                     |
| `-l, --list`                 | 스킬 목록만 출력하고 설치 안 함                                                      |

지원 에이전트 전체 목록: [vercel-labs/skills README](https://github.com/vercel-labs/skills#supported-agents)

## 업데이트 / 제거 / 조회

설치 이후엔 `npx skills`를 직접 쓰면 됩니다:

```bash
npx skills list                      # 설치된 스킬 목록
npx skills update upgrade-api        # 특정 스킬 업데이트
npx skills remove upgrade-api        # 제거
```

## 토큰 교체

rc 파일에서 기존 `export AGENT_SKILLS_GH_TOKEN=...` / `export UPGRADE_API_TOKEN=...` 라인을 삭제한 뒤 스크립트를 다시 실행하면 새 값을 입력받습니다.

## 문제 해결

- **`Node.js/npx가 필요합니다`** — `brew install node` 또는 https://nodejs.org 에서 설치.
- **`GH_TOKEN 인증 실패`** — PAT 만료/오입력. 관리자에게 문의.
- **에이전트가 스킬을 못 읽음** — 에이전트 앱 재시작. `npx skills list`로 설치 경로 확인.

## 관련 레포

- **이 레포 (public)**: 부트스트랩 설치 스크립트
- **[team-upgrade/agent-skills](https://github.com/team-upgrade/agent-skills) (private)**: 실제 스킬 본문
- **[vercel-labs/skills](https://github.com/vercel-labs/skills)**: 내부적으로 쓰는 오픈소스 CLI
