# CI & 배포 (TestFlight)

브랜치 전략, 테스트 CI, TestFlight 자동 배포를 정리한다.

## 브랜치 전략 — 트렁크 기반 + 릴리스 태그

- **`master` = 트렁크.** 항상 배포 가능한 상태를 유지한다. 평소 작업은 여기로 머지.
- **기능 브랜치는 짧게** (`feat/...`, `fix/...`). 큰 작업만 브랜치를 따고, 끝나면 바로 master로.
- **출시 = 태그를 다는 행위.** master가 낼 만한 상태일 때 버전 태그를 푸시하면 그때만 배포가 돈다.
- **핫픽스도 master에서.** 고치고 → 다음 패치 태그(`v1.1.1`).

역할이 이렇게 갈린다: **브랜치 = 개발 중, 태그 = 이 커밋을 출시.**

## 두 개의 워크플로

| 워크플로 | 트리거 | 하는 일 |
|---|---|---|
| `.github/workflows/ci.yml` | master 푸시 / PR | 프로젝트 재생성 후 전체 테스트 (`fastlane test`) |
| `.github/workflows/deploy.yml` | `v*` 태그 푸시 | 태그↔버전 확인 → Release 아카이브 → **TestFlight 업로드** (`fastlane beta`) |

App Store **최종 심사 제출은 수동**으로 남긴다. deploy는 TestFlight까지만 올린다.

## 릴리스 방법

1. `app/Project.swift`의 `MARKETING_VERSION`을 낼 버전으로 맞춘다 (예: `1.1.0`).
2. master에 반영하고 태그를 푼다:
   ```bash
   git tag v1.1.0
   git push origin v1.1.0
   ```
3. 태그 이름(`v1.1.0`)과 `MARKETING_VERSION`(`1.1.0`)이 다르면 배포가 **시작 전에 멈춘다** (deploy.yml의 확인 단계).
4. 빌드 번호(`CURRENT_PROJECT_VERSION`)는 CI가 자동으로 "TestFlight의 해당 버전 최고 빌드 + 1"로 넣는다. Project.swift의 빌드 번호는 로컬 아카이브용 기본값일 뿐, 배포 때는 덮어쓴다.
5. 업로드가 끝나면 App Store Connect → TestFlight에서 확인하고, 낼 때 직접 심사 제출.

## 준비물 — GitHub Secrets (직접 등록)

민감한 값이라 저장소에 넣지 않는다. **Settings → Secrets and variables → Actions**에 등록한다.

| Secret | 값 |
|---|---|
| `ASC_KEY_ID` | App Store Connect API 키의 Key ID |
| `ASC_ISSUER_ID` | 같은 페이지의 Issuer ID |
| `ASC_KEY_P8` | `.p8` 키 파일 내용을 base64로 인코딩한 문자열 |

### API 키 만들기

1. App Store Connect → **Users and Access → Integrations → App Store Connect API**.
2. **Team Keys**에서 키 생성. 역할은 **App Manager** 이상.
3. `.p8` 파일을 내려받는다 (한 번만 받을 수 있으니 잘 보관).
4. base64로 변환해서 `ASC_KEY_P8`에 붙여 넣는다:
   ```bash
   base64 -i AuthKey_XXXXXX.p8 | pbcopy
   ```
5. Key ID / Issuer ID를 각 Secret에 넣는다.

이 키만 있으면 비밀번호·2FA 없이 CI가 인증하고, 자동 서명(`-allowProvisioningUpdates`)으로
배포용 인증서와 앱·위젯·워치 프로비저닝 프로파일까지 Xcode가 알아서 만들고 내려받는다.
별도 fastlane match 저장소는 필요 없다.

## 러너에 대한 주의 — Xcode 26+

이 앱은 iOS 26 / watchOS 11을 타깃으로 하므로 **Xcode 26 이상**이 필요하다.
GitHub 호스티드 러너(`macos-15` 등)에 아직 그 Xcode가 없을 수 있다. 그럴 때는:

- **자기 Mac을 self-hosted 러너로 등록**하고 (Settings → Actions → Runners),
  두 워크플로의 `runs-on: macos-15`를 그 러너 라벨로 바꾼다. Xcode 27이 이미 깔린
  이 개발 머신이 가장 확실하다.
- 호스티드 러너에 Xcode 26이 올라오면 `runs-on`을 그대로 두고 `setup-xcode`의
  `xcode-version`만 맞추면 된다.

시뮬레이터 이름(`iPhone 17 Pro`)도 러너의 Xcode가 가진 것으로 `app/fastlane/Fastfile`의
`test` 레인에서 조정한다.

## 로컬에서 배포 테스트

CI를 거치지 않고 수동으로도 같은 레인을 돌릴 수 있다 (자기 Mac, Xcode 27):

```bash
cd app
bundle install
export ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_P8="$(base64 -i AuthKey_XXXX.p8)"
export RELEASE_VERSION=1.1.0
bundle exec fastlane beta
```

## 서명이 불안정하면 — match로 전환

자동 클라우드 서명이 CI에서 간헐적으로 실패하면 [fastlane match](https://docs.fastlane.tools/actions/match/)로
바꾼다: 별도 private 저장소에 인증서/프로파일을 암호화 저장하고, `beta` 레인 앞에
`match(type: "appstore", readonly: true, api_key: api_key)`를 넣은 뒤 `build_app`을
수동 서명으로 돌린다. 지금 구성은 설정이 가장 적은 자동 서명 방식이다.
