/*
 * term6d - Term6 session daemon.
 *
 * Runs as root (LaunchDaemon). Owns the ptys/shells so they survive Term6.app
 * being suspended or killed. The app connects over a unix socket, attaches to
 * a session and gets the recent output replayed from a ring buffer.
 *
 * Single-threaded select() loop. select() is used on purpose: poll() has had
 * trouble with ptys on older Darwin kernels.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <pwd.h>
#include <sys/types.h>
#include <sys/select.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>

#include "proto.h"
#include "ptyspawn.h"

#define RING_CAP        (256 * 1024)
#define MAX_OUT_QUEUE   (1024 * 1024)
#define MAX_PENDING_IN  (4 * 1024 * 1024)
#define MAX_FRAME       (4 * 1024 * 1024)

typedef struct session session_t;
typedef struct client client_t;

struct session {
    uint32_t id;
    int master;
    pid_t pid;
    int exited;
    int status;
    time_t eof_at;                /* when the pty hit EOF (0 = still open) */
    unsigned char *ring;
    uint32_t total;               /* bytes ever produced */
    unsigned char *pin;           /* input waiting to be written to the pty */
    size_t pinlen;
    client_t *client;
    session_t *next;
};

struct client {
    int fd;
    int dead;
    session_t *sess;
    unsigned char *in;  size_t inlen,  incap;
    unsigned char *out; size_t outlen, outcap;
    client_t *next;
};

static session_t *g_sessions = NULL;
static client_t  *g_clients  = NULL;
static uint32_t   g_next_id  = 1;
static uid_t      g_mobile_uid = (uid_t)-1;

/* ---------- little helpers ---------- */

static void put32(unsigned char *p, uint32_t v)
{ p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v; }
static uint32_t get32(const unsigned char *p)
{ return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3]; }
static uint32_t get16(const unsigned char *p)
{ return ((uint32_t)p[0] << 8) | p[1]; }

static void on_chld(int sig) { (void)sig; }

static int peer_uid(int fd, uid_t *uid)
{
#ifdef __APPLE__
    gid_t gid;
    return getpeereid(fd, uid, &gid);
#else
    struct ucred cr;
    socklen_t l = sizeof cr;
    if (getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &cr, &l) != 0) return -1;
    *uid = cr.uid;
    return 0;
#endif
}

static void set_nonblock_cloexec(int fd)
{
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);
    fcntl(fd, F_SETFD, FD_CLOEXEC);
}

/* ---------- client output queue ---------- */

static void queue_frame(client_t *c, uint8_t type, const void *payload, uint32_t len)
{
    if (c->dead) return;
    if (c->outlen + 5 + len > MAX_OUT_QUEUE) { c->dead = 1; return; }  /* it can re-attach and replay */
    if (c->outlen + 5 + len > c->outcap) {
        size_t ncap = c->outcap ? c->outcap : 4096;
        while (ncap < c->outlen + 5 + len) ncap *= 2;
        unsigned char *n = realloc(c->out, ncap);
        if (!n) { c->dead = 1; return; }
        c->out = n; c->outcap = ncap;
    }
    c->out[c->outlen] = type;
    put32(c->out + c->outlen + 1, len);
    if (len) memcpy(c->out + c->outlen + 5, payload, len);
    c->outlen += 5 + len;
}

static void flush_client(client_t *c)
{
    while (c->outlen > 0) {
        ssize_t n = write(c->fd, c->out, c->outlen);
        if (n > 0) {
            memmove(c->out, c->out + n, c->outlen - n);
            c->outlen -= n;
        } else if (n < 0 && (errno == EAGAIN || errno == EINTR)) {
            return;
        } else {
            c->dead = 1;
            return;
        }
    }
}

/* ---------- sessions ---------- */

static void ring_append(session_t *s, const unsigned char *d, size_t n)
{
    if (n > RING_CAP) {
        size_t skip = n - RING_CAP;
        d += skip;
        s->total += (uint32_t)skip;
        n = RING_CAP;
    }
    size_t idx = s->total % RING_CAP;
    size_t first = RING_CAP - idx;
    if (first > n) first = n;
    memcpy(s->ring + idx, d, first);
    if (n > first) memcpy(s->ring, d + first, n - first);
    s->total += (uint32_t)n;
}

