#pragma once

#include <stdint.h> // for uintptr_t

void send_message(void *pid, uintptr_t stream);
