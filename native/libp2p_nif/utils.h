#pragma once

#include <stdint.h> // for uintptr_t
#include <stdbool.h>

typedef bool (*send_message1_t)(void *pid_bytes, void *arg1);

bool run_callback1(send_message1_t send_message, void *pid_bytes, void *arg1);
