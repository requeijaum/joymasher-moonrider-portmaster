/*
 * evdev_gamepad.c  —  Leitor evdev -> estado gamepad W3C standard, para o launcher WPE.
 *
 * Objetivo: rodar numa thread, abrir TODOS os /dev/input/eventN, mesclar eventos
 * (funciona tanto para joydev unico quanto para gpio-keys + sticks separados),
 * traduzir codigos KEY e ABS para os 17 botoes + 4 eixos do W3C Standard Mapping,
 * e sinalizar o main loop (GLib) para empurrar o estado ao WebView via
 * window.__muos_pushGamepad(btn[], ax[]).
 *
 * NAO chama WebKit diretamente da thread. Usa um snapshot atomico + flag "dirty";
 * o main loop (g_timeout) le o snapshot e injeta o JS. Evita problemas de threading
 * com a WebView (que deve ser tocada so na thread do GMainLoop).
 *
 * Mapa de codigos: baseado em gamecontrollerdb "Anbernic Handheld" (H700/muOS).
 * Marcado CONFIRMAR onde depende de evtest no device. A tabela e editavel: codigos
 * desconhecidos sao logados, permitindo ajuste sem mexer na logica.
 *
 * Compilar junto do launcher: cc ... moonrider-launch.c evdev_gamepad.c -lpthread
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <linux/input.h>
#include "evdev_wait.h"

/* ---- Indices W3C Standard ---- */
enum {
  B_A=0, B_B=1, B_X=2, B_Y=3,
  B_L1=4, B_R1=5, B_L2=6, B_R2=7,
  B_SELECT=8, B_START=9, B_L3=10, B_R3=11,
  B_UP=12, B_DOWN=13, B_LEFT=14, B_RIGHT=15,
  B_GUIDE=16, NBTN=17
};
enum { AX_LX=0, AX_LY=1, AX_RX=2, AX_RY=3, NAXES=4 };

/* Estado compartilhado thread -> main loop */
typedef struct {
  float btn[NBTN];
  float ax[NAXES];
  int dirty;               /* protegido por lock */
  pthread_mutex_t lock;
} muos_pad_state;

static muos_pad_state g_pad = { {0}, {0}, 0, PTHREAD_MUTEX_INITIALIZER };
static atomic_bool g_run = ATOMIC_VAR_INIT(false);

/* ---- Traducao de codigo evdev de botao -> indice standard ----
 * MAPA CORRIGIDO 2026-07-13 por captura evtest no RG40xx H (event1, muOS-Keys).
 * Os codigos evdev deste device estao ROTACIONADOS vs a convencao usual:
 *   fisico BAIXO    -> BTN_EAST  (305)   [nao BTN_SOUTH!]
 *   fisico DIREITA  -> BTN_SOUTH (304)   [nao BTN_EAST!]
 *   fisico CIMA     -> BTN_NORTH (307)
 *   fisico ESQUERDA -> BTN_C     (306)   [nao BTN_WEST!]
 * W3C Standard positional: baixo=0(A/confirmar), direita=1(B), esq=2(X), cima=3(Y).
 * Entao mapeamos pela POSICAO FISICA (nao pelo nome do codigo). */
static int map_key(int code) {
  switch (code) {
    /* Faces — por POSICAO FISICA confirmada no device (codigos rotacionados) */
    case BTN_EAST:   return B_A;      /* fisico BAIXO   -> 0 (A/confirmar) CORRIGIDO */
    case BTN_SOUTH:  return B_B;      /* fisico DIREITA -> 1 (B/voltar)    CORRIGIDO */
    case BTN_C:      return B_X;      /* fisico ESQUERDA-> 2 (X)           CORRIGIDO */
    case BTN_NORTH:  return B_Y;      /* fisico CIMA    -> 3 (Y)           CONFIRMADO */
    case BTN_WEST:   return B_X;      /* fallback: alguns firmwares usam WEST p/ esq */
    case BTN_TL:     return B_L1;     /* 310 */
    case BTN_TR:     return B_R1;     /* 311 */
    case BTN_TL2:    return B_L2;     /* 312 */
    case BTN_TR2:    return B_R2;     /* 313 */
    case BTN_SELECT: return B_SELECT; /* 314 */
    case BTN_START:  return B_START;  /* 315 */
    case BTN_MODE:   return B_GUIDE;  /* 316 */
    case BTN_Z:      return B_R3;     /* 309 extra */
    case KEY_GOTO:   return B_GUIDE;  /* 354 botao funcao/menu */
    case BTN_THUMBL: return B_L3;     /* 0x13d (se existir) */
    case BTN_THUMBR: return B_R3;     /* 0x13e (se existir) */
    /* DPad como botoes (fallback; neste device vem por ABS_HAT0X/Y) */
    case BTN_DPAD_UP:    return B_UP;
    case BTN_DPAD_DOWN:  return B_DOWN;
    case BTN_DPAD_LEFT:  return B_LEFT;
    case BTN_DPAD_RIGHT: return B_RIGHT;
    /* gpio-keys teclado: DPad OK, mas KEY_ENTER/KEY_ESC REMOVIDOS — o muOS gpio-keys
     * emite KEY_ESC/KEY_ENTER/KEY_POWER p/ navegacao do sistema e vazavam p/ btn[8]/btn[9]
     * disparando o combo SELECT+START FALSO (jogo saia sozinho apos o audio). O combo real
     * usa BTN_SELECT(314)/BTN_START(315) do gamepad fisico, mapeados acima. */
    case KEY_UP:    return B_UP;
    case KEY_DOWN:  return B_DOWN;
    case KEY_LEFT:  return B_LEFT;
    case KEY_RIGHT: return B_RIGHT;
    default: return -1;
  }
}

