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
ip_lock_write_status(int total_conn, const char *active_ips_json)
{
    if (status_file_path[0] == '\0') {
        return;
    }

    FILE *f = fopen(status_file_path, "w");
    if (f == NULL) {
        return;
    }

    if (active_ips_json == NULL) {
        active_ips_json = "{}";
    }

    fprintf(f,
            "{\"locked_ip\":\"%s\",\"connections\":%d,\"active_ips\":%s}\n",
            locked_ip, total_conn, active_ips_json);
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

    int keepidle  = 30;
    int keepintvl = 10;
    int keepcnt   = 3;
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
        unsigned int user_timeout = 45000;
        setsockopt(fd, SOL_TCP, TCP_USER_TIMEOUT, &user_timeout, sizeof(user_timeout));
    }
#endif
#else
    (void)fd;
#endif
}
