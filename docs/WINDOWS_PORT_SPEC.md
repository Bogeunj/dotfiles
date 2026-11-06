# dotfiles Windows 네이티브 포팅 스펙 (WSL 없이)

> **이 문서의 용도**
> 개인 dotfiles(Linux/WSL + bash + tmux 기반)를 **WSL 없이 순수 Windows(PowerShell + 터미널)** 환경으로 옮기기 위한 구현 명세서입니다.
> GitHub 접근이 불가능한 환경에서 이 문서 **하나만** Claude에게 전달해 구현을 요청하는 것을 전제로 작성되었습니다.
> 원본 코드는 문서 맨 끝 [부록](#부록-원본-코드-참고용)에 전부 들어 있습니다.

---

## 0. Claude에게 줄 요청 문구 (복붙용)

```
아래 문서는 내가 Linux에서 쓰던 dotfiles를 Windows 네이티브(WSL 없음)로 포팅하기 위한 스펙이야.
문서의 "목표 디렉토리 구조"대로 파일을 만들어주고, 각 컴포넌트 스펙과 "수용 테스트"를 만족하게 구현해줘.
- 셸: PowerShell 7 (pwsh). Windows PowerShell 5.1에서도 최소한 install.ps1은 돌아가게.
- 관리자 권한 없이 동작해야 함 (회사 PC).
- 심볼릭 링크를 쓰지 말 것 (Developer Mode가 꺼져 있을 수 있음).
- 인터넷/패키지 설치가 막혀 있을 수 있으니, 이미 설치된 도구는 건너뛰고 설치 실패해도 나머지 단계는 계속 진행하게.
구현 후에는 각 파일 전체 내용과 설치/사용 방법을 알려줘.
```

---

## 1. 원본 요약 (무엇을 옮기는가)

원본 저장소 구성:

| 파일 | 역할 |
|---|---|
| `install.sh` | Homebrew 설치 → `git tmux lazygit fzf starship git-delta ripgrep` 설치 → nvm + Node LTS → `npm i -g opencode-ai` → dotfile들을 `~`로 심볼릭 링크 → `bin/dev`를 `~/.local/bin`에 링크 → 버전 확인 |
| `.bashrc` | 기본 Ubuntu bashrc + nvm 로드 + brew shellenv + `~/.local/bin` PATH + **현재 폴더에 `.venv`가 있으면 자동 activate** |
| `.gitconfig` | `~/.gitconfig.local` include(이름/이메일 등 개인정보 분리), editor=nvim, defaultBranch=main, fetch.prune=true, pull.rebase=false |
| `.gitconfig.local.example` | user.name / user.email / credential.helper 템플릿 |
| `.tmux.conf` | prefix = `Ctrl+a`, 창/패널 번호 1부터, 창 번호 자동 재정렬 |
| `.wezterm.lua` | WezTerm 설정. 기본 프로그램 `wsl.exe`, 폰트 JetBrains Mono, 테마 Dracula, `Alt+1/2/3` → tmux 창 1/2/3 전환, `Ctrl+c/v` 클립보드 |
| `bin/dev` | **핵심 도구.** git worktree + tmux 세션으로 "브랜치별 작업공간"을 만들어 주는 스크립트 |

### `bin/dev`의 동작 (가장 중요)

- `dev` (인자 없음): 현재 repo 루트에서 세션 `dev_<base>_<현재브랜치>` 생성/접속
- `dev <name>`: `../<base>_<name>` 경로에 `git worktree add -b <name>` (없을 때만) → 세션 `dev_<base>_<name>` 생성/접속
- 세션은 3개 창으로 구성:
  1. `code` 창: `opencode` 실행 (AI 코딩 에이전트)
  2. `git` 창: `lazygit` 실행
  3. `term` 창: 빈 셸
  - 각 창은 `.venv`가 있으면 먼저 activate (우선순위: `$VENV_ACTIVATE` → 대상 worktree의 `.venv` → 메인 repo의 `.venv`)
  - 생성 후 `code` 창을 선택한 상태로 attach
- 이미 세션이 있으면 fzf로 `attach / restart / stop` 선택 (fzf 없으면 attach)
- `dev -l`: 관리 중인 worktree 목록 + 세션 존재/attach 여부
- `dev -c <name>`: 세션 종료 + worktree 강제 삭제 + 로컬 브랜치 삭제 (`<base>_<name>` 형태로 넣어도 허용)
- `dev -c --orphans` (`-orphans`도 허용): 세션이 없는 worktree만 정리
- `dev -c --all`: 관리 중인 전부 정리
- `dev -h`: 도움말
- `<base>` 계산: repo 폴더명이 `<X>_<현재브랜치>` 꼴이면(= 이미 worktree 안에 있으면) `<X>`를 base로 사용, 아니면 폴더명 그대로
- "관리 중인 worktree" = `git worktree list --porcelain`의 경로 중 폴더명이 `<base>_`로 시작하는 것. key = 접두사 뒤 부분

---

## 2. Linux → Windows 매핑

| 원본 (Linux) | Windows 대체 | 비고 |
|---|---|---|
| bash | **PowerShell 7 (`pwsh`)** | 회사 PC에 없으면 scoop/winget으로 설치. 안 되면 5.1 호환 유지 |
| `.bashrc` | `powershell/profile.ps1` + `$PROFILE`에서 dot-source | 심볼릭 링크 대신 한 줄 로더 |
| Homebrew | **scoop** (관리자 불필요) → 실패 시 winget → 둘 다 안 되면 "수동 설치 안내" 출력 | |
| nvm | **fnm** (`fnm env --use-on-cd`) | nvm-windows도 가능하나 fnm 권장 |
| tmux 세션 | **WezTerm workspace** | WezTerm 자체 멀티플렉서는 Windows에서 네이티브로 동작 |
| tmux 창(code/git/term) | **WezTerm 탭** 3개 (타이틀 code/git/term) | |
| tmux prefix + 1/2/3 | `Alt+1/2/3` → `ActivateTab(0/1/2)` 직접 | prefix 불필요 |
| tmux attach | WezTerm `SwitchToWorkspace` | |
| `tmux has-session` / `list-sessions` | `wezterm cli list --format json`의 `workspace` 필드 | |
| `tmux kill-session` | 해당 workspace의 모든 pane에 `wezterm cli kill-pane` | |
| `.venv/bin/activate` | `.venv\Scripts\Activate.ps1` | |
| `ln -s` 심볼릭 링크 | **사용 안 함**. include/dot-source/환경변수로 대체 (아래 4장) | |
| `credential.helper = store` | `credential.helper = manager` (Git for Windows의 GCM) | 평문 저장 피함 |
| `~/.local/bin` | `%USERPROFILE%\.local\bin` 또는 dotfiles\bin을 **사용자 PATH**에 추가 | |
| `wsl.exe` (wezterm default_prog) | `pwsh.exe -NoLogo` | |

---

## 3. 목표 디렉토리 구조

dotfiles 폴더 위치는 자유 (예: `C:\Users\<me>\dotfiles`). 모든 경로는 스크립트 위치 기준으로 계산할 것.

```
dotfiles\
├─ install.ps1                    # 부트스트랩 (멱등)
├─ powershell\
│  └─ profile.ps1                 # .bashrc 대체
├─ git\
│  ├─ .gitconfig                  # 공용 설정 (include 대상)
│  └─ .gitconfig.local.example    # 개인정보 템플릿
├─ wezterm\
│  └─ wezterm.lua                 # WezTerm 설정 (workspace 기반 dev 지원)
├─ bin\
│  ├─ dev.ps1                     # 핵심 도구 (bin/dev 포팅)
│  └─ dev.cmd                     # cmd/PATH에서 `dev`로 부르기 위한 래퍼 (선택)
└─ README.md                      # 설치/사용법
```

---

## 4. 컴포넌트별 상세 스펙

### 4.1 `install.ps1`

요구사항:
- **관리자 권한 불필요**, **멱등**(여러 번 실행해도 안전), 단계별 실패가 전체를 중단시키지 않음(각 단계 try/catch, 마지막에 성공/실패 요약 표 출력).
- 시작 시 실행 정책 안내: 막혀 있으면 `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` 를 안내(자동 변경은 하지 않거나, 사용자 동의 후).
- 로그 형식: `[dotfiles] 메시지`, 에러는 `[ERROR] ...`.

단계:
1. **패키지 매니저 확보**
   - `scoop`이 있으면 사용. 없으면 설치 시도 (`irm get.scoop.sh | iex`). 실패하면 `winget` 사용. 둘 다 없으면 "수동 설치 필요 목록"만 출력하고 계속.
   - 프록시 환경 고려: `$env:HTTPS_PROXY`가 있으면 scoop config에 반영하는 옵션(`scoop config proxy ...`)을 주석으로 안내.
2. **도구 설치** (이미 `Get-Command`로 존재하면 건너뜀)
   - 필수: `git`, `pwsh`, `wezterm`, `lazygit`, `fzf`, `ripgrep`(`rg`), `neovim`(`nvim`), `fnm`
   - 선택: `starship`, `delta`
   - scoop 기준 예: `scoop bucket add extras` 후 `scoop install git pwsh lazygit fzf ripgrep neovim fnm starship delta extras/wezterm`
   - winget 기준 ID 예: `Git.Git`, `Microsoft.PowerShell`, `wez.wezterm`, `JesseDuffield.lazygit`, `junegunn.fzf`, `BurntSushi.ripgrep.MSVC`, `Neovim.Neovim`, `Schniz.fnm`, `Starship.Starship`, `dandavison.delta` (ID는 설치 시 `winget search`로 확인하도록 주석)
   - 폰트: WezTerm은 JetBrains Mono를 **내장**하므로 별도 설치 불필요.
3. **Node LTS** — `fnm install --lts` → `fnm default lts-latest` (명령 형식은 설치된 fnm 버전에 맞게) → 현재 세션에 `fnm env | Out-String | Invoke-Expression`.
4. **AI 코딩 CLI** — 기본 `npm install -g opencode-ai`. 회사에서 다른 CLI(예: `claude`)를 쓰면 설치 생략 가능. `dev.ps1`의 code 탭 명령은 환경변수 `DEV_CODE_CMD`(기본 `opencode`)로 바꿀 수 있게.
5. **PowerShell 프로필 연결 (심볼릭 링크 X)**
   - `$PROFILE.CurrentUserAllHosts` 파일(없으면 생성)에 아래 마커 블록이 없으면 추가:
     ```powershell
     # >>> dotfiles >>>
     . "C:\...\dotfiles\powershell\profile.ps1"
     # <<< dotfiles <<<
     ```
   - pwsh(7)와 Windows PowerShell(5.1)의 프로필 경로가 다르므로 **둘 다** 처리 (`Documents\PowerShell\profile.ps1`, `Documents\WindowsPowerShell\profile.ps1`). OneDrive로 Documents가 리다이렉트된 경우도 `[Environment]::GetFolderPath('MyDocuments')` 로 처리.
   - 기존 프로필 내용은 보존(블록만 추가/갱신). 수정 전 `*.backup.yyyyMMddHHmmss` 백업.
6. **Git 설정 (심볼릭 링크 X)**
   - `~/.gitconfig.local`이 없으면:
     - 기존 `~/.gitconfig`가 있으면 그것을 `.gitconfig.local`로 **복사**(원본 로직 유지)
     - 없으면 `git\.gitconfig.local.example` 복사
   - `~/.gitconfig`를 백업 후 다음 내용으로 생성 (dotfiles 쪽 파일을 include):
     ```ini
     [include]
         path = C:/Users/<me>/dotfiles/git/.gitconfig
     ```
     (경로는 슬래시 `/`로 기록)
   - 공용 `.gitconfig`가 다시 `~/.gitconfig.local`을 include 하므로 개인정보는 분리 유지.
7. **WezTerm 설정 연결 (심볼릭 링크 X)**
   - `~/.wezterm.lua`를 백업 후 아래 한 줄 로더로 생성:
     ```lua
     return dofile([[C:\Users\<me>\dotfiles\wezterm\wezterm.lua]])
     ```
   - (대안: 사용자 환경변수 `WEZTERM_CONFIG_FILE` 설정. 둘 중 하나만.)
8. **dev 명령 PATH 등록**
   - `dotfiles\bin` 을 **사용자 PATH**(`[Environment]::SetEnvironmentVariable('Path', ..., 'User')`)에 중복 없이 추가.
   - `bin\dev.cmd`: `@pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev.ps1" %*` (pwsh 없으면 powershell.exe로 폴백)
   - 프로필에도 `function dev { & "$DotfilesDir\bin\dev.ps1" @args }` 정의 (PowerShell 안에서는 이걸 사용).
9. **검증** — `git --version`, `wezterm --version`, `lazygit --version`, `node -v`, `npm -v`, `<DEV_CODE_CMD> --version` 결과를 표로 출력.
10. 마지막 안내: "터미널(WezTerm)을 다시 열거나 `. $PROFILE` 실행".

옵션 파라미터(권장): `-SkipPackages`, `-SkipNode`, `-SkipAI`, `-DryRun`.

### 4.2 `powershell/profile.ps1` (.bashrc 대체)

- `$DotfilesDir` 를 이 파일 위치에서 계산.
- 히스토리: PSReadLine
  - `Set-PSReadLineOption -HistoryNoDuplicates -MaximumHistoryCount 2000`
  - `-PredictionSource History` (지원 버전일 때만, try/catch)
  - 공백으로 시작하는 명령은 히스토리 제외 (`-AddToHistoryHandler` 로 구현) — bash의 `HISTCONTROL=ignoreboth` 대응
- 별칭: `ll` (= `Get-ChildItem -Force`), `la`, `l`. `grep`이 없으면 `rg`로 별칭(선택).
- `$env:EDITOR = 'nvim'`
- PATH 앞에 `%USERPROFILE%\.local\bin` 추가(존재 시, 중복 방지).
- fnm: 존재하면 `fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression`
- starship: 존재하면 `Invoke-Expression (&starship init powershell)`
- **`.venv` 자동 활성화**: 프로필 로드 시 현재 폴더에 `.venv\Scripts\Activate.ps1` 이 있으면 dot-source. (원본처럼 시작 시점 1회만. 원하면 `cd` 훅으로 확장 가능하다는 주석만)
- `function dev { & (Join-Path $DotfilesDir 'bin\dev.ps1') @args }`
- 모든 도구 연동은 `Get-Command -ErrorAction SilentlyContinue` 로 존재 확인 후 수행 → 미설치여도 프로필 에러 없음.
- 프로필 로드 시간 짧게 유지 (네트워크 호출 금지).

### 4.3 `git/.gitconfig`

원본 그대로 + Windows 보정:
```ini
[include]
    path = ~/.gitconfig.local

[core]
    editor = nvim
    autocrlf = input        ; 또는 팀 규칙에 맞게 (주석으로 안내)
    longpaths = true        ; worktree 경로가 길어질 수 있음

[init]
    defaultBranch = main

[fetch]
    prune = true

[pull]
    rebase = false
```
- delta가 설치돼 있으면 쓰도록 하는 설정은 **주석 처리된 예시**로만 제공 (미설치 PC에서 git이 깨지지 않게).

`git/.gitconfig.local.example`:
```ini
[user]
    name = Your Name
    email = you@example.com

[credential]
    helper = manager
```

### 4.4 `wezterm/wezterm.lua`

원본 설정 유지 + tmux 역할 흡수:
- `default_prog = { 'pwsh.exe', '-NoLogo' }` (pwsh 없으면 `powershell.exe` — `wezterm.glob`/존재 확인 또는 주석으로 안내)
- `font = wezterm.font 'JetBrains Mono'`, `color_scheme = 'Dracula'`
- 키:
  - `Alt+1/2/3` → `act.ActivateTab(0/1/2)` (원본: tmux 창 1/2/3 = code/git/term)
  - `Ctrl+c` → **선택 영역이 있으면 복사, 없으면 Ctrl+c를 그대로 전달**(SIGINT가 죽지 않도록. `wezterm.action_callback`에서 `window:get_selection_text_for_pane(pane)` 확인)
  - `Ctrl+v` → `PasteFrom 'Clipboard'`
  - `Alt+w` → `ShowLauncherArgs { flags = 'FUZZY|WORKSPACES' }` (= tmux 세션 선택기)
  - `Alt+n` / `Alt+p` → 다음/이전 workspace (`SwitchWorkspaceRelative(1/-1)`) (선택)
- 탭 바: 현재 workspace 이름을 오른쪽 상태줄에 표시 (`update-right-status` 이벤트에서 `window:active_workspace()`).
- 탭 타이틀이 셸에 의해 덮어써지지 않도록, 탭에 명시 타이틀(`tab:set_title`)이 있으면 그것을 우선 표시 (`format-tab-title` 이벤트).
- **dev.ps1 연동용 이벤트 핸들러**:
  ```lua
  -- dev.ps1 이 OSC 1337 SetUserVar=DEV_SWITCH=<base64(workspace명)> 을 보내면 해당 workspace로 전환
  wezterm.on('user-var-changed', function(window, pane, name, value)
    if name == 'DEV_SWITCH' and value ~= '' then
      window:perform_action(wezterm.action.SwitchToWorkspace { name = value }, pane)
    end
  end)
  ```

### 4.5 `bin/dev.ps1` (핵심 — `bin/dev` 포팅)

**전제**: WezTerm 안에서 실행 (`$env:WEZTERM_PANE` 존재). 아니면 `[ERROR] dev는 WezTerm 안에서 실행해야 합니다.` 출력 후 종료 (단 `-h`, `-l`(worktree 부분)은 동작해도 됨).

**인터페이스** (원본과 동일하게 유지):
```
dev [name]
dev -l
dev -c <name>
dev -c --orphans   (-orphans 도 허용)
dev -c --all
dev -h | --help
```
PowerShell 파라미터 바인딩과 충돌하지 않도록 `param()` 대신 **`$args` 를 직접 파싱**할 것 (`-c`, `--all` 등을 그대로 받기 위해). `dev.cmd`에서 넘어오는 인자도 동일하게 처리.

**변수 계산** (원본과 동일):
- `REPO_ROOT` = `git rev-parse --show-toplevel` (실패 시 현재 폴더). **Windows 경로로 정규화** (`git`은 `C:/x/y` 형태를 줄 수 있음 → `[IO.Path]::GetFullPath`)
- `PROJECT_NAME` = REPO_ROOT 폴더명
- `CURRENT_BRANCH` = `git rev-parse --abbrev-ref HEAD` (실패 시 `main`)
- `BASE_NAME` = PROJECT_NAME 이 `_<CURRENT_BRANCH>` 로 끝나면 그 접미사 제거, 아니면 PROJECT_NAME
- 세션(workspace) 이름 = `dev_<BASE_NAME>_<key>`
- 브랜치명에 `/` 등 경로 금지 문자가 있으면 **폴더명/워크스페이스명에서는 `-`로 치환**, git 브랜치명은 원본 그대로 사용 (원본에는 없는 개선. 치환 규칙은 도움말에 명시)

**venv 해석** (`Resolve-ActivateScript $targetPath`):
1. `$env:VENV_ACTIVATE` 가 있고 파일이 존재하면 그것
2. `<targetPath>\.venv\Scripts\Activate.ps1`
3. `<MAIN_PATH>\.venv\Scripts\Activate.ps1`
4. 없으면 빈 문자열

**탭에서 실행할 명령 만들기** (`Build-TabArgs $cmd $targetPath`):
- 결과는 `wezterm cli spawn` 의 `--` 뒤에 붙일 인자 배열:
  `pwsh -NoLogo -NoExit -Command "<activate가 있으면 '. ''<경로>''; '><cmd>"`
- `cmd`가 비어 있으면(term 탭) activate만 하고 셸 유지.
- 따옴표 이스케이프 주의 (경로에 공백이 있을 수 있음 → 단일따옴표 이중화 방식 권장).

**WezTerm 헬퍼 함수**:
- `Get-WezPanes` : `wezterm cli list --format json | ConvertFrom-Json` (필드: `window_id, tab_id, pane_id, workspace, title, cwd ...`)
- `Test-Workspace $name` : 위 목록에 `workspace -eq $name` 인 pane이 있는지
- `Remove-Workspace $name` : 해당 workspace의 모든 `pane_id`에 대해 `wezterm cli kill-pane --pane-id <id>`. **현재 pane(`$env:WEZTERM_PANE`)이 그 workspace에 속하면 마지막에 kill** (스크립트가 먼저 죽지 않게)
- `Switch-Workspace $name` :
  1. OSC 1337 전송: `[Console]::Write("$([char]27)]1337;SetUserVar=DEV_SWITCH=$(base64(utf8 name))$([char]7)")`
  2. 전환이 안 되는 환경(ConPTY가 OSC를 삼키는 경우 등)을 위해 안내 출력: `"[INFO] 전환이 안 되면 Alt+w 로 '<name>' 선택"`
- `New-DevWorkspace $name $targetPath` :
  1. `$p1 = wezterm cli spawn --new-window --workspace $name --cwd $targetPath -- <code탭 args>` (출력 = pane id)
  2. `wezterm cli set-tab-title --pane-id $p1 code`
  3. `$p2 = wezterm cli spawn --pane-id $p1 --cwd $targetPath -- <git탭 args: lazygit>` → 타이틀 `git`
     (`--pane-id` 를 주고 `--new-window` 를 빼면 같은 창에 새 탭으로 생김)
  4. `$p3 = wezterm cli spawn --pane-id $p1 --cwd $targetPath -- <term탭 args>` → 타이틀 `term`
  5. `wezterm cli activate-tab --pane-id $p1` 등으로 code 탭 활성화 (지원 명령은 설치된 wezterm 버전의 `wezterm cli --help`로 확인)
  6. `Switch-Workspace $name`

**메인 흐름** (원본과 동일 순서):
1. `-h/--help` → 도움말 출력 (원본 도움말 문구를 한국어/영어 중 택1로 유지, tmux → WezTerm workspace로 용어만 변경)
2. `-l` → `Sessions for <BASE>:` 출력 후, 관리 worktree마다:
   - workspace 있으면 `  * <key> [<branch>] (workspace: <name>, active|background)`
     - active 판정: `wezterm cli list-clients --format json` 의 `focused_pane_id` 가 속한 workspace == name
   - 없으면 `  - <key> [<branch>] (no workspace)`
3. `-c <target>` → 원본과 동일 (`--orphans`, `-orphans`, `--all`, `<base>_<key>` 접두 허용). 대상별 `Cleanup-Target`:
   - `Remove-Workspace dev_<base>_<key>` (없으면 무시)
   - worktree 경로가 있으면 `git worktree remove <path> --force`
   - `git branch -D <key>` (실패 무시)
   - `[SUCCESS] '<key>' environment cleanup completed.`
   - **Windows 주의**: 해당 worktree 안에서 프로세스(lazygit, node 등)가 파일을 잡고 있으면 삭제 실패 → workspace 종료 후 `Start-Sleep -Milliseconds 500` 후 재시도 1~2회, 그래도 실패하면 경로를 알려주고 계속.
   - `--all`, `--orphans` 는 원본처럼 목록을 먼저 다 수집한 뒤 순회.
4. 그 외 (`dev` 또는 `dev <name>`):
   - name 없음: `targetPath = MAIN_PATH`, workspace = `dev_<base>_<CURRENT_BRANCH>`
   - name 있음: `targetPath = <REPO_ROOT의 부모>\<base>_<name>` (원본의 `../` 를 **절대경로로**), 폴더 없으면 `git worktree add <targetPath> -b <name>`
     - 이미 브랜치 `<name>`이 존재하면 `-b` 없이 `git worktree add <targetPath> <name>` 로 폴백 (원본 개선)
   - workspace가 이미 있으면:
     - fzf 있으면 `"attach`n restart`n stop" | fzf --header "Action for <ws>:"`, 없으면 `Read-Host` 로 1/2/3 선택 (기본 attach)
     - attach → `Switch-Workspace`, 종료
     - restart → `Remove-Workspace` 후 아래 생성으로 진행
     - stop → name 없으면 `[INFO] No target name provided. Use: dev -c <name>` / 있으면 `Cleanup-Target`
     - 그 외(ESC 등) → 종료
   - 없으면 `New-DevWorkspace`

**기타**:
- `git`, `wezterm` 없으면 `[ERROR] git is required.` 식으로 종료 (원본의 tmux 체크 → wezterm 체크).
- code 탭 명령 = `$env:DEV_CODE_CMD` (기본 `opencode`), git 탭 명령 = `$env:DEV_GIT_CMD` (기본 `lazygit`).
- 종료 코드: 성공 0, 사용법 오류 1.
- `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`. 단 git/wezterm 외부 명령은 `$LASTEXITCODE` 로 확인.

---

## 5. 대안: WezTerm 설치가 불가능할 때 (Windows Terminal 모드)

WezTerm을 회사에서 못 쓰면 `dev.ps1` 에 `-Backend wt` 모드(또는 `$env:DEV_BACKEND='wt'`)를 추가:
- 생성/접속: `wt.exe -w <ws이름> new-tab --title code -d <path> pwsh -NoExit -Command <...> `; new-tab --title git ... `; new-tab --title term ... `; focus-tab -t 0`
  - `-w <이름>` 은 같은 이름의 창이 열려 있으면 그 창을 재사용 → "attach" 비슷하게 동작
  - PowerShell에서 `;` 는 wt 인자로 넘기려면 `` `; `` 로 이스케이프 필요
- 한계: 세션 목록/존재 확인/종료(-l, restart, -c 의 세션 종료 부분)를 정확히 할 수 없음 → `-l` 은 worktree 목록만, `-c` 는 worktree/브랜치만 정리하고 "창은 직접 닫으세요" 안내.
- Windows Terminal `settings.json` 에 `Alt+1/2/3` → `switchToTab` index 0/1/2 키 바인딩 예시를 README에 포함.

---

## 6. 주의사항 / 엣지 케이스

- **실행 정책**: 회사 GPO로 막혀 있으면 `dev.cmd`(Bypass) 경유로 실행. 프로필 로드도 막히면 README에 안내.
- **경로**: 공백/한글 포함 경로 지원. git이 돌려주는 `/` 경로를 `\` 로 정규화한 뒤 비교. 폴더명 비교는 대소문자 무시(`-ieq`).
- **OneDrive Documents 리다이렉트**: 프로필 경로는 반드시 `$PROFILE` 변수/`GetFolderPath`로 구할 것.
- **프록시/오프라인**: 설치 단계 실패 시 다음 단계로 진행, 마지막 요약에서 실패 항목과 수동 설치 방법 표시.
- **CRLF**: 생성하는 `.ps1`은 UTF-8 (BOM 포함 권장: 5.1에서 한글 깨짐 방지), `.lua`/`.gitconfig` 는 UTF-8 (BOM 없음).
- **worktree 삭제 잠금**: 4.5의 재시도 로직 참고.
- **credential**: 원본의 `store`(평문 저장)는 회사 환경에서 쓰지 말 것 → `manager`.

---

## 7. 수용 테스트 (구현 완료 기준)

새 사용자 계정(또는 깨끗한 PC)에서:

1. [ ] `pwsh -File install.ps1` 이 관리자 권한 없이 끝까지 실행되고, 두 번 실행해도 에러/중복이 없다.
2. [ ] 새 WezTerm 창이 pwsh로 열리고, Dracula 테마 + JetBrains Mono가 적용된다.
3. [ ] 프로필 로드 중 에러가 없다 (일부 도구 미설치 상태에서도).
4. [ ] `git config user.email` 이 `.gitconfig.local` 값을 출력하고, `git config init.defaultBranch` 가 `main`.
5. [ ] `.venv` 가 있는 폴더에서 새 탭을 열면 자동 activate 된다.
6. [ ] 테스트 repo `C:\work\proj` 에서:
   - [ ] `dev` → workspace `dev_proj_main` 생성, 탭 code/git/term, code 탭 활성, opencode/lazygit 실행 중
   - [ ] `dev feat` → `C:\work\proj_feat` worktree + 브랜치 `feat` 생성, workspace `dev_proj_feat` 로 전환
   - [ ] `Alt+1/2/3` 으로 code/git/term 탭 이동
   - [ ] `Alt+w` 로 workspace 목록이 뜨고 이동 가능
   - [ ] `C:\work\proj_feat` 안에서 `dev -l` 실행 시 base가 `proj` 로 계산되어 목록이 동일하게 나온다
   - [ ] 이미 있는 workspace로 `dev feat` → attach/restart/stop 선택이 뜬다
   - [ ] `dev -c feat` → workspace 탭들 닫힘, `proj_feat` 폴더 삭제, `feat` 브랜치 삭제
   - [ ] `dev -c proj_feat` 도 동일하게 동작
   - [ ] workspace만 수동으로 닫은 뒤 `dev -c --orphans` → 해당 worktree만 정리
   - [ ] `dev -c --all` → 관리 중인 모든 것 정리, 메인 repo는 유지
7. [ ] `cmd.exe` 에서도 `dev -h` 가 동작한다 (`dev.cmd` 경유).

---

## 부록: 원본 코드 (참고용)

> 동작을 정확히 맞추기 위한 참고 자료. 그대로 복사하지 말고 위 스펙대로 Windows용으로 다시 구현할 것.

### A. `bin/dev` (bash)

```bash
#!/usr/bin/env bash

set -euo pipefail

if ! command -v git >/dev/null 2>&1; then
    echo "[ERROR] git is required."
    exit 1
fi

if ! command -v tmux >/dev/null 2>&1; then
    echo "[ERROR] tmux is required."
    exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_NAME="$(basename "$REPO_ROOT")"
MAIN_PATH="$REPO_ROOT"
CURRENT_BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"

if [[ "$PROJECT_NAME" == *"_$CURRENT_BRANCH" ]]; then
    BASE_NAME="${PROJECT_NAME%_$CURRENT_BRANCH}"
else
    BASE_NAME="$PROJECT_NAME"
fi

resolve_activate_script() {
    local target_path="$1"

    if [[ -n "${VENV_ACTIVATE:-}" && -f "${VENV_ACTIVATE}" ]]; then
        printf '%s' "${VENV_ACTIVATE}"
        return 0
    fi

    if [[ -f "$target_path/.venv/bin/activate" ]]; then
        printf '%s' "$target_path/.venv/bin/activate"
        return 0
    fi

    if [[ -f "$MAIN_PATH/.venv/bin/activate" ]]; then
        printf '%s' "$MAIN_PATH/.venv/bin/activate"
        return 0
    fi

    printf ''
}

build_window_command() {
    local cmd="$1"
    local target_path="$2"
    local activate_script

    activate_script="$(resolve_activate_script "$target_path")"
    if [[ -n "$activate_script" ]]; then
        printf 'source "%s" && %s' "$activate_script" "$cmd"
    else
        printf '%s' "$cmd"
    fi
}

session_name_for_key() {
    local key="$1"
    printf 'dev_%s_%s' "$BASE_NAME" "$key"
}

print_help() {
    cat <<EOF
Usage:
  dev [name]
  dev -l
  dev -c <name>
  dev -c --orphans
  dev -c --all
  dev -h | --help

What it manages:
  - Worktree: a separate directory checked out to a branch
  - Tmux session: terminal workspace named dev_<project>_<name>

Examples:
  dev b               Create/attach branch b workspace (e.g. ${BASE_NAME}_b)
                      Tmux session example: dev_${BASE_NAME}_b
  dev -l              List worktrees and tmux status
  dev -c test         Remove test tmux/session + worktree + local branch
  dev -c --orphans    Remove worktrees that have no matching tmux session
  dev -c --all        Remove all managed worktrees/sessions

Notes:
  - Use --orphans (double dash). -orphans is also accepted as alias.
  - Cleanup commands remove directories and local branches.
  - Set VENV_ACTIVATE to force a specific virtualenv activate script.
EOF
}

list_managed_worktrees() {
    git worktree list --porcelain | while IFS= read -r line; do
        case "$line" in
            worktree\ *)
                wp_path="${line#worktree }"
                wp_name="$(basename "$wp_path")"
                if [[ "$wp_name" == "${BASE_NAME}_"* ]]; then
                    wp_key="${wp_name#${BASE_NAME}_}"
                    printf '%s|%s\n' "$wp_path" "$wp_key"
                fi
                ;;
        esac
    done
}

