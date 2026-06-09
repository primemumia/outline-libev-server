/*
 * ip_lock.c - Per-port client IP lock with live connection awareness
 */

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#ifndef __MINGW32__
#include <netinet/tcp.h>
#endif

#include "ip_lock.h"
#include "utils.h"

static char lock_file_path[512];
static char status_file_path[512];
static char locked_ip[INET6_ADDRSTRLEN];
static time_t lock_file_mtime = 0;
static int ip_lock_enabled     = 0;

void
ip_lock_sidecar_path(char *out, size_t out_size, const char *port, const char *suffix)
{
    snprintf(out, out_size, IP_LOCK_RUNTIME_DIR "/.shadowsocks_%s.%s", port, suffix);
}

void
ip_lock_ensure_runtime_dir(void)
{
    mkdir(IP_LOCK_RUNTIME_DIR, S_IRWXU);
}

void
ip_lock_init(const char *lock_file, const char *status_file)
{
    ip_lock_enabled = 1;
    ip_lock_ensure_runtime_dir();
    if (lock_file != NULL) {
        strncpy(lock_file_path, lock_file, sizeof(lock_file_path) - 1);
        lock_file_path[sizeof(lock_file_path) - 1] = '\0';
    }
    if (status_file != NULL) {
        strncpy(status_file_path, status_file, sizeof(status_file_path) - 1);
        status_file_path[sizeof(status_file_path) - 1] = '\0';
    }
    locked_ip[0] = '\0';
    ip_lock_reload();
}

void
ip_lock_reload(void)
{
    if (lock_file_path[0] == '\0') {
        return;
    }

    struct stat st;
    if (stat(lock_file_path, &st) != 0) {
        locked_ip[0] = '\0';
        lock_file_mtime = 0;
        return;
    }

    if (st.st_mtime == lock_file_mtime) {
        return;
    }

    lock_file_mtime = st.st_mtime;

    FILE *f = fopen(lock_file_path, "r");
    if (f == NULL) {
        locked_ip[0] = '\0';
        return;
    }

    if (fgets(locked_ip, sizeof(locked_ip), f) == NULL) {
        locked_ip[0] = '\0';
    } else {
        size_t len = strlen(locked_ip);
        while (len > 0 && (locked_ip[len - 1] == '\n' || locked_ip[len - 1] == '\r' ||
                           locked_ip[len - 1] == ' ')) {
            locked_ip[--len] = '\0';
        }
    }
    fclose(f);
}

const char *
ip_lock_get_locked_ip(void)
{
    return locked_ip;
}

void
ip_lock_set(const char *ip)
{
    if (ip == NULL || ip[0] == '\0') {
        return;
    }

    strncpy(locked_ip, ip, sizeof(locked_ip) - 1);
    locked_ip[sizeof(locked_ip) - 1] = '\0';

    if (lock_file_path[0] == '\0') {
        return;
    }

    FILE *f = fopen(lock_file_path, "w");
    if (f == NULL) {
        return;
    }
    fprintf(f, "%s\n", locked_ip);
    fclose(f);

    struct stat st;
    if (stat(lock_file_path, &st) == 0) {
        lock_file_mtime = st.st_mtime;
    }
}

void
ip_lock_clear(void)
{
    locked_ip[0] = '\0';
    lock_file_mtime = 0;

    if (lock_file_path[0] != '\0') {
        unlink(lock_file_path);
    }
}

void
ip_lock_format_active_ips(const char *const *ips, int ip_count,
                          char *out, size_t out_size)
{
    int pos = 0;
    int i;

    if (out == NULL || out_size == 0) {
        return;
    }

    if (ips == NULL || ip_count <= 0) {
        snprintf(out, out_size, "[]");
        return;
    }

    pos += snprintf(out + pos, out_size - pos, "[");
    for (i = 0; i < ip_count; i++) {
        int n;
        if (ips[i] == NULL || ips[i][0] == '\0') {
            continue;
        }
        if (pos > 1 && pos < (int)out_size - 1) {
            pos += snprintf(out + pos, out_size - pos, ",");
        }
        if (pos >= (int)out_size - 2) {
            break;
        }
        n = snprintf(out + pos, out_size - pos, "\"%s\"", ips[i]);
        if (n < 0 || pos + n >= (int)out_size - 2) {
            break;
        }
        pos += n;
    }
    snprintf(out + pos, out_size - pos, "]");
}

static void
ip_lock_json_escape(const char *in, char *out, size_t out_size)
{
    size_t pos = 0;

    if (out == NULL || out_size == 0) {
        return;
    }

    if (in == NULL) {
        out[0] = '\0';
        return;
    }

    for (; *in != '\0' && pos + 1 < out_size; in++) {
        if (*in == '"' || *in == '\\') {
            if (pos + 2 >= out_size) {
                break;
            }
            out[pos++] = '\\';
        }
        out[pos++] = *in;
    }
    out[pos] = '\0';
}

void
ip_lock_write_status(int total_conn, const char *active_ips_json)
{
    char locked_esc[INET6_ADDRSTRLEN * 2];

    if (status_file_path[0] == '\0') {
        return;
    }

    FILE *f = fopen(status_file_path, "w");
    if (f == NULL) {
        return;
    }

    if (active_ips_json == NULL) {
        active_ips_json = "[]";
    }

    ip_lock_json_escape(locked_ip, locked_esc, sizeof(locked_esc));

    fprintf(f,
            "{\"locked_ip\":\"%s\",\"connections\":%d,\"active_ips\":%s}\n",
            locked_esc, total_conn, active_ips_json);
    fclose(f);
}

int
ip_lock_is_enabled(void)
{
    return ip_lock_enabled;
}

int
ip_lock_idle_timeout(void)
{
    return IP_LOCK_IDLE_TIMEOUT_SEC;
}

void
ip_lock_configure_client_socket(int fd)
{
#ifndef __MINGW32__
    int on = 1;

    setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &on, sizeof(on));

    int keepidle  = IP_LOCK_KEEPIDLE_SEC;
    int keepintvl = IP_LOCK_KEEPINTVL_SEC;
    int keepcnt   = IP_LOCK_KEEPCNT;
#ifdef TCP_KEEPIDLE
    setsockopt(fd, SOL_TCP, TCP_KEEPIDLE, &keepidle, sizeof(keepidle));
#endif
#ifdef TCP_KEEPINTVL
    setsockopt(fd, SOL_TCP, TCP_KEEPINTVL, &keepintvl, sizeof(keepintvl));
#endif
#ifdef TCP_KEEPCNT
    setsockopt(fd, SOL_TCP, TCP_KEEPCNT, &keepcnt, sizeof(keepcnt));
#endif
#ifdef TCP_USER_TIMEOUT
    {
        unsigned int user_timeout = IP_LOCK_USER_TIMEOUT_MS;
        setsockopt(fd, SOL_TCP, TCP_USER_TIMEOUT, &user_timeout, sizeof(user_timeout));
    }
#endif
#else
    (void)fd;
#endif
}