static session_t *find_session(uint32_t id)
{
    session_t *s;
    for (s = g_sessions; s; s = s->next) if (s->id == id) return s;
    return NULL;
}

static session_t *new_session(const char *shell, int cols, int rows, int asRoot, const char *lang)
{
    if (cols < 10)  cols = 10;
    if (cols > 500) cols = 500;
    if (rows < 2)   rows = 2;
    if (rows > 300) rows = 300;

    session_t *s = calloc(1, sizeof *s);
    if (!s) return NULL;
    s->ring = malloc(RING_CAP);
    if (!s->ring) { free(s); return NULL; }
    s->pid = t6_spawn(&s->master, shell, cols, rows, asRoot, lang);
    if (s->pid < 0) { free(s->ring); free(s); return NULL; }
    s->id = g_next_id++;
    s->next = g_sessions;
    g_sessions = s;
    return s;
}

static void free_session(session_t *s)
{
    session_t **pp;
    for (pp = &g_sessions; *pp; pp = &(*pp)->next) {
        if (*pp == s) { *pp = s->next; break; }
    }
    if (s->client) s->client->sess = NULL;
    if (s->master >= 0) close(s->master);
    free(s->ring);
    free(s->pin);
    free(s);
}

static void session_write_input(session_t *s, const unsigned char *p, size_t len)
{
    if (s->pinlen + len > MAX_PENDING_IN) return;
    unsigned char *n = realloc(s->pin, s->pinlen + len);
    if (!n) return;
    s->pin = n;
    memcpy(s->pin + s->pinlen, p, len);
    s->pinlen += len;
}

static void session_flush_input(session_t *s)
{
    while (s->pinlen > 0 && s->master >= 0) {
        ssize_t n = write(s->master, s->pin, s->pinlen);
        if (n > 0) {
            memmove(s->pin, s->pin + n, s->pinlen - n);
            s->pinlen -= n;
        } else {
            return;               /* EAGAIN: try again when select says writable */
        }
    }
}

static void attach(client_t *c, session_t *s)
{
    if (s->client && s->client != c) {         /* only one viewer: kick the old one */
        s->client->sess = NULL;
        s->client->dead = 1;
    }
    s->client = c;
    c->sess = s;
}

static void send_replay(client_t *c, session_t *s, uint32_t since)
{
    uint32_t start = s->total > RING_CAP ? s->total - RING_CAP : 0;
    unsigned char hdr[5];
    hdr[0] = 0;
    if (since > s->total || since < start) { since = start; hdr[0] = 1; }
    put32(hdr + 1, since);                     /* offset of the first byte we are about to replay */
    queue_frame(c, T6_S_ATTACHED, hdr, 5);

    uint32_t off = since;
    while (off < s->total) {
        uint32_t idx = off % RING_CAP;
        uint32_t chunk = s->total - off;
        if (chunk > RING_CAP - idx) chunk = RING_CAP - idx;
        if (chunk > 16384) chunk = 16384;
        queue_frame(c, T6_S_OUTPUT, s->ring + idx, chunk);
        off += chunk;
    }
}

/* ---------- frame handling ---------- */

static void send_error(client_t *c, const char *msg)
{
    queue_frame(c, T6_S_ERROR, msg, (uint32_t)strlen(msg));
}

