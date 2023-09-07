#pragma once

#include <stdint.h> // for uintptr_t

// send_message function signature.
typedef void (*send_message_t)(void *pid_bytes, uintptr_t stream);

void run_callback(send_message_t send_message, void *pid_bytes, uintptr_t stream);
