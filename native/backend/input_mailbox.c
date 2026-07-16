#include "input_mailbox.h"

#include <string.h>

void muos_input_mailbox_init(muos_input_mailbox *mailbox) {
    memset(mailbox, 0, sizeof(*mailbox));
}

uint64_t muos_input_mailbox_update(muos_input_mailbox *mailbox,
                                   const float *buttons,
                                   const float *axes) {
    int i;
    for (i = 0; i < MUOS_INPUT_MAILBOX_BUTTONS; i++) {
        if (buttons[i] >= 0.5f && mailbox->previous_buttons[i] < 0.5f)
            mailbox->press_generation[i]++;
        mailbox->previous_buttons[i] = buttons[i];
    }
    memcpy(mailbox->latest_buttons, buttons, sizeof(mailbox->latest_buttons));
    memcpy(mailbox->latest_axes, axes, sizeof(mailbox->latest_axes));
    mailbox->latest_seq++;
    mailbox->pending = 1;
    return mailbox->latest_seq;
}

int muos_input_mailbox_begin_send(muos_input_mailbox *mailbox,
                                  muos_input_snapshot *snapshot) {
    int i;
    if (mailbox->in_flight || !mailbox->pending) return 0;

    memcpy(snapshot->buttons, mailbox->latest_buttons, sizeof(snapshot->buttons));
    memcpy(snapshot->axes, mailbox->latest_axes, sizeof(snapshot->axes));
    snapshot->seq = mailbox->latest_seq;
    for (i = 0; i < MUOS_INPUT_MAILBOX_BUTTONS; i++) {
        snapshot->press_generation[i] = mailbox->press_generation[i];
        snapshot->press_edges[i] = mailbox->press_generation[i] >
                                   mailbox->acked_press_generation[i];
    }
    mailbox->pending = 0;
    mailbox->in_flight = 1;
    return 1;
}

void muos_input_mailbox_complete(muos_input_mailbox *mailbox,
                                 const muos_input_snapshot *snapshot,
                                 int delivered) {
    int i;
    mailbox->in_flight = 0;
    if (!delivered) {
        mailbox->pending = 1;
        return;
    }
    for (i = 0; i < MUOS_INPUT_MAILBOX_BUTTONS; i++) {
        if (snapshot->press_edges[i] &&
            snapshot->press_generation[i] > mailbox->acked_press_generation[i])
            mailbox->acked_press_generation[i] = snapshot->press_generation[i];
        if (mailbox->press_generation[i] > mailbox->acked_press_generation[i])
            mailbox->pending = 1;
    }
}
