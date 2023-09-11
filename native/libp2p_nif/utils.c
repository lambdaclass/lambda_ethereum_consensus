#include "utils.h"

bool run_callback1(send_message1_t send_message, void *pid_bytes, void *arg1)
{
    return send_message(pid_bytes, arg1);
}
