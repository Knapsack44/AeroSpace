#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

./script/install-dep.sh --complgen

rm -rf .shell-completion && mkdir -p \
    .shell-completion/zsh \
    .shell-completion/fish \
    .shell-completion/bash

./.deps/cargo-root/bin/complgen aot ./grammar/commands-bnf-grammar.txt \
    --zsh-script .shell-completion/zsh/_aerospace \
    --fish-script .shell-completion/fish/aerospace.fish \
    --bash-script .shell-completion/bash/aerospace

# Check basic syntax
if /usr/bin/which zsh &> /dev/null; then
    zsh -c 'autoload -Uz compinit; compinit; source ./.shell-completion/zsh/_aerospace'
fi
if /usr/bin/which fish &> /dev/null; then
    fish -c 'source ./.shell-completion/fish/aerospace.fish'
fi
if /usr/bin/which bash &> /dev/null; then
    bash -c 'source ./.shell-completion/bash/aerospace'
fi
