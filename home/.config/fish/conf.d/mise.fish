# mise owns language and CLI versions. Guarded so a machine without mise (or a
# container before the install step) still gets a usable shell.
if type -q mise
    mise activate fish | source
end