cleanup_target() {
    local key="$1"
    local wp_path=""

    while IFS='|' read -r path name; do
        if [[ "$name" == "$key" ]]; then
            wp_path="$path"
            break
        fi
    done < <(list_managed_worktrees)

    tmux kill-session -t "$(session_name_for_key "$key")" 2>/dev/null || true

    if [[ -n "$wp_path" ]]; then
        git worktree remove "$wp_path" --force
    fi

    git branch -D "$key" 2>/dev/null || true
    echo "[SUCCESS] '$key' environment cleanup completed."
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    print_help
    exit 0
fi

if [[ "${1:-}" == "-l" ]]; then
    echo "Sessions for $BASE_NAME:"

    while IFS='|' read -r wp_path wp_key; do
        wp_branch="$(git -C "$wp_path" rev-parse --abbrev-ref HEAD)"
        session="$(session_name_for_key "$wp_key")"
        if tmux has-session -t "$session" 2>/dev/null; then
            attached="detached"
            if tmux list-sessions -F '#{session_name} #{?session_attached,attached,detached}' 2>/dev/null | awk -v s="$session" '$1 == s { print $2; found=1 } END { if (!found) print "detached" }' | grep -q '^attached$'; then
                attached="attached"
            fi
            echo "  * $wp_key [$wp_branch] (tmux: $session, $attached)"
        else
            echo "  - $wp_key [$wp_branch] (no tmux)"
        fi
    done < <(list_managed_worktrees)

    exit 0
fi

if [[ "${1:-}" == "-c" ]]; then
    option="${2:-}"
    if [[ -z "$option" ]]; then
        echo "[ERROR] Specify a target."
        echo "Try: dev -c <name> | dev -c --orphans | dev -c --all"
        exit 1
    fi

    if [[ "$option" == "-orphans" ]]; then
        option="--orphans"
    fi

    if [[ "$option" == "--all" ]]; then
        while IFS='|' read -r _ path_key; do
            cleanup_target "$path_key"
        done < <(list_managed_worktrees)
        echo "[SUCCESS] All managed environments cleaned up."
    elif [[ "$option" == "--orphans" ]]; then
        while IFS='|' read -r _ path_key; do
            if ! tmux has-session -t "$(session_name_for_key "$path_key")" 2>/dev/null; then
                cleanup_target "$path_key"
            fi
        done < <(list_managed_worktrees)
        echo "[SUCCESS] Orphan worktrees cleaned up."
    else
        key="$option"
        if [[ "$key" == "${BASE_NAME}_"* ]]; then
            key="${key#${BASE_NAME}_}"
        fi
        cleanup_target "$key"
    fi

    exit 0
fi

target_name="${1:-}"
if [[ -z "$target_name" ]]; then
    target_path="$MAIN_PATH"
    session="$(session_name_for_key "$CURRENT_BRANCH")"
else
    target_path="../${BASE_NAME}_$target_name"
    session="$(session_name_for_key "$target_name")"
    if [[ ! -d "$target_path" ]]; then
        git worktree add "$target_path" -b "$target_name"
    fi
fi

if tmux has-session -t "$session" 2>/dev/null; then
    if command -v fzf >/dev/null 2>&1; then
        action="$(printf "attach\nrestart\nstop" | fzf --header="Action for $session:")"
    else
        action="attach"
    fi

    case "$action" in
        attach)
            tmux attach-session -t "$session"
            exit 0
            ;;
        restart)
            tmux kill-session -t "$session"
            ;;
        stop)
            if [[ -z "$target_name" ]]; then
                echo "[INFO] No target name provided. Use: dev -c <name>"
                exit 0
            fi
            "$0" -c "$target_name"
            exit 0
            ;;
        *)
            exit 0
            ;;
    esac