static void handle_frame(client_t *c, uint8_t type, const unsigned char *p, uint32_t len)
{
    switch (type) {
    case T6_C_NEW: {
        if (len < 5 || c->sess) { send_error(c, "bad NEW"); break; }
        int cols = (int)get16(p), rows = (int)get16(p + 2), asRoot = p[4];
        char shell[256], lang[64];
        size_t rest = len - 5, sl = rest;
        const unsigned char *nul = memchr(p + 5, 0, rest);          /* payload tail is "shell\0lang" */
        size_t ll = 0;
        if (nul) { sl = (size_t)(nul - (p + 5)); ll = rest - sl - 1; }
        if (sl > sizeof shell - 1) sl = sizeof shell - 1;
        if (ll > sizeof lang - 1) ll = sizeof lang - 1;
        memcpy(shell, p + 5, sl);
        shell[sl] = 0;
        if (nul) memcpy(lang, nul + 1, ll);
        lang[ll] = 0;
        session_t *s = new_session(shell, cols, rows, asRoot, lang);
        if (!s) { send_error(c, "could not start shell"); break; }
        attach(c, s);
        unsigned char b[4];
        put32(b, s->id);
        queue_frame(c, T6_S_SESSION, b, 4);
        break;
    }
    case T6_C_ATTACH: {
        if (len < 8) { send_error(c, "bad ATTACH"); break; }
        session_t *s = find_session(get32(p));
        if (!s) { send_error(c, "no such session"); break; }
        attach(c, s);
        send_replay(c, s, get32(p + 4));
        break;
    }
    case T6_C_INPUT:
        if (c->sess && !c->sess->exited) {
            session_write_input(c->sess, p, len);
            session_flush_input(c->sess);
        }
        break;
    case T6_C_RESIZE:
        if (c->sess && len >= 4 && c->sess->master >= 0)
            t6_set_winsize(c->sess->master, (int)get16(p), (int)get16(p + 2));
        break;
    case T6_C_KILL:
        if (c->sess) kill(c->sess->pid, SIGHUP);
        break;
    case T6_C_PING:
        queue_frame(c, T6_S_PONG, NULL, 0);
        break;
    default:
        break;
    }
}

static void client_read(client_t *c)
{
    unsigned char buf[8192];
    ssize_t n = read(c->fd, buf, sizeof buf);
    if (n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR)) { c->dead = 1; return; }
    if (n < 0) return;

    if (c->inlen + n > c->incap) {
        size_t ncap = c->incap ? c->incap : 8192;
        while (ncap < c->inlen + n) ncap *= 2;
        unsigned char *nb = realloc(c->in, ncap);
        if (!nb) { c->dead = 1; return; }
        c->in = nb; c->incap = ncap;
    }
    memcpy(c->in + c->inlen, buf, n);
    c->inlen += n;

    while (c->inlen >= 5 && !c->dead) {
        uint32_t len = get32(c->in + 1);
        if (len > MAX_FRAME) { c->dead = 1; return; }
        if (c->inlen < 5 + (size_t)len) break;
        uint8_t type = c->in[0];
        handle_frame(c, type, c->in + 5, len);
        memmove(c->in, c->in + 5 + len, c->inlen - 5 - len);
        c->inlen -= 5 + len;
    }
}

static void free_client(client_t *c)
{
    client_t **pp;
    for (pp = &g_clients; *pp; pp = &(*pp)->next) {
        if (*pp == c) { *pp = c->next; break; }
    }
    if (c->sess && c->sess->client == c) c->sess->client = NULL;
    close(c->fd);
    free(c->in);
    free(c->out);
    free(c);
}

/* ---------- main loop ---------- */

static void session_read(session_t *s)
{
    unsigned char buf[16384];
    int i;
    for (i = 0; i < 4; i++) {
        ssize_t n = read(s->master, buf, sizeof buf);
        if (n > 0) {
            ring_append(s, buf, (size_t)n);
            if (s->client) queue_frame(s->client, T6_S_OUTPUT, buf, (uint32_t)n);
        } else if (n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR)) {
            /* EOF/EIO: the shell side is gone. Reaping decides the session's fate. */
            if (!s->exited) { kill(s->pid, SIGHUP); }
            close(s->master);
            s->master = -1;
            s->eof_at = time(NULL);
            return;
        } else {
            return;
        }
    }
}

