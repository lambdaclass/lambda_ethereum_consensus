#include "main.h"
#include "utils.h"
#include <erl_nif.h>

#define ERL_FUNCTION(FUNCTION_NAME) static ERL_NIF_TERM FUNCTION_NAME(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])

#define ERL_FUNCTION_GETTER(NAME, GETTER)                    \
    ERL_FUNCTION(NAME)                                       \
    {                                                        \
        uintptr_t host = get_handle_from_term(env, argv[0]); \
        uintptr_t host_id = GETTER(host);                    \
        return get_handle_result(env, host_id);              \
    }

#define NIF_ENTRY(FUNCTION_NAME, ARITY)      \
    {                                        \
        #FUNCTION_NAME, ARITY, FUNCTION_NAME \
    }

const uint64_t PID_LENGTH = 1024;

/***********/
/* Helpers */
/***********/

static uintptr_t get_handle_from_term(ErlNifEnv *env, ERL_NIF_TERM term)
{
    uintptr_t handle;
    enif_get_uint64(env, term, &handle);
    return handle;
}

static ERL_NIF_TERM get_handle_result(ErlNifEnv *env, uintptr_t handle)
{
    if (handle == 0)
    {
        return enif_make_atom(env, "error");
    }
    return enif_make_tuple2(env, enif_make_atom(env, "ok"), enif_make_uint64(env, handle));
}

/*********/
/* Tests */
/*********/

ERL_FUNCTION(hello)
{
    return enif_make_atom(env, "world");
}

ERL_FUNCTION(my_function)
{
    int a, b;
    enif_get_int(env, argv[0], &a);
    enif_get_int(env, argv[1], &b);

    int result = MyFunction(a, b);

    return enif_make_int(env, result);
}

ERL_FUNCTION(test_send_message)
{
    ErlNifPid *pid = malloc(sizeof(ErlNifPid));

    if (!enif_self(env, pid))
    {
        return enif_make_atom(env, "error");
    }

    TestSendMessage(pid);

    return enif_make_atom(env, "ok");
}

/*********/
/* Utils */
/*********/

ERL_FUNCTION(listen_addr_strings)
{
    uint32_t len;
    enif_get_string_length(env, argv[0], &len, ERL_NIF_UTF8);
    char addr_string[len];
    enif_get_string(env, argv[0], addr_string, len, ERL_NIF_UTF8);

    GoString go_listenAddr = {addr_string, len};

    ListenAddrStrings(go_listenAddr);

    return enif_make_atom(env, "nil");
}

/****************/
/* Host methods */
/****************/

ERL_FUNCTION(host_new)
{
    uintptr_t result = New(0, NULL);
    return get_handle_result(env, result);
}

ERL_FUNCTION(host_close)
{
    uintptr_t handle = get_handle_from_term(env, argv[0]);

    HostClose(handle);

    return enif_make_atom(env, "nil");
}

ERL_FUNCTION(host_set_stream_handler)
{
    uintptr_t handle = get_handle_from_term(env, argv[0]);

    char proto_id[PID_LENGTH];
    enif_get_string(env, argv[1], proto_id, PID_LENGTH, ERL_NIF_UTF8);

    // TODO: This is a memory leak.
    ErlNifPid *pid = malloc(sizeof(ErlNifPid));

    if (!enif_self(env, pid))
    {
        return enif_make_atom(env, "error");
    }

    SetStreamHandler(handle, proto_id, (void *)pid);

    return enif_make_atom(env, "ok");
}

ERL_FUNCTION(host_new_stream)
{
    uintptr_t handle = get_handle_from_term(env, argv[0]);
    uintptr_t id = get_handle_from_term(env, argv[1]);

    char proto_id[PID_LENGTH];
    enif_get_string(env, argv[1], proto_id, PID_LENGTH, ERL_NIF_UTF8);

    int result = NewStream(handle, id, proto_id);
    return get_handle_result(env, result);
}

ERL_FUNCTION_GETTER(host_peerstore, Peerstore)
ERL_FUNCTION_GETTER(host_id, ID)
ERL_FUNCTION_GETTER(host_addrs, Addrs)

/*********************/
/* Peerstore methods */
/*********************/

ERL_FUNCTION(peerstore_add_addrs)
{
    uintptr_t ps = get_handle_from_term(env, argv[0]);
    uintptr_t id = get_handle_from_term(env, argv[1]);
    uintptr_t addrs = get_handle_from_term(env, argv[2]);
    u_long ttl;
    enif_get_uint64(env, argv[3], &ttl);

    AddAddrs(ps, id, addrs, ttl);
    return enif_make_atom(env, "nil");
}

/* Functions left to port
- StreamRead
- StreamWrite
- StreamClose
*/

static ErlNifFunc nif_funcs[] = {
    NIF_ENTRY(hello, 0),
    NIF_ENTRY(my_function, 2),
    NIF_ENTRY(test_send_message, 0),
    NIF_ENTRY(listen_addr_strings, 1),
    NIF_ENTRY(host_new, 0),
    NIF_ENTRY(host_close, 1),
    NIF_ENTRY(host_set_stream_handler, 2),
    NIF_ENTRY(host_new_stream, 3),
    NIF_ENTRY(host_peerstore, 1),
    NIF_ENTRY(host_id, 1),
    NIF_ENTRY(host_addrs, 1),
    NIF_ENTRY(peerstore_add_addrs, 4),
};

ERL_NIF_INIT(Elixir.Libp2p, nif_funcs, NULL, NULL, NULL, NULL)
