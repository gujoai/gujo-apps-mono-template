# __DISPLAY_NAME__

<!-- 이 앱이 무엇이고 왜 있는지 한 문단으로 적습니다. 아래 문단은 템플릿의 기본 기능을 설명하므로, 앱에 맞게 바꾼 뒤 이 주석을 지웁니다. -->
이 앱은 항목을 추가하고 완료 여부를 표시하는 목록 앱입니다. 창에서 제목을 적어 항목을 추가하고, 체크 상자로 완료를 표시하고, 오른쪽 클릭 메뉴로 항목을 지웁니다. 같은 일을 CLI 로도 할 수 있고, 앱이 앞으로 오면 저장 파일을 다시 읽으므로 CLI 로 바꾼 내용이 창에 보입니다.

## 실행

저장소 루트에서 실행합니다.

```sh
swift run repo run __name__             # GUI 를 실행한다
swift run repo bundle __name__ --open   # .app 을 만들어 연다
```

## CLI

CLI 실행 파일의 이름은 `__name__` 입니다. `swift run repo build __name__` 로 빌드한 뒤, 명령과 종료 코드는 `apps/__name__/.build/debug/__name__ help` 로 확인합니다.

## 데이터

항목은 `items.json` 에 저장됩니다. 환경 변수 `__DATA_ENV__` 가 있으면 그 디렉터리를 쓰고, 없으면 `~/Library/Application Support/__BUNDLE_ID__/` 를 씁니다. 시험할 때는 `__DATA_ENV__` 를 임시 디렉터리로 지정하면 실제 데이터를 건드리지 않습니다.
