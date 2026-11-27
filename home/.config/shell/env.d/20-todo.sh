# The shared file plane: one Syncthing folder at /srv/files holding the todo
# list, the Obsidian notes and the arbitrary-file vault. Exported only when the
# todo directory exists: the work Mac has no /srv, and an unset TODO_FILE makes
# tuxedo create ./todo.txt in whatever directory it was started from.
if [ -d /srv/files/todos ]; then
    TODO_DIR=/srv/files/todos
    TODO_FILE=$TODO_DIR/todo.txt
    NOTES_DIR=/srv/files/notes
    export TODO_DIR TODO_FILE NOTES_DIR
fi
