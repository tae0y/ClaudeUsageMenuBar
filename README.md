# Claude Usage MenuBar (macOS)

Claude Code 사용량(일간/주간)을 macOS 메뉴바에서 확인하는 SwiftUI 앱입니다.

## 기능
- 메뉴바 타이틀에 일간/주간 사용률 표시 (`D xx% | W yy%`)
- 팝오버에 Daily/Weekly 토큰 사용량 + Progress Bar
- 5분 자동 갱신 + 수동 Refresh
- Organization/Session 자동 탐지 (`~/.claude.json`, Claude/브라우저 쿠키, 환경변수)

## 실행
```bash
cd /Users/bachtaeyeong/Documents/New\ project/ClaudeUsageMenuBar
swift run ClaudeUsageMenuBar
```

## 자동 탐지 우선순위
- Organization ID: `CLAUDE_ORGANIZATION_ID` → `~/.claude.json` → Claude 쿠키(`lastActiveOrg`)
- Session Key: `CLAUDE_SESSION_KEY` → Claude/브라우저 쿠키(`sessionKey` 등)

앱은 `https://claude.ai/api/organizations/{orgId}/usage`를 호출합니다.

## 참고
- Claude API/웹 응답 스키마는 계정 상태에 따라 달라질 수 있어, 여러 필드명을 유연하게 파싱하도록 구현했습니다.
- 쿠키 값이 OS 암호화 상태면 자동 탐지가 실패할 수 있습니다. 이때는 환경변수(`CLAUDE_ORGANIZATION_ID`, `CLAUDE_SESSION_KEY`)로 실행하면 됩니다.
