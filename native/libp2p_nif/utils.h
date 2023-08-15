#pragma once

#include <stdint.h> // for uintptr_t

// For better readability. Pointer is casted to opaque,
// to avoid having to include erl_nif.h in Go.
typedef void *erl_pid_t;

// send_message function signature.
typedef void (*send_message_t)(erl_pid_t pid, uintptr_t stream);

void run_callback(send_message_t send_message, erl_pid_t pid, uintptr_t stream);
