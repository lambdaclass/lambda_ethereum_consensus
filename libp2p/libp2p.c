#include "main.h"
#include "utils.h"
#include <erl_nif.h>

#define ERL_FUNCTION(FUNCTION_NAME) static ERL_NIF_TERM FUNCTION_NAME(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])

#define ERL_FUNCTION_GETTER(NAME, GETTER)                       \
    ERL_FUNCTION(NAME)                                          \
    {                                                           \
        uintptr_t _handle = get_handle_from_term(env, argv[0]); \
        uintptr_t _res = GETTER(_handle);                       \
        return get_handle_result(env, _res);                    \
    }

#define NIF_ENTRY(FUNCTION_NAME, ARITY)      \
    {                                        \
        #FUNCTION_NAME, ARITY, FUNCTION_NAME \
    }

const uint64_t PID_LENGTH = 1024;
const uint64_t BUFFER_SIZE = 4096;

/***********/
/* Helpers */
/***********/

static uintptr_t get_handle_from_term(ErlNifEnv *env, ERL_NIF_TERM term)
{
    uintptr_t handle;
    enif_get_uint64(env, term, &handle);
    return handle;
}

static ERL_NIF_TERM make_error_msg(ErlNifEnv *env, const char *msg)
{
    return enif_make_tuple2(env, enif_make_atom(env, "error"), enif_make_string(env, msg, ERL_NIF_UTF8));
}

static ERL_NIF_TERM make_ok_tuple2(ErlNifEnv *env, ERL_NIF_TERM term)
{
    return enif_make_tuple2(env, enif_make_atom(env, "ok"), term);
}

static ERL_NIF_TERM get_handle_result(ErlNifEnv *env, uintptr_t handle)
{
    if (handle == 0)
    {
        return make_error_msg(env, "invalid handle returned");
    }
    return make_ok_tuple2(env, enif_make_uint64(env, handle));
}

/*********/
/* Utils */
/*********/

ERL_FUNCTION(listen_addr_strings)
{
    char addr_string[PID_LENGTH];
    uint64_t len = enif_get_string(env, argv[0], addr_string, PID_LENGTH, ERL_NIF_UTF8);
    if (len <= 0)
    {
        return make_error_msg(env, "invalid string");
    }

    GoString go_listenAddr = {addr_string, len - 1};

    uintptr_t handle = ListenAddrStrings(go_listenAddr);

    return get_handle_result(env, handle);
}

/****************/
/* Host methods */
/****************/

ERL_FUNCTION(host_new)
{
    // TODO: add option passing
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
    uint64_t len = enif_get_string(env, argv[1], proto_id, PID_LENGTH, ERL_NIF_UTF8);

    if (len <= 0)
    {
        return make_error_msg(env, "invalid string");
    }
    GoString go_protoId = {proto_id, len - 1};

    // TODO: This is a memory leak.
    ErlNifPid *pid = malloc(sizeof(ErlNifPid));

    if (!enif_self(env, pid))
    {
        return make_error_msg(env, "failed to get pid");
    }

    SetStreamHandler(handle, go_protoId, (void *)pid);

    return enif_make_atom(env, "ok");
}

ERL_FUNCTION(host_new_stream)
{
    uintptr_t handle = get_handle_from_term(env, argv[0]);
    uintptr_t id = get_handle_from_term(env, argv[1]);

    char proto_id[PID_LENGTH];
    uint64_t len = enif_get_string(env, argv[2], proto_id, PID_LENGTH, ERL_NIF_UTF8);

    if (len <= 0)
    {
        return make_error_msg(env, "invalid string");
    }
    GoString go_protoId = {proto_id, len - 1};

    int result = NewStream(handle, id, go_protoId);
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

/******************/
/* Stream methods */
/******************/

ERL_FUNCTION(stream_read)
{
    uintptr_t stream = get_handle_from_term(env, argv[0]);

    char buffer[BUFFER_SIZE];
    GoSlice go_buffer = {buffer, BUFFER_SIZE, BUFFER_SIZE};

    uint64_t read = StreamRead(stream, go_buffer);

    if (read == -1)
    {
        return make_error_msg(env, "failed to read");
    }
    return make_ok_tuple2(env, enif_make_string_len(env, buffer, read, ERL_NIF_UTF8));
}

ERL_FUNCTION(stream_write)
{
    uintptr_t stream = get_handle_from_term(env, argv[0]);

    char data[BUFFER_SIZE];
    uint64_t len = enif_get_string(env, argv[1], data, BUFFER_SIZE, ERL_NIF_UTF8);

    if (len <= 0)
    {
        return make_error_msg(env, "invalid string");
    }
    GoSlice go_data = {data, len - 1, len - 1};

    uint64_t written = StreamWrite(stream, go_data);

    if (written == -1)
    {
        return make_error_msg(env, "failed to write");
    }
    return enif_make_atom(env, "ok");
}

ERL_FUNCTION(stream_close)
{
    StreamClose(get_handle_from_term(env, argv[0]));
    return enif_make_atom(env, "nil");
}

static ErlNifFunc nif_funcs[] = {
    NIF_ENTRY(listen_addr_strings, 1),
    NIF_ENTRY(host_new, 0),
    NIF_ENTRY(host_close, 1),
    NIF_ENTRY(host_set_stream_handler, 2),
    NIF_ENTRY(host_new_stream, 3),
    NIF_ENTRY(host_peerstore, 1),
    NIF_ENTRY(host_id, 1),
    NIF_ENTRY(host_addrs, 1),
    NIF_ENTRY(peerstore_add_addrs, 4),
    NIF_ENTRY(stream_read, 1),
    NIF_ENTRY(stream_write, 2),
    NIF_ENTRY(stream_close, 1),
};

ERL_NIF_INIT(Elixir.Libp2p, nif_funcs, NULL, NULL, NULL, NULL)
