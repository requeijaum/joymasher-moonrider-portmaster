#include "../native/backend/evdev_wait.h"

#include <assert.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

int main(void) {
    int p[2];
    assert(pipe(p) == 0);

    struct pollfd fd = { .fd = p[0], .events = POLLIN, .revents = 0 };
    assert(muos_evdev_wait(&fd, 1, 5) == 0);

    uint8_t value = 0x5a;
    assert(write(p[1], &value, 1) == 1);
    fd.revents = 0;
    assert(muos_evdev_wait(&fd, 1, 100) == 1);
    assert((fd.revents & POLLIN) != 0);

    close(p[0]);
    close(p[1]);
    puts("test-evdev-wait: OK");
    return 0;
}
