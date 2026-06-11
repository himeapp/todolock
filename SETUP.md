# TodoLock — Xcode 셋업 가이드

이 프로젝트는 [XcodeGen](https://github.com/yonaskolb/XcodeGen)으로 `.xcodeproj`를
생성합니다. 타깃·번들ID·entitlements·App Group·익스텐션 설정은 모두
[project.yml](project.yml)에 선언돼 있어, 소스를 추가/이동해도 `xcodegen generate`
한 번이면 프로젝트가 재구성됩니다.

## 0. 사전 준비

- **Xcode 15+** (iOS 17 SDK 필요. SwiftData가 iOS 17+, Family Controls는 16+)
- **Apple Developer Program** 멤버십 (Family Controls capability는 유료 계정에서만 enable 가능)
- **iOS 17+ 실기기** (Family Controls는 시뮬레이터에서 정상 동작하지 않음)
- **XcodeGen**: `brew install xcodegen`

## 1. 프로젝트 생성

레포 루트(`project.yml`이 있는 곳)에서:

```sh
xcodegen generate
```

`TodoLock.xcodeproj`가 만들어지고 4개 타깃이 구성됩니다:

| 타깃 | 종류 | 번들 ID |
|---|---|---|
| `TodoLock` | App | `com.todolock` |
| `ShieldConfiguration` | App Extension | `com.todolock.ShieldConfiguration` |
| `ShieldAction` | App Extension | `com.todolock.ShieldAction` |
| `ActivityMonitorExtension` | App Extension | `com.todolock.ActivityMonitor` |

project.yml이 자동으로 연결해 주는 것:
- 각 타깃의 entitlements (Family Controls + App Group `group.com.todolock.shared`)
- 익스텐션 3개의 `NSExtensionPointIdentifier` / `NSExtensionPrincipalClass`
- 메인 앱의 URL scheme `todolock` (`todolock://task?sessionId=...` 딥링크)
- `NSUserNotificationsUsageDescription` privacy 설명
- 익스텐션을 메인 앱에 자동 임베드

> **Shield 익스텐션이 둘로 나뉜 이유**: `ShieldConfigurationExtension`(잠금화면 UI 구성)과
> `ShieldActionExtension`(잠금화면 버튼 처리)은 서로 다른 extension point라 하나의 타깃에
> 담을 수 없습니다. 그래서 `ShieldConfiguration` / `ShieldAction` 두 타깃으로 분리돼 있습니다.

## 2. 서명(Signing) 설정 — Xcode에서 수동

`xcodegen`은 코드 서명 팀을 채우지 못하므로 한 번은 직접 지정해야 합니다.

1. `TodoLock.xcodeproj` 열기
2. **4개 타깃 모두** → `Signing & Capabilities` → **Team**을 본인 개발자 계정으로 선택
   - 또는 [project.yml](project.yml)의 `settings.base.DEVELOPMENT_TEAM`에 팀 ID를 넣고
     `xcodegen generate` 재실행 (이러면 매번 재생성해도 유지됨)
3. `Automatic` 서명이면 Xcode가 provisioning profile을 자동 생성

## 3. Family Controls Capability 승인

- entitlements에 `com.apple.developer.family-controls`가 이미 들어 있습니다.
- 이 capability는 Apple 승인이 필요할 수 있습니다 — 개발용 provisioning은 보통 바로 되지만,
  배포용은 [별도 신청](https://developer.apple.com/contact/request/family-controls-distribution/)이 필요합니다.

## 4. 빌드 & 실제 디바이스에 설치

- 실기기 연결 후 `TodoLock` 스킴 빌드/실행
- 첫 실행 → "권한 허용" → iOS의 Screen Time 권한 다이얼로그
- 앱 열면 바로 **리모컨 화면**: 숫자패드로 MMSS 입력 / 시간 ▲▼ / 모드 프리셋(공부모드·출근길·잘때) /
  잠글 앱 관리 / 점프(과업 설정) / 시작
- 시작 → 선택한 앱 잠금 적용
- 잠긴 앱 열기 → 우리 Shield 화면이 떠야 함
- "과업 수행" 버튼 → 알림 → 알림 탭 → 메인 앱이 과업 화면으로 진입

## 5. 컴파일만 검증 (서명 없이, 시뮬레이터)

실기기 없이 코드 정합성만 확인할 때:

```sh
xcodebuild build -project TodoLock.xcodeproj -scheme TodoLock \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

> Family Controls는 시뮬레이터에서 실제로 동작하지 않으므로, 이 단계는 **컴파일 가능 여부**만
> 검증합니다. 실제 잠금/Shield 동작은 4번(실기기)에서만 확인됩니다.

## 6. 디버깅 체크리스트

- Shield가 안 뜸 → Family Controls 권한이 `approved`인지, ManagedSettingsStore에 applications가 nil이 아닌지 확인
- Shield 버튼 눌러도 무반응 → `ShieldAction` 타깃이 잘 임베드됐는지, Info.plist의 PrincipalClass 확인
- 세션이 자동 만료 안 됨 → `ActivityMonitorExtension`의 PrincipalClass, App Group에 sessionId가 들어가는지 확인
- 익스텐션이 권한/그룹 못 읽음 → 4개 타깃 모두 같은 Team으로 서명됐고 App Group이 동일한지 확인

## 알려진 한계

- 사용자가 앱을 삭제하면 ManagedSettings 자체는 해제되지 않을 수 있으나 우리 앱에서 관리 불가
- Shield Action에서 직접 메인 앱을 열 수 없어 알림으로 우회 (Apple이 권장하는 패턴)
- 17세 미만 사용자는 보호자 승인 흐름으로 진행되어 MVP 흐름과 다름
