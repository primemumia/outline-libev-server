/*
 * ip_lock.h - Per-port client IP lock with live connection awareness
 */

#ifndef _IP_LOCK_H
#define _IP_LOCK_H

#include <stddef.h>

#ifndef INET6_ADDRSTRLEN
#define INET6_ADDRSTRLEN 46
#endif

#define IP_LOCK_RUNTIME_DIR "/run/shadowsocks-manager"
#define IP_LOCK_IDLE_TIMEOUT_SEC 10
#define IP_LOCK_KEEPIDLE_SEC 4
#define IP_LOCK_KEEPINTVL_SEC 2
#define IP_LOCK_KEEPCNT 3
#define IP_LOCK_USER_TIMEOUT_MS 10000

void ip_lock_sidecar_path(char *out, size_t out_size, const char *port, const char *suffix);
void ip_lock_ensure_runtime_dir(void);
int ip_lock_is_enabled(void);
int ip_lock_idle_timeout(void);
void ip_lock_configure_client_socket(int fd);

void ip_lock_init(const char *lock_file, const char *status_file);
void ip_lock_reload(void);
const char *ip_lock_get_locked_ip(void);
void ip_lock_set(const char *ip);
void ip_lock_clear(void);
void ip_lock_write_status(int total_conn, const char *active_ips_json);

#endif
