<!-- template:begin -->
# 에이전트 규칙

이 규칙은 이 저장소에서 일하는 에이전트를 위한 것입니다. 구조와 경계는 [ARCHITECTURE.md](ARCHITECTURE.md) 를 먼저 읽습니다.

## 규칙

1. **앱 만들기:** 새 앱은 `swift run repo new <slug>` 로 만듭니다. (이유: 이 명령이 필요한 파일과 이름, 번들 ID 를 한 번에 맞추고 서식까지 정리합니다.)
2. **한 번에 앱 하나:** 한 작업에서는 `apps/` 아래 앱 하나만 고치고, 앱 사이의 의존은 ARCHITECTURE.md 의 경계 절을 따릅니다. (이유: 앱마다 따로 빌드하고 테스트하고 배포할 수 있어야 하고, 여러 에이전트가 서로 다른 앱을 동시에 고칠 수 있어야 합니다.)
3. **로직은 Core 에:** 로직은 `<Name>Core` 에 두고, GUI 와 CLI 에는 Core 를 호출하는 코드만 둡니다. GUI 로 할 수 있는 일은 CLI 명령으로도 만듭니다. (이유: 에이전트가 화면을 조작하지 않고 CLI 로 동작을 확인할 수 있고, 로직 테스트가 Core 에 모입니다. [결정 0004](decisions/template/0004-core-app-cli-structure.md))
4. **확인:** 변경을 마치면 `swift run repo check <slug>` 를 실행해서 통과시키고, 새 동작에는 Core 테스트를 더합니다. (이유: 이 파일은 check 가 확인하는 서식과 구조 규칙을 되풀이하지 않습니다.)
5. **한 내용은 한 곳에:** 앱 사용법은 그 앱의 `README.md` 에, 결정과 이유는 `decisions/NNNN-제목.md` 에, 변경 기록은 커밋 메시지에, 버전은 `apps/<slug>/VERSION` 에 적습니다. (이유: 두 곳에 적은 내용은 한쪽만 고쳐져서 낡습니다.)
6. **비밀:** API 키, 토큰, 비밀번호는 저장소가 아니라 Keychain 에 보관합니다. (이유: 한 번 커밋된 비밀은 git 이력에서 지우기 어렵습니다.)
7. **외부 패키지:** 외부 SwiftPM 패키지는 꼭 필요할 때만 더하고, 더한 이유를 `decisions/` 에 기록합니다. (이유: 이 저장소는 Xcode 와 git 만 있는 Mac 에서 바로 동작해야 합니다. [결정 0001](decisions/template/0001-no-external-dependencies.md))
8. **공용 패키지는 필요할 때:** 공용 패키지는 두 번째 앱이 같은 코드를 필요로 하는 시점에 만듭니다. (이유: 미리 만든 공용 코드는 쓰이지 않거나 처음 쓴 앱에 맞춰 굳어집니다.)
9. **커밋:** 커밋은 작게 나누고, `git add` 에는 바꾼 파일의 경로를 적습니다. (이유: 여러 에이전트가 한 저장소에서 일할 때 다른 작업의 변경이 섞이지 않습니다.)
10. **템플릿 관리 영역:** `template.json` 이 관리 영역으로 정한 파일과 템플릿 구역은 `swift run repo template update` 로만 바꿉니다. (이유: 관리 영역은 업데이트 때 통째로 교체되므로 직접 고친 내용은 사라집니다. [결정 0002](decisions/template/0002-template-editions-and-file-replacement.md))
11. **문서:** 문서를 새로 쓰거나 고칠 때는 문서 작성 가이드북의 `guides/new-project.md` 절차를 따르고, 한국어 문장은 fluent-korean 지침을 따릅니다. 기능이 바뀌면 설명은 `repo help` 나 앱의 CLI 도움말에 두고, 이 파일에는 관례가 바뀔 때만 규칙을 더합니다. (이유: 이 파일에 기능 설명이 쌓이면 코드와 도움말의 내용을 되풀이하게 되고, 한 번 더한 문장은 잘 지워지지 않습니다. [결정 0003](decisions/template/0003-documentation-standard.md))
12. **블록:** `bricks/` 와 `bricks.lock` 은 `swift run repo brick` 명령으로만 바꾸고, 블록을 고쳐 써야 하면 먼저 `swift run repo brick eject <테넌트>/<앱>` 으로 주인 앱으로 옮깁니다. (이유: 블록은 테넌트의 판에서 받은 코드라서 다음 update 때 교체되고, 고친 내용은 `bricks.lock` 에 기록한 커밋과 어긋납니다. [결정 0005](decisions/template/0005-bricks-from-tenants.md))
13. **테넌트 등록:** `repo.json` 의 `tenants` 에는 저장소 주인이 지시한 테넌트만 등록합니다. (이유: 어느 테넌트의 코드를 믿고 받을지는 저장소 주인이 책임지는 결정입니다.)
14. **생성 블록:** README 와 `index.md` 의 `okf:derived` 블록은 손으로 고치지 않고 `swift run repo okf sync` 로 갱신합니다. (이유: 블록 내용은 VERSION 과 Package.swift 에서 만들어지므로, 손으로 고치면 코드와 어긋나고 다음 sync 때 사라집니다. [결정 0007](decisions/template/0007-lean-okf.md))

## 관련

- 명령과 옵션: `swift run repo help`, 템플릿 업데이트는 `swift run repo help template`, 블록은 `swift run repo help brick`, 생성 블록은 `swift run repo help okf`
- 구조와 경계: [ARCHITECTURE.md](ARCHITECTURE.md)
- 이 파일의 작성 규칙: 규칙마다 이유를 하나 붙이고, 이 저장소의 관례만 적습니다. 출처: https://github.com/dalsoop/stable-agent-documentation-guidebook 의 R-001, R-002
- 한국어 문장 지침: https://github.com/snflkd/fluent-korean
<!-- template:end -->

## 이 저장소의 규칙

이 저장소에만 해당하는 규칙은 이 아래에 적습니다. 위 구역은 템플릿 업데이트 때 교체됩니다.