fi

tmux new-session -d -s "$session" -n "code" -c "$target_path"
tmux send-keys -t "$session:code" "$(build_window_command opencode "$target_path")" Enter
tmux new-window -t "$session" -n "git" -c "$target_path"
tmux send-keys -t "$session:git" "$(build_window_command lazygit "$target_path")" Enter
tmux new-window -t "$session" -n "term" -c "$target_path"

activate_script="$(resolve_activate_script "$target_path")"
if [[ -n "$activate_script" ]]; then
    tmux send-keys -t "$session:term" "source \"$activate_script\"" Enter
fi

tmux select-window -t "$session:code"
tmux attach-session -t "$session"
```

### B. `install.sh`

```bash
#!/usr/bin/env bash

set -euo pipefail

trap 'echo "[ERROR] install failed at line ${LINENO}" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$SCRIPT_DIR"
NVM_INSTALL_URL="https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh"

log() {
    printf '[dotfiles] %s\n' "$1"
}

backup_if_needed() {
    local target="$1"
    local source="$2"

    if [[ -L "$target" ]] && [[ "$(readlink -f "$target")" == "$(readlink -f "$source")" ]]; then
        return 0
    fi

    if [[ -e "$target" ]] || [[ -L "$target" ]]; then
        local backup_path="${target}.backup.$(date +%Y%m%d%H%M%S)"
        mv "$target" "$backup_path"
        log "Backed up $target -> $backup_path"
    fi
}

