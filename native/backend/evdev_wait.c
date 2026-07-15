#include "evdev_wait.h"

#include <errno.h>

int muos_evdev_wait(struct pollfd *fds, size_t count, int timeout_ms) {
    int result;
    do {
        result = poll(fds, (nfds_t)count, timeout_ms);
    } while (result < 0 && errno == EINTR);
    return result;
}
