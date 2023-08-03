#pragma once

#include <stdint.h> // for uintptr_t

typedef void *erl_pid_t;

void send_message(erl_pid_t pid, uintptr_t stream);
