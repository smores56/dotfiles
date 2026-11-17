# Development and check image for the dotfiles repository itself.
# Pinned by digest; `dev` builds it for this checkout.
FROM registry.fedoraproject.org/fedora:43@sha256:01aab1ff7df0cde68d5994e13a5639fe6524781a3664d69f5857e93b30508294

RUN dnf -y install --setopt=install_weak_deps=False \
        bash git jq python3 shellcheck zsh \
    && dnf -y clean all \
    && rm -rf /var/cache/dnf

WORKDIR /workspace
COPY . /workspace
CMD ["sh", "tests/check.sh", "--shellcheck"]
