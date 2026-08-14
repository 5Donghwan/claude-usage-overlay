# ClaudeUsageOverlay

Claude 데스크톱 앱의 채팅 입력창 위에 5시간/주간 사용량 바를 항상 표시하는 오버레이.

> 비공식 개인 프로젝트로, Anthropic과 무관하다 (Not affiliated with or endorsed by
> Anthropic). "Claude"·"Anthropic"은 Anthropic, PBC의 상표다. 자세한 조건은
> [LICENSE](LICENSE) 참고.

![스크린샷: Claude 입력창 아래 5h / 7d / Fable 사용량 바](docs/screenshot.png)

- Claude.app은 전혀 수정하지 않는다. 별도 백그라운드 앱(NSPanel)이 위에 겹쳐 그린다.
- 데이터: `~/Library/Application Support/Claude/plan-usage-history.json` —
  Claude 앱 자신이 5분마다 갱신하는 파일 (`u.fh` = 5시간 %, `u.sd` = 주간 %).
  API 호출·스크래핑 없음. 90분 이상 오래된 샘플은 `--`로 표시.
- 바는 **2개(`5h`/`7d`)** 또는 **3개(+ 모델별 한도)** 중에 고를 수 있다.
  기본은 3개이며, 바꾸는 법은 아래 "바 2개 vs 3개" 참고.
- 위치: 접근성(AX) API로 Claude 창의 입력창 좌표를 0.1초마다 읽어 자동 추적.
  창 이동/리사이즈, 우측 패널 크기 변경, 입력창 여러 줄 확장 모두 따라감.
- Claude가 맨 앞 앱일 때만 표시. 클릭은 전부 통과(입력창 조작 방해 없음).

## 요구사항

- macOS 14 이상
- Xcode Command Line Tools (`swift build`가 되면 충분 — `xcode-select --install`)
- Node.js (폰트를 Claude 앱과 동일하게 맞추고 싶을 때만 필요, 선택)
- `zstd` (모델별 한도 바를 쓰고 싶을 때만 필요, 선택 — `brew install zstd`)
- Claude 데스크톱 앱이 `/Applications/Claude.app`에 설치돼 있을 것

## 빌드 & 실행

```bash
git clone <this-repo>
cd claude-usage-overlay
./build.sh
open dist/ClaudeUsageOverlay.app
```

첫 실행 시 손쉬운 사용(Accessibility) 권한을 요청한다:
시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 → ClaudeUsageOverlay 켜기.
권한을 주면 재시작 없이 몇 초 안에 동작한다.

**주의:** 재빌드하면 ad-hoc 서명이 바뀌어 권한을 다시 켜야 할 수 있다.
그래서 배치·크기 조정은 재빌드 없이 `tunables.json`으로 한다.

폰트를 추출하지 않고 실행하면 시스템 기본 폰트로 표시된다 (동작에는 문제없음,
아래 "폰트" 섹션 참고).

## 미세 조정 (tunables.json)

기본값은 Claude 앱 자체의 컴포저 툴바(모델명·effort 표시)와 맞춰 이미 보정되어
있다. 다르게 쓰고 싶으면 프로젝트 루트에 `tunables.json`을 만든다 — 15초 안에
반영된다 (재시작 불필요, `.gitignore`에 포함되어 있어 커밋되지 않는 개인 설정
파일이다). 바꾸고 싶은 필드만 적으면 되고, 나머지는 기본값을 그대로 쓴다:

```json
{
  "centerAboveBottom": 25,
  "scale": 0.9
}
```

전체 필드와 기본값:

| 필드 | 기본값 | 설명 |
|---|---|---|
| `barW` | 86 | 바 하나의 가로 길이 |
| `groupGap` | 18 | 5h 그룹과 7d 그룹 사이 간격 |
| `panelH` | 30 | 오버레이 전체 높이 |
| `scale` | 1.0 | 전체 시각 배율 |
| `centerAboveBottom` | 19 | 입력창 컨테이너 하단 → 오버레이 세로 중심 거리(px). 키우면 위로, 줄이면 아래로 이동 |
| `titleFont` | `AnthropicSansVariable-TextRegular` | "5h"/"7d" 라벨 폰트 (PostScript 이름) |
| `valueFont` | `AnthropicSansVariable-TextRegular` | 퍼센트 수치 폰트 |
| `titleSize` | 12 | 라벨 크기 |
| `valueSize` | 12 | 수치 크기 |
| `showModelLimits` | true | 모델별 주간 한도 바 표시 (아래 참고). `false`면 5h/7d만 |

`titleFont`/`valueFont`로 지정 가능한 이름은 `scripts/extract-fonts.mjs` 실행 후
`AnthropicSansVariable-Text{Regular,Medium,Semibold,Bold,Extrabold,Light}`
(Italic 계열도 동일 패턴). 폰트를 추출하지 않았다면 이 값은 무시되고 시스템 폰트로
자동 대체된다.

## 바 2개 vs 3개

