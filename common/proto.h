/* Wire protocol between Term6.app and term6d (the root session daemon).
 * Every frame: [u8 type][u32 length, big endian][payload]                */
#ifndef T6_PROTO_H
#define T6_PROTO_H

#include <stdint.h>

#define T6_SOCK_PATH "/var/tmp/term6d.sock"

enum {
    /* app -> daemon */
    T6_C_NEW    = 1,  /* u16 cols, u16 rows, u8 asRoot, then "shell path\0LANG value" (both may be empty) */
    T6_C_ATTACH = 2,  /* u32 session id, u32 bytes the client already has */
    T6_C_INPUT  = 3,  /* raw bytes for the shell */
    T6_C_RESIZE = 4,  /* u16 cols, u16 rows */
    T6_C_KILL   = 5,  /* kill the attached session */
    T6_C_PING   = 6,

    /* daemon -> app */
    T6_S_SESSION  = 10, /* u32 id (reply to NEW) */
    T6_S_OUTPUT   = 12, /* raw bytes from the shell */
    T6_S_EXIT     = 13, /* u32 exit status */
    T6_S_ATTACHED = 14, /* u8 reset (1 = history was truncated, wipe the screen first), u32 offset of the first replayed byte */
    T6_S_PONG     = 15,
    T6_S_ERROR    = 16  /* text */
};

#endif
