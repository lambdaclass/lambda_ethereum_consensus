#include "utils.h"
#include <erl_nif.h>

void send_message(void *_pid, uintptr_t stream_handle)
{
    // Passed as void* to avoid including erl_nif.h in the header.
    ErlNifPid *pid = (ErlNifPid *)_pid;
    ErlNifEnv *env = enif_alloc_env();

    ERL_NIF_TERM message = enif_make_tuple2(env, enif_make_atom(env, "ok"), enif_make_uint64(env, stream_handle));

    int result = enif_send(NULL, pid, env, message);
    // On error, the env isn't freed by the function.
    if (!result)
    {
        enif_free_env(env);
    }
}
