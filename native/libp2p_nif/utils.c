#include "utils.h"

void run_callback(send_message_t send_message, erl_pid_t pid, uintptr_t stream)
{
    send_message(pid, stream);
}