/* Aplica um eixo ABS ao estado, normalizando para -1..1.
 * DPad via ABS_HAT0X/Y (-1/0/+1) vira botoes. Sticks viram axes. */
static int apply_abs(muos_pad_state *p, int code,
                     int value, int min, int max) {
  float norm = 0.0f;
  if (max > min) {
    norm = ( (float)(value - min) / (float)(max - min) ) * 2.0f - 1.0f;
  }
  switch (code) {
    /* RG40xx H (muOS-Keys) NAO expoe ABS_X nem ABS_RX. Eixos reais (evtest):
     * ABS_Y=1, ABS_Z=2, ABS_RY=4, ABS_RZ=5, range -4096..4096.
     * MAPA CORRIGIDO 2026-07-13 por captura evtest (analogico esquerdo):
     *   CIMA    -> ABS_Z = -4096  => ABS_Z e o eixo Y (cima=negativo, bate com W3C)
     *   DIREITA -> ABS_Y = +4096  => ABS_Y e o eixo X (direita=positivo, bate com W3C)
     * O mapa ANTIGO (ABS_Z=LX, ABS_Y=LY) trocava X<->Y => stick girado -90 graus.
     *   left stick  X = ABS_Y,  Y = ABS_Z
     *   right stick X = ABS_RY, Y = ABS_RZ (mesma troca por simetria) */
    case ABS_Y:  p->ax[AX_LX] = norm; break;   /* left X  (era LY) */
    case ABS_Z:  p->ax[AX_LY] = norm; break;   /* left Y  (era LX) */
    case ABS_RY: p->ax[AX_RX] = norm; break;   /* right X (era RY) */
    case ABS_RZ: p->ax[AX_RY] = norm; break;   /* right Y (era RX) */
    /* fallback caso um device exponha ABS_X/ABS_RX */
    case ABS_X:  p->ax[AX_LX] = norm; break;
    case ABS_RX: p->ax[AX_RX] = norm; break;
    case ABS_HAT0X:
      p->btn[B_LEFT]  = (value < 0) ? 1.0f : 0.0f;
      p->btn[B_RIGHT] = (value > 0) ? 1.0f : 0.0f;
      break;
    case ABS_HAT0Y:
      p->btn[B_UP]   = (value < 0) ? 1.0f : 0.0f;
      p->btn[B_DOWN] = (value > 0) ? 1.0f : 0.0f;
      break;
    default: return 0;
  }
  return 1;
}

/* Guarda min/max por (fd,code). Devices distintos podem expor o mesmo ABS com
 * ranges diferentes; um cache global por codigo distorcia a normalizacao. */
#define ABS_CACHE 64
#define MAX_FDS 16
static int abs_min[MAX_FDS][ABS_CACHE];
static int abs_max[MAX_FDS][ABS_CACHE];
static int abs_known[MAX_FDS][ABS_CACHE];

static void prime_abs_range(int fd, int slot) {
  for (int c = 0; c < ABS_CACHE; c++) {
    struct input_absinfo ai;
    if (ioctl(fd, EVIOCGABS((unsigned int)c), &ai) == 0 && (ai.maximum != ai.minimum)) {
      abs_min[slot][c] = ai.minimum;
      abs_max[slot][c] = ai.maximum;
      abs_known[slot][c] = 1;
    }
  }
}

