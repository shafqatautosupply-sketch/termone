/*
 * term6root - tiny setuid-root launcher.
 *
 * Term6.app (running as mobile) forks a pty and execs this instead of the shell when
 * "Run Shell as Root" is on and Persistent Sessions (term6d) is off. We become root and
 * exec the shell with the environment the app prepared.
 *
 *   usage: term6root <shell> <argv0>      e.g.  term6root /bin/bash -bash
 *
 * Only root and "mobile" may use it. Installed setuid by the package postinst (chmod 4755).
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <pwd.h>
#include <grp.h>

int main(int argc, char **argv, char **envp)
{
    if (argc < 3) {
        fprintf(stderr, "usage: term6root <shell> <argv0>\n");
        return 2;
    }

    uid_t caller = getuid();
    struct passwd *m = getpwnam("mobile");
    if (caller != 0 && !(m && caller == m->pw_uid)) {
        fprintf(stderr, "term6root: not permitted\n");
        return 1;
    }

    if (setgid(0) != 0 || setuid(0) != 0) {
        fprintf(stderr, "term6root: not setuid root (reinstall the package or chmod 4755 %s)\n", argv[0]);
        return 1;
    }
    initgroups("root", 0);

    const char *home = getenv("HOME");
    if (chdir(home && *home ? home : "/var/root") != 0) chdir("/");

    char *nargv[] = { argv[2], NULL };
    execve(argv[1], nargv, envp);
    perror("term6root: exec");
    return 127;
}