link_file() {
    local source="$1"
    local target="$2"

    mkdir -p "$(dirname "$target")"
    backup_if_needed "$target" "$source"
    ln -sfn "$source" "$target"
}

activate_brew_env() {
    if command -v brew >/dev/null 2>&1; then
        eval "$("$(command -v brew)" shellenv)"
        return
    fi

    for candidate in /home/linuxbrew/.linuxbrew/bin/brew /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [[ -x "$candidate" ]]; then
            eval "$("$candidate" shellenv)"
            return
        fi
    done
}

ensure_brew() {
    activate_brew_env
    if command -v brew >/dev/null 2>&1; then
        return
    fi

    if ! command -v curl >/dev/null 2>&1; then
        echo "[ERROR] curl is required to install Homebrew." >&2
        exit 1
    fi

    log "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    activate_brew_env

    if ! command -v brew >/dev/null 2>&1; then
        echo "[ERROR] Homebrew installation failed." >&2
        exit 1
    fi
}

ensure_nvm_and_node() {
    if [[ ! -s "$HOME/.nvm/nvm.sh" ]]; then
        log "Installing nvm..."
        curl -fsSL "$NVM_INSTALL_URL" | bash
    fi

    # shellcheck source=/dev/null
    source "$HOME/.nvm/nvm.sh"

    log "Installing Node LTS via nvm..."
    nvm install --lts
    nvm alias default 'lts/*'
    nvm use --lts >/dev/null
}

