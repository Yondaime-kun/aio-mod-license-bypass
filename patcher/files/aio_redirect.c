/* aio_redirect.c — LD_PRELOAD hook: redirect license host to 127.0.0.1
 *
 * Works regardless of how the engine resolves/connects, and without root.
 * Build:  gcc -shared -fPIC -O2 -o libaio_redirect.so aio_redirect.c -ldl
 * Use:    LD_PRELOAD=/path/libaio_redirect.so aio
 *
 * Redirects:
 *   - getaddrinfo("aio.scwill.store", ...)  -> 127.0.0.1
 *   - connect() to the real server IPs      -> 127.0.0.1
 *
 * Fail-open: if anything goes wrong, the real function is called.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <netdb.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <stdlib.h>
#include <stdio.h>

static const char *REDIRECT_HOST = "aio.scwill.store";
static const char *REDIRECT_IP   = "127.0.0.1";
static const char *BLOCKED_IPS[] = { "172.67.143.135", "104.21.46.254", NULL };

static void aio_log(const char *msg) {
    const char *p = getenv("AIO_REDIRECT_LOG");
    if (!p) p = "/tmp/aio_redirect.log";
    FILE *f = fopen(p, "a");
    if (f) { fprintf(f, "[ldpreload] %s\n", msg); fclose(f); }
}

typedef int (*getaddrinfo_t)(const char *, const char *,
                             const struct addrinfo *, struct addrinfo **);
typedef int (*connect_t)(int, const struct sockaddr *, socklen_t);

int getaddrinfo(const char *node, const char *service,
                const struct addrinfo *hints, struct addrinfo **res) {
    static getaddrinfo_t real = NULL;
    if (!real) real = (getaddrinfo_t)dlsym(RTLD_NEXT, "getaddrinfo");
    if (node && strcmp(node, REDIRECT_HOST) == 0) {
        aio_log("getaddrinfo aio.scwill.store -> 127.0.0.1");
        return real(REDIRECT_IP, service, hints, res);
    }
    return real(node, service, hints, res);
}

int connect(int fd, const struct sockaddr *addr, socklen_t len) {
    static connect_t real = NULL;
    if (!real) real = (connect_t)dlsym(RTLD_NEXT, "connect");
    if (addr && addr->sa_family == AF_INET && len >= sizeof(struct sockaddr_in)) {
        const struct sockaddr_in *in = (const struct sockaddr_in *)addr;
        char ip[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &in->sin_addr, ip, sizeof(ip));
        for (int i = 0; BLOCKED_IPS[i]; i++) {
            if (strcmp(ip, BLOCKED_IPS[i]) == 0) {
                struct sockaddr_in lo = *in;
                lo.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
                aio_log("connect blocked-ip -> 127.0.0.1");
                return real(fd, (struct sockaddr *)&lo, len);
            }
        }
    }
    return real(fd, addr, len);
}
