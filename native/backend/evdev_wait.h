#ifndef MUOS_EVDEV_WAIT_H
#define MUOS_EVDEV_WAIT_H

#include <poll.h>
#include <stddef.h>

int muos_evdev_wait(struct pollfd *fds, size_t count, int timeout_ms);

#endif