static void *evdev_thread(void *arg) {
  (void)arg;
  struct pollfd fds[MAX_FDS]; int nfd = 0;
  DIR *d = opendir("/dev/input");
  if (d) {
    struct dirent *de;
    while ((de = readdir(d)) && nfd < MAX_FDS) {
      if (strncmp(de->d_name, "event", 5) != 0) continue;
      char path[300];
      snprintf(path, sizeof(path), "/dev/input/%s", de->d_name);
      int fd = open(path, O_RDONLY | O_NONBLOCK);
      if (fd < 0) continue;
      /* filtra: so aceita nós que tenham EV_KEY ou EV_ABS */
      unsigned long evbit = 0;
      if (ioctl(fd, EVIOCGBIT(0, sizeof(evbit)), &evbit) >= 0 &&
          (evbit & ((1UL<<EV_KEY) | (1UL<<EV_ABS)))) {
        prime_abs_range(fd, nfd);
        fds[nfd].fd = fd;
        fds[nfd].events = POLLIN;
        fds[nfd].revents = 0;
        nfd++;
        fprintf(stderr, "[evdev] usando %s\n", path);
      } else {
        close(fd);
      }
    }
    closedir(d);
  }
  if (nfd == 0) { fprintf(stderr, "[evdev] nenhum device de input encontrado\n"); return NULL; }

  struct input_event ev;
  while (atomic_load_explicit(&g_run, memory_order_acquire)) {
    int ready = muos_evdev_wait(fds, (size_t)nfd, 100);
    if (ready < 0) {
      fprintf(stderr, "[evdev] poll falhou: %s\n", strerror(errno));
      break;
    }
    if (ready == 0) continue;
    for (int i = 0; i < nfd; i++) {
      if (!(fds[i].revents & POLLIN)) continue;
      ssize_t n;
      while ((n = read(fds[i].fd, &ev, sizeof(ev))) == (ssize_t)sizeof(ev)) {
        pthread_mutex_lock(&g_pad.lock);
        if (ev.type == EV_KEY) {
          int idx = map_key(ev.code);
          if (idx >= 0) {
            g_pad.btn[idx] = ev.value ? 1.0f : 0.0f;
            g_pad.dirty = 1;
          }
          /* Volume (114/115) e tratado pelo sistema muOS; ignorar em silencio. */
          else if (ev.value && ev.code != KEY_VOLUMEUP && ev.code != KEY_VOLUMEDOWN)
            fprintf(stderr, "[evdev] KEY desconhecido code=0x%x\n", ev.code);
        } else if (ev.type == EV_ABS) {
          int mn = -32768, mx = 32767;
          if (ev.code < ABS_CACHE && abs_known[i][ev.code]) {
            mn = abs_min[i][ev.code]; mx = abs_max[i][ev.code];
          }
          if (apply_abs(&g_pad, ev.code, ev.value, mn, mx)) g_pad.dirty = 1;
        }
        pthread_mutex_unlock(&g_pad.lock);
      }
    }

  }
  for (int i = 0; i < nfd; i++) close(fds[i].fd);
  return NULL;
}

/* ---- API publica para o launcher ---- */
static pthread_t g_thr;
static int g_started = 0;

void muos_gamepad_start(void) {
  if (g_started) return;
  atomic_store_explicit(&g_run, true, memory_order_release);
  int err = pthread_create(&g_thr, NULL, evdev_thread, NULL);
  if (err != 0) {
    atomic_store_explicit(&g_run, false, memory_order_release);
    fprintf(stderr, "[evdev] pthread_create falhou: %s\n", strerror(err));
    return;
  }
  g_started = 1;
}
void muos_gamepad_stop(void) {
  if (!g_started) return;
  atomic_store_explicit(&g_run, false, memory_order_release);
  pthread_join(g_thr, NULL);
  g_started = 0;
}

/* Copia snapshot do estado para buffers do chamador. Retorna 1 se mudou. */
int muos_gamepad_snapshot(float out_btn[NBTN], float out_ax[NAXES]) {
  int was_dirty;
  pthread_mutex_lock(&g_pad.lock);
  was_dirty = g_pad.dirty; g_pad.dirty = 0;
  memcpy(out_btn, g_pad.btn, sizeof(float) * NBTN);
  memcpy(out_ax,  g_pad.ax,  sizeof(float) * NAXES);
  pthread_mutex_unlock(&g_pad.lock);
  return was_dirty;
}
