#!/bin/bash
echo "[PROCESS] 시스템 자동 설정을 시작합니다..."

# 1. Homebrew 설치 확인 및 설치
if ! command -v brew &> /dev/null; then
    echo "Homebrew를 설치합니다..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"
fi

# 2. 필수 패키지 일괄 설치
echo "필수 도구들을 설치합니다 (tmux, lazygit, fzf, starship, git-delta, ripgrep)..."
brew install tmux lazygit fzf starship git-delta ripgrep

# 3. 심볼릭 링크 생성 (환경 설정 연결)
echo "설정 파일(dotfiles)을 연결합니다..."
ln -sf ~/dotfiles/.bashrc ~/.bashrc
ln -sf ~/dotfiles/.tmux.conf ~/.tmux.conf

# 4. dev 스크립트 설치
echo "dev 스크립트를 경로에 등록합니다..."
mkdir -p ~/.local/bin
ln -sf ~/dotfiles/bin/dev ~/.local/bin/dev
chmod +x ~/.local/bin/dev

echo "[SUCCESS] 모든 설정이 완료되었습니다. 터미널을 재시작하세요!"
