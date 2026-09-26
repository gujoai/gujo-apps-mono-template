# 3. 문서 작성 기준

## 상태

채택(2026-09-26).

## 배경

이 템플릿의 문서는 에이전트가 매 작업 전에 읽고, 고객 저장소에 복사된 뒤에도 계속 쓰입니다. 기능이 바뀔 때마다 여러 문서에 같은 설명이 더해지면 문서가 길어지고 서로 어긋납니다. 그래서 문서마다 독자와 담을 내용을 정하는 기준이 필요했습니다. 템플릿을 쓰는 사람과 에이전트에게 일을 맡기는 사람은 한국어 사용자입니다.

## 결정

- 문서는 https://github.com/dalsoop/stable-agent-documentation-guidebook 의 `guides/new-project.md` 절차와 템플릿을 따릅니다. 문서마다 독자와 독자 과제를 정하고, 컨텍스트 파일(`AGENTS.md`)에는 이유를 붙인 관례만 둡니다.
- 문서는 한국어 원본 하나만 두고, 한국어 문장은 https://github.com/snflkd/fluent-korean 지침을 따릅니다.
- README 와 AGENTS.md 에 이 기준을 따른다는 사실을 알립니다.

## 검토한 대안

- **가이드북처럼 영어(Simplified Technical English) 원본과 한국어 번역본을 함께 두기:** 기각했습니다. 독자가 한국어 사용자이고, 두 벌을 맞춰 관리하는 비용이 듭니다.
- **기준 없이 쓰기:** 기각했습니다. 기능이 바뀔 때마다 README 와 AGENTS.md 에 같은 설명이 더해지고, 규칙에 이유가 없어서 지워도 되는지 판단할 수 없게 됩니다.

## 결과

- 문서별 독자 표는 `ARCHITECTURE.md` 에 두고, 명령 설명은 AGENTS.md 가 아니라 `swift run repo help` 로 옮깁니다.
- 문서 규칙 가운데 기계로 확인할 수 있는 부분은 `swift run repo doctor` 의 점검으로 만듭니다. 무엇을 점검하고 무엇을 사람이 확인하는지는 `ARCHITECTURE.md` 의 점검 상태 절에 둡니다.
- 가이드북의 영어 원본 규칙을 따르지 않는다는 사실은 `ARCHITECTURE.md` 의 예외 절에 적습니다.
