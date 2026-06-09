/*
 * ip_lock.h - Per-port client IP lock with live connection awareness
 */

#ifndef _IP_LOCK_H
#define _IP_LOCK_H

#include <stddef.h>

#ifndef INET6_ADDRSTRLEN
#define INET6_ADDRSTRLEN 46
#endif

void ip_lock_init(const char *lock_file, const char *status_file);
void ip_lock_reload(void);
const char *ip_lock_get_locked_ip(void);
void ip_lock_set(const char *ip);
void ip_lock_clear(void);
void ip_lock_write_status(int total_conn, const char *active_ips_json);

#endif