ensure_opencode() {
    if ! command -v npm >/dev/null 2>&1; then
        echo "[ERROR] npm is not available after Node installation." >&2
        exit 1
    fi

    log "Installing opencode-ai with npm..."
    npm install -g opencode-ai

    local npm_global_bin
    npm_global_bin="$(npm prefix -g)/bin"
    if [[ -x "$npm_global_bin/opencode" ]]; then
        mkdir -p "$HOME/.local/bin"
        ln -sfn "$npm_global_bin/opencode" "$HOME/.local/bin/opencode"
    fi

    if ! command -v opencode >/dev/null 2>&1; then
        echo "[ERROR] opencode command is not available." >&2
        exit 1
    fi
}

ensure_gitconfig_local() {
    if [[ -f "$HOME/.gitconfig.local" ]]; then
        return
    fi

    if [[ -f "$HOME/.gitconfig" ]] && [[ ! -L "$HOME/.gitconfig" ]]; then
        cp "$HOME/.gitconfig" "$HOME/.gitconfig.local"
        log "Created ~/.gitconfig.local from existing ~/.gitconfig"
        return
    fi

    cp "$DOTFILES_DIR/.gitconfig.local.example" "$HOME/.gitconfig.local"
    log "Created ~/.gitconfig.local from template"
}