| | 표시 | 설정 | 추가 조건 |
|---|---|---|---|
| **3개 (기본)** | `5h` `7d` `Fable` | 그대로 두면 된다 | `zstd` 필요 (`brew install zstd`) |
| **2개** | `5h` `7d` | `tunables.json`에 아래 한 줄 | 없음 |

2개만 쓰려면 프로젝트 루트에 `tunables.json`을 만들고:

```json
{ "showModelLimits": false }
```

15초 안에 반영되고 재빌드·재시작은 필요 없다. 다시 3개로 돌리려면 `true`로 바꾸거나
그 줄을 지우면 된다.

3개로 두고 싶은데 세 번째 바가 안 뜬다면 대부분 아래 둘 중 하나다:

- **`zstd`가 없다** → `brew install zstd` 후 몇 초 기다린다
- **플랜에 모델별 한도가 없다** → 이 경우엔 바가 뜰 수 없다. 표시할 값 자체가 없으므로
  2개 구성이 정상이다

어느 쪽이든 `5h`/`7d`는 영향받지 않는다. 확인은 로그로:

```bash
grep "model limits" ~/Library/Logs/ClaudeUsageOverlay.log
```

## 모델별 한도가 동작하는 방식

플랜에 모델별 주간 한도가 걸려 있으면 `5h`/`7d` 옆에 모델 이름이 붙은 바가 자동으로
하나 더 생긴다 (예: `Fable 49%`). 모델이 여러 개면 그만큼 바가 늘어나고, 새 모델이
추가돼도 서버가 내려주는 이름을 그대로 쓰므로 코드 수정 없이 따라간다.

**이 값만 데이터 출처가 다르다.** Claude 앱은 `/api/organizations/<org>/usage` 응답의
`limits[]` 배열로 이 수치를 받는데, `plan-usage-history.json`에는 저장하지 않는다
(레거시 고정 키 8개만 저장하고, 모델별 항목은 전부 `null`로 내려온다). 그래서 이
바만은 Chromium HTTP 캐시(`~/Library/Application Support/Claude/Cache/Cache_Data`)에
남은 **응답 본문**을 읽는다. 쿠키·토큰 등 인증 정보는 일절 건드리지 않으며, 읽기
전용이고 네트워크 요청도 하지 않는다.

캐시 본문은 보통 **zstd** 압축인데 macOS는 zstd를 기본 제공하지 않는다 (Compression
프레임워크에 없고 시스템 libzstd도 없음). 앞서 말한 `brew install zstd`가 필요한 게
이 때문이다.

이 경로는 전 구간이 best-effort로 짜여 있다 — `zstd` 부재, 캐시 형식 변경, 항목 만료,
해제 실패 등 무엇이 어긋나도 이 바만 조용히 사라지고 `5h`/`7d`에는 영향이 없다.
Chromium 캐시 형식은 비공개라 Claude 앱 업데이트로 깨질 수 있는데, 그때도 마찬가지다.

## 폰트

오버레이 텍스트를 Claude 앱과 동일한 서체(Anthropic Sans)로 맞추려면:

```bash
node scripts/extract-fonts.mjs
```

**로컬에 설치된 자신의 Claude.app**에서 폰트 파일(app.asar 내부)을 읽어 `fonts/`에
저장하는 스크립트다. 앱은 실행 시 이 폴더의 폰트를 프로세스 스코프로만 등록하므로
시스템에는 설치되지 않는다.

`fonts/`는 `.gitignore`에 포함되어 있고 **절대 커밋·배포하면 안 된다** — Anthropic
소유의 라이선스 폰트를 각자 자기 컴퓨터에서 추출하는 것이지, 재배포가 아니다.
이 저장소를 포크하거나 클론한 사람은 각자 위 스크립트를 한 번 실행하면 된다.
실행하지 않아도 앱은 정상 동작하고, 대신 시스템 기본 폰트로 표시된다.

Claude 앱 업데이트로 내부 파일명이 바뀌면 스크립트가 폰트를 못 찾을 수 있다 —
그 경우 `scripts/extract-fonts.mjs`의 정규식(`AnthropicSans.*\.ttf`)을 새 파일명에
맞게 수정하면 된다.

## 로그인 시 자동 시작

```bash
./install-launchagent.sh
```

현재 체크아웃 경로를 그대로 넣은 LaunchAgent를 생성해 등록한다 (먼저 `./build.sh`
필요). 해제:

```bash
launchctl unload ~/Library/LaunchAgents/local.claude-usage-overlay.plist
rm ~/Library/LaunchAgents/local.claude-usage-overlay.plist
```

## 종료 / 삭제

```bash
pkill -f ClaudeUsageOverlay.app
```

삭제는 이 폴더와 (등록했다면) LaunchAgent plist, 손쉬운 사용 목록 항목을 지우면 끝.

## 진단

- 로그: `~/Library/Logs/ClaudeUsageOverlay.log`
- AX 트리 확인: `dist/ClaudeUsageOverlay.app/Contents/MacOS/ClaudeUsageOverlay --probe`
  (입력창 탐지 휴리스틱이 뭘 골랐는지 출력)