static void reap_and_finish(void)
{
    session_t *s = g_sessions, *next;
    while (s) {
        next = s->next;

        if (!s->exited) {
            int st = 0;
            if (waitpid(s->pid, &st, WNOHANG) == s->pid) { s->exited = 1; s->status = st; }
            else if (s->master < 0 && s->eof_at && time(NULL) - s->eof_at > 3) kill(s->pid, SIGKILL);
        }

        if (s->exited) {
            /* the shell is gone: pick up the last output, then tell the viewer */
            if (s->master >= 0) {
                unsigned char buf[16384];
                ssize_t n;
                while ((n = read(s->master, buf, sizeof buf)) > 0) {
                    ring_append(s, buf, (size_t)n);
                    if (s->client) queue_frame(s->client, T6_S_OUTPUT, buf, (uint32_t)n);
                }
                close(s->master);
                s->master = -1;
            }
            if (s->client) {
                unsigned char b[4];
                put32(b, (uint32_t)s->status);
                queue_frame(s->client, T6_S_EXIT, b, 4);
            }
            free_session(s);
        }
        s = next;
    }
}

int main(void)
{
    const char *path = getenv("T6_SOCK");
    if (!path || !*path) path = T6_SOCK_PATH;

    signal(SIGPIPE, SIG_IGN);
    signal(SIGCHLD, on_chld);          /* only to interrupt select() */

    struct passwd *pw = getpwnam("mobile");
    if (pw) g_mobile_uid = pw->pw_uid;

    int lfd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (lfd < 0) { perror("socket"); return 1; }
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof addr);
    addr.sun_family = AF_UNIX;
    snprintf(addr.sun_path, sizeof addr.sun_path, "%s", path);
    unlink(path);
    if (bind(lfd, (struct sockaddr *)&addr, sizeof addr) != 0) { perror("bind"); return 1; }
    chmod(path, 0600);
    if (pw) chown(path, pw->pw_uid, pw->pw_gid);
    if (listen(lfd, 8) != 0) { perror("listen"); return 1; }
    set_nonblock_cloexec(lfd);

    for (;;) {
        fd_set rf, wf;
        int maxfd = lfd;
        client_t *c;
        session_t *s;

        FD_ZERO(&rf); FD_ZERO(&wf);
        FD_SET(lfd, &rf);
        for (c = g_clients; c; c = c->next) {
            FD_SET(c->fd, &rf);
            if (c->outlen > 0) FD_SET(c->fd, &wf);
            if (c->fd > maxfd) maxfd = c->fd;
        }
        for (s = g_sessions; s; s = s->next) {
            if (s->master < 0) continue;
            if (!s->client || s->client->outlen < 256 * 1024) FD_SET(s->master, &rf);
            if (s->pinlen > 0) FD_SET(s->master, &wf);
            if (s->master > maxfd) maxfd = s->master;
        }

        struct timeval tv = { 2, 0 };
        int n = select(maxfd + 1, &rf, &wf, NULL, &tv);
        if (n < 0 && errno != EINTR) { perror("select"); sleep(1); continue; }

        if (n > 0) {
            if (FD_ISSET(lfd, &rf)) {
                int fd = accept(lfd, NULL, NULL);
                if (fd >= 0) {
                    uid_t uid = (uid_t)-1;
                    if (peer_uid(fd, &uid) == 0 && (uid == 0 || uid == g_mobile_uid)) {
                        client_t *nc = calloc(1, sizeof *nc);
                        if (nc) {
                            nc->fd = fd;
                            set_nonblock_cloexec(fd);
                            nc->next = g_clients;
                            g_clients = nc;
                        } else close(fd);
                    } else close(fd);
                }
            }
            for (c = g_clients; c; c = c->next)
                if (FD_ISSET(c->fd, &rf)) client_read(c);
            for (s = g_sessions; s; s = s->next) {
                if (s->master < 0) continue;
                if (FD_ISSET(s->master, &wf)) session_flush_input(s);
                if (FD_ISSET(s->master, &rf)) session_read(s);
            }
            for (c = g_clients; c; c = c->next)
                if (c->outlen > 0) flush_client(c);
        }

        reap_and_finish();

        for (c = g_clients; c; ) {
            client_t *nx = c->next;
            if (c->dead) {
                if (c->outlen > 0 && c->sess == NULL) flush_client(c);   /* best effort: deliver EXIT/errors */
                free_client(c);
            }
            c = nx;
        }
        for (c = g_clients; c; c = c->next)       /* EXIT frames queued by reap_and_finish */
            if (c->outlen > 0) flush_client(c);
    }
    return 0;
}