log "Starting dotfiles installation..."

ensure_brew

log "Installing core tools (git tmux lazygit fzf starship git-delta ripgrep)..."
brew install git tmux lazygit fzf starship git-delta ripgrep

ensure_nvm_and_node
ensure_opencode

log "Linking dotfiles into home directory..."
link_file "$DOTFILES_DIR/.bashrc" "$HOME/.bashrc"
link_file "$DOTFILES_DIR/.tmux.conf" "$HOME/.tmux.conf"

ensure_gitconfig_local
link_file "$DOTFILES_DIR/.gitconfig" "$HOME/.gitconfig"

log "Linking helper scripts..."
mkdir -p "$HOME/.local/bin"
chmod +x "$DOTFILES_DIR/bin/dev"
link_file "$DOTFILES_DIR/bin/dev" "$HOME/.local/bin/dev"
chmod +x "$HOME/.local/bin/dev"

log "Verifying installs..."
git --version
tmux -V
node -v
npm -v
opencode --version

log "Done. Restart your terminal or run: source ~/.bashrc"
```

### C. `.wezterm.lua`

```lua
-- Windows 쪽 파일: C:\Users\<user>\.wezterm.lua
-- 새 머신에서는 이 파일을 그 경로로 복사(또는 심볼릭 링크)해야 적용됨.
-- Alt+1/2/3 -> Ctrl+a(tmux prefix) + 1/2/3 -> bin/dev가 만드는 code/git/term 창 전환
local wezterm = require 'wezterm'
local config = {}
config.default_prog = { 'wsl.exe', '~' }
config.font = wezterm.font 'JetBrains Mono'
config.color_scheme = 'Dracula'
config.keys = {
  { key = '1', mods = 'ALT', action = wezterm.action.SendString '\x011' },
  { key = '2', mods = 'ALT', action = wezterm.action.SendString '\x012' },
  { key = '3', mods = 'ALT', action = wezterm.action.SendString '\x013' },
  { key = 'c', mods = 'CTRL', action = wezterm.action.CopyTo 'Clipboard' },
  { key = 'v', mods = 'CTRL', action = wezterm.action.PasteFrom 'Clipboard' },
}
return config
```

### D. `.tmux.conf`

```
# Prefix를 Ctrl + a로 설정
set -g prefix C-a
unbind C-b
bind C-a send-prefix

# 에피의 바이브: 창 번호를 1번부터 시작! (매우 중요)
set -g base-index 1
setw -g pane-base-index 1

# 창 번호가 중간에 비면 자동으로 채우기
set -g renumber-windows on
```

### E. `.gitconfig` / `.gitconfig.local.example`

```ini
[include]
    path = ~/.gitconfig.local

[core]
    editor = nvim

[init]
    defaultBranch = main

[fetch]
    prune = true

[pull]
    rebase = false

[user]
    name = Your Name
    email = you@example.com

[credential]
    helper = store
```

### F. `.bashrc` 중 커스텀 부분 (나머지는 Ubuntu 기본값)

```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

if command -v brew >/dev/null 2>&1; then
    eval "$("$(command -v brew)" shellenv)"
elif [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
export PATH="$HOME/.local/bin:$PATH"
# 프로젝트 폴더에 .venv가 있으면 자동으로 켜기
if [ -f "./.venv/bin/activate" ]; then
    source "./.venv/bin/activate"
fi
# (그 외: HISTCONTROL=ignoreboth, HISTSIZE=1000, HISTFILESIZE=2000, alias ll='ls -alF', la='ls -A', l='ls -CF')
```
