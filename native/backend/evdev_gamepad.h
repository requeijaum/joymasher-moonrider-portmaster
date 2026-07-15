/* evdev_gamepad.h — API do leitor evdev para o launcher WPE. */
#ifndef MUOS_EVDEV_GAMEPAD_H
#define MUOS_EVDEV_GAMEPAD_H

#define MUOS_NBTN  17
#define MUOS_NAXES 4

/* Inicia a thread de leitura de /dev/input/eventN. */
void muos_gamepad_start(void);
/* Para a thread e fecha os fds. */
void muos_gamepad_stop(void);
/* Copia snapshot: out_btn[17] (0..1), out_ax[4] (-1..1). Retorna 1 se mudou. */
int  muos_gamepad_snapshot(float out_btn[MUOS_NBTN], float out_ax[MUOS_NAXES]);

#endif
