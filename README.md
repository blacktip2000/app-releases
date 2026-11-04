# app-releases

blacktip2000의 앱 설치 파일 **공개 배포 전용** 레포입니다. 소스 코드는 없습니다(각 앱 레포는 Private).
앱 안의 자동 업데이트가 이 레포의 매니페스트를 읽고, 릴리스 자산(설치 파일)을 내려받습니다.

## 규칙 (앱 공통)

| 항목 | 규칙 | 예 (CCCAN 0.3.0) |
|---|---|---|
| 릴리스 태그 | `<App>-v<SemVer>` | `CCCAN-v0.3.0` |
| 설치 파일 | 릴리스 자산 | `CCCAN-Setup-0.3.0.exe` |
| 최신 매니페스트 | `apps/<App>/latest.json` | `apps/CCCAN/latest.json` |
| 버전 기록 | `apps/<App>/versions/<SemVer>.json` | `apps/CCCAN/versions/0.3.0.json` |

앱은 `https://raw.githubusercontent.com/blacktip2000/app-releases/main/apps/<App>/latest.json` 을 읽습니다.

## 매니페스트 형식 (schema 1)

```json
{
  "schema": 1,
  "app": "CCCAN",
  "version": "0.3.0",
  "tag": "CCCAN-v0.3.0",
  "published": "2026-11-04",
  "notes": "변경 내용(텍스트/마크다운)",
  "notesUrl": "https://github.com/blacktip2000/app-releases/releases/tag/CCCAN-v0.3.0",
  "installer": {
    "url": "https://github.com/blacktip2000/app-releases/releases/download/CCCAN-v0.3.0/CCCAN-Setup-0.3.0.exe",
    "sha256": "<설치 파일 SHA-256, 소문자 64자>",
    "size": 3100000
  }
}
```

- 앱은 `app` 일치, `version`이 SemVer이고 현재보다 높은지, `installer.url`이 이 레포 릴리스 자산인지 확인합니다.
- 내려받은 파일의 크기와 SHA-256이 다르면 설치하지 않습니다.

## 배포 방법

```powershell
# 앱 레포에서 설치 파일을 만든 뒤
pwsh -File tools\publish.ps1 -App CCCAN -Version 0.3.0 -Installer ..\CCCAN\installer\Output\CCCAN-Setup-0.3.0.exe -NotesFile notes.md
```

**한 번 올린 릴리스 자산은 교체하지 않습니다**(다운로드 CDN이 이전 파일을 계속 줄 수 있음 → 앱의 SHA-256 검증 실패). 수정이 필요하면 버전을 올려 새로 배포합니다.

`publish.ps1` 순서: 릴리스 생성(같은 태그가 있으면 중단) → 매니페스트 작성 → 커밋·푸시 → raw 주소로 다시 받아 SHA-256 확인.
**매니페스트는 자산 업로드가 끝난 뒤에만** 갱신되므로, 앱이 없는 파일을 받으려 하는 일이 없습니다.

새 앱을 추가할 때는 `apps/<App>/` 폴더만 새로 쓰면 됩니다(다른 앱과 태그·경로가 겹치지 않음).

## Release summary (shown in the app's update dialog)

Start the notes file with a summary section; `tools/publish.ps1` copies its bullets into `summary` of the manifest.

```markdown
### 요약
- one-line change
- another one-line change

### Added
- **Feature**: details ...
```

- `summary`: bullets of the summary section (`### 요약` or `### Summary`). Apps from CCCAN 0.4.1 show it first.
- `history`: summaries of previous versions (from `apps/<App>/versions/*.json`, newest first, up to 10).
  Apps show every version newer than the installed one, so skipped versions are visible too.
  Entries without a summary carry their `notes` (the app summarizes them).
- `notes`: full notes (markdown bold/code marks removed) + a short "previous versions" section for older apps that only read `notes`.
- Rebuild the manifest of an already released version (no new asset): add `-ManifestOnly`.
