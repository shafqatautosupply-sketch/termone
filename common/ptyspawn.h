/* Header-only helper shared by the app (local mode) and term6d. */
#ifndef T6_PTYSPAWN_H
#define T6_PTYSPAWN_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <pwd.h>
#include <grp.h>
#include <sys/types.h>
#include <sys/ioctl.h>
#include <termios.h>

/* Setuid-root helper used when the app itself (running as mobile) is asked for a root shell. */
#define T6_ROOT_HELPER "/usr/libexec/term6root"

/* Declared by hand so we do not depend on util.h being present in the SDK. */
extern pid_t forkpty(int *amaster, char *name, struct termios *termp, struct winsize *winp);

static void t6_set_winsize(int master, int cols, int rows)
{
    struct winsize ws;
    memset(&ws, 0, sizeof ws);
    ws.ws_col = (unsigned short)cols;
    ws.ws_row = (unsigned short)rows;
    ioctl(master, TIOCSWINSZ, &ws);
}

/* Starts a login shell on a new pty. Returns the pid (or -1) and stores the
 * non-blocking, close-on-exec master fd in *master.
 *
 * asRoot:  as root (daemon)       -> asRoot=0 drops to the "mobile" user, asRoot=1 stays root
 *          as mobile (app, local) -> asRoot=1 goes through the setuid helper T6_ROOT_HELPER
 * lang:    value for LANG / LC_CTYPE (NULL or "" = en_US.UTF-8)                              */
static pid_t t6_spawn(int *master, const char *shell, int cols, int rows, int asRoot, const char *lang)
{
    struct winsize ws;
    char shellbuf[256], argv0[128], homebuf[256], userbuf[64];
    char e_home[300], e_user[100], e_logname[100], e_shell[300], e_lang[100], e_ctype[100];
    struct passwd *pw;
    int drop = 0, viaHelper = 0;
    uid_t uid = 0;
    gid_t gid = 0;
    const char *base;

    memset(&ws, 0, sizeof ws);
    ws.ws_col = (unsigned short)cols;
    ws.ws_row = (unsigned short)rows;

    snprintf(shellbuf, sizeof shellbuf, "%s", (shell && *shell) ? shell : "/bin/bash");
    if (access(shellbuf, X_OK) != 0) snprintf(shellbuf, sizeof shellbuf, "/bin/bash");
    if (access(shellbuf, X_OK) != 0) snprintf(shellbuf, sizeof shellbuf, "/bin/sh");

    base = strrchr(shellbuf, '/');
    base = base ? base + 1 : shellbuf;
    snprintf(argv0, sizeof argv0, "-%.120s", base);       /* leading '-' = login shell */

    if (getuid() == 0 && !asRoot) {
        pw = getpwnam("mobile");
        drop = (pw != NULL);
    } else if (getuid() != 0 && asRoot && access(T6_ROOT_HELPER, X_OK) == 0) {
        pw = getpwnam("root");
        viaHelper = 1;
    } else {
        pw = getpwuid(getuid());
    }
    snprintf(homebuf, sizeof homebuf, "%s", (pw && pw->pw_dir) ? pw->pw_dir : (viaHelper ? "/var/root" : "/var/mobile"));
    snprintf(userbuf, sizeof userbuf, "%s", (pw && pw->pw_name) ? pw->pw_name : (viaHelper ? "root" : "mobile"));
    if (pw) { uid = pw->pw_uid; gid = pw->pw_gid; }

    const char *lg = (lang && *lang) ? lang : "en_US.UTF-8";
    snprintf(e_home, sizeof e_home, "HOME=%s", homebuf);
    snprintf(e_user, sizeof e_user, "USER=%s", userbuf);
    snprintf(e_logname, sizeof e_logname, "LOGNAME=%s", userbuf);
    snprintf(e_shell, sizeof e_shell, "SHELL=%s", shellbuf);
    snprintf(e_lang, sizeof e_lang, "LANG=%.80s", lg);
    snprintf(e_ctype, sizeof e_ctype, "LC_CTYPE=%.80s", lg);

    char *envp[] = {
        e_home, e_user, e_logname, e_shell, e_lang, e_ctype,
        (char *)"TERM=xterm-256color",
        (char *)"TERM_PROGRAM=Term6",
        (char *)"PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/X11/bin",
        NULL
    };
    char *argv[] = { argv0, NULL };

    pid_t pid = forkpty(master, NULL, NULL, &ws);
    if (pid == 0) {
        if (viaHelper) {
            char *hargv[] = { (char *)"term6root", shellbuf, argv0, NULL };
            execve(T6_ROOT_HELPER, hargv, envp);              /* helper becomes root, then execs the shell */
        }
        if (drop) {
            initgroups(userbuf, (int)gid);
            setgid(gid);
            setuid(uid);
        }
        chdir(homebuf);
        execve(shellbuf, argv, envp);
        _exit(127);
    }
    if (pid > 0) {
        fcntl(*master, F_SETFD, FD_CLOEXEC);
        fcntl(*master, F_SETFL, fcntl(*master, F_GETFL, 0) | O_NONBLOCK);
    }
    return pid;
}

#endif
