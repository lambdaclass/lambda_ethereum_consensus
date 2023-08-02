#include "main.h"
#include "utils.h"
#include <erl_nif.h>

#define ERL_FUNCTION(FUNCTION_NAME) static ERL_NIF_TERM FUNCTION_NAME(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])

#define ERL_FUNCTION_GETTER(NAME, RECV_TYPE, ATTR_TYPE, GETTER)            \
    ERL_FUNCTION(NAME)                                                     \
    {                                                                      \
        uintptr_t _handle = get_handle_from_term(env, RECV_TYPE, argv[0]); \
        IF_ERROR(_handle == 0, "invalid first argument");                  \
        uintptr_t _res = GETTER(_handle);                                  \
        return get_handle_result(env, ATTR_TYPE, _res);                    \
    }

#define IF_ERROR(COND, MSG)                \
    if (COND)                              \
    {                                      \
        return make_error_msg(env, (MSG)); \
    }

#define GET_HANDLE(TERM, TYPE)                                         \
    ({                                                                 \
        uintptr_t _handle = get_handle_from_term(env, (TYPE), (TERM)); \
        IF_ERROR(_handle == 0, "invalid " #TYPE);                      \
        _handle;                                                       \
    })

#define NIF_ENTRY(FUNCTION_NAME, ARITY)      \
    {                                        \
        #FUNCTION_NAME, ARITY, FUNCTION_NAME \
    }

const uint64_t PID_LENGTH = 1024;
const uint64_t BUFFER_SIZE = 4096;

/*************/
/* NIF Setup */
/*************/

ErlNifResourceType *Option;
ErlNifResourceType *Host;
ErlNifResourceType *Peerstore;
ErlNifResourceType *peer_ID;
ErlNifResourceType *Multiaddr_arr;
ErlNifResourceType *Stream;

// Resource type helpers
void handle_cleanup(ErlNifEnv *env, void *arg)
{
    uintptr_t handle = (uintptr_t)arg;
    DeleteHandle(handle);
}

static int open_resource_types(ErlNifEnv *env, ErlNifResourceFlags flags)
{
    int ok = 0;
    ok &= NULL == (Option = enif_open_resource_type(env, NULL, "Option_type", handle_cleanup, flags, NULL));
    ok &= NULL == (Host = enif_open_resource_type(env, NULL, "Host_type", handle_cleanup, flags, NULL));
    ok &= NULL == (Peerstore = enif_open_resource_type(env, NULL, "Peerstore_type", handle_cleanup, flags, NULL));
    ok &= NULL == (peer_ID = enif_open_resource_type(env, NULL, "peer_ID_type", handle_cleanup, flags, NULL));
    ok &= NULL == (Multiaddr_arr = enif_open_resource_type(env, NULL, "Multiaddr_arr_type", handle_cleanup, flags, NULL));
    ok &= NULL == (Stream = enif_open_resource_type(env, NULL, "Stream_type", handle_cleanup, flags, NULL));
    return ok ? 1 : 0;
}

static int load(ErlNifEnv *env, void **priv_data, ERL_NIF_TERM load_info)
{
    return open_resource_types(env, ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER);
}

static int upgrade(ErlNifEnv *env, void **priv_data, void **old_priv_data,
                   ERL_NIF_TERM load_info)
{
    return open_resource_types(env, ERL_NIF_RT_TAKEOVER);
}

/***********/
/* Helpers */
/***********/

static uintptr_t get_handle_from_term(ErlNifEnv *env, ErlNifResourceType *type, ERL_NIF_TERM term)
{
    uintptr_t *obj;
    int result = enif_get_resource(env, term, type, (void **)&obj);
    return (!result || obj == NULL) ? 0 : *obj;
}

static ERL_NIF_TERM _make_error_msg(ErlNifEnv *env, uint len, const char *msg)
{
    ERL_NIF_TERM msg_term;
    u_char *buffer = enif_make_new_binary(env, len, &msg_term);
    memcpy(buffer, msg, len);
    return enif_make_tuple2(env, enif_make_atom(env, "error"), msg_term);
}

static inline ERL_NIF_TERM make_error_msg(ErlNifEnv *env, const char *msg)
{
    return _make_error_msg(env, strlen(msg), msg);
}

static ERL_NIF_TERM make_ok_tuple2(ErlNifEnv *env, ERL_NIF_TERM term)
{
    return enif_make_tuple2(env, enif_make_atom(env, "ok"), term);
}

static ERL_NIF_TERM get_handle_result(ErlNifEnv *env, ErlNifResourceType *type, uintptr_t handle)
{
    IF_ERROR(handle == 0, "invalid handle returned");
    uintptr_t *obj = enif_alloc_resource(type, sizeof(uintptr_t));
    IF_ERROR(obj == NULL, "couldn't create resource");
    *obj = handle;
    ERL_NIF_TERM term = enif_make_resource(env, obj);
    return make_ok_tuple2(env, term);
}

/*********/
/* Utils */
/*********/

ERL_FUNCTION(listen_addr_strings)
{
    ErlNifBinary bin;
    IF_ERROR(!enif_inspect_binary(env, argv[0], &bin), "invalid address");
    GoString listen_addr = {(const char *)bin.data, bin.size};

    uintptr_t handle = ListenAddrStrings(listen_addr);

    return get_handle_result(env, Option, handle);
}

/****************/
/* Host methods */
/****************/

ERL_FUNCTION(host_new)
{
    IF_ERROR(!enif_is_list(env, argv[0]), "options is not a list");
    const int MAX_OPTIONS = 256;
    uintptr_t options[MAX_OPTIONS];
    int i = 0;
    ERL_NIF_TERM head, tail = argv[0];
    while (!enif_is_empty_list(env, tail) && i < MAX_OPTIONS)
    {
        enif_get_list_cell(env, tail, &head, &tail);
        uintptr_t handle = GET_HANDLE(head, Option);
        options[i++] = handle;
    }
    GoSlice go_options = {options, i, MAX_OPTIONS};
    uintptr_t result = HostNew(go_options);
    return get_handle_result(env, Host, result);
}

ERL_FUNCTION(host_close)
{
    uintptr_t host = GET_HANDLE(argv[0], Host);
    HostClose(host);
    return enif_make_atom(env, "ok");
}

ERL_FUNCTION(host_set_stream_handler)
{
    uintptr_t host = GET_HANDLE(argv[0], Host);

    ErlNifBinary bin;
    IF_ERROR(!enif_inspect_binary(env, argv[1], &bin), "invalid protocol ID");
    GoString proto_id = {(const char *)bin.data, bin.size};

    // TODO: This is a memory leak.
    ErlNifPid *pid = malloc(sizeof(ErlNifPid));

    IF_ERROR(!enif_self(env, pid), "failed to get pid");

    SetStreamHandler(host, proto_id, (void *)pid);

    return enif_make_atom(env, "ok");
}

ERL_FUNCTION(host_new_stream)
{
    uintptr_t host = GET_HANDLE(argv[0], Host);
    uintptr_t id = GET_HANDLE(argv[1], peer_ID);

    ErlNifBinary bin;
    IF_ERROR(!enif_inspect_binary(env, argv[2], &bin), "invalid protocol ID");
    GoString proto_id = {(const char *)bin.data, bin.size};

    uintptr_t result = NewStream(host, id, proto_id);
    return get_handle_result(env, Stream, result);
}

ERL_FUNCTION_GETTER(host_peerstore, Host, Peerstore, HostPeerstore)
ERL_FUNCTION_GETTER(host_id, Host, peer_ID, HostID)
ERL_FUNCTION_GETTER(host_addrs, Host, Multiaddr_arr, HostAddrs)

/*********************/
/* Peerstore methods */
/*********************/

ERL_FUNCTION(peerstore_add_addrs)
{
    uintptr_t ps = GET_HANDLE(argv[0], Peerstore);
    uintptr_t id = GET_HANDLE(argv[1], peer_ID);
    uintptr_t addrs = GET_HANDLE(argv[2], Multiaddr_arr);
    u_long ttl;
    IF_ERROR(!enif_get_uint64(env, argv[3], &ttl), "invalid TTL");

    AddAddrs(ps, id, addrs, ttl);
    return enif_make_atom(env, "ok");
}

/******************/
/* Stream methods */
/******************/

ERL_FUNCTION(stream_read)
{
    uintptr_t stream = GET_HANDLE(argv[0], Stream);

    char buffer[BUFFER_SIZE];
    GoSlice go_buffer = {buffer, BUFFER_SIZE, BUFFER_SIZE};

    uint64_t read = StreamRead(stream, go_buffer);
    IF_ERROR(read == -1, "failed to read");

    ERL_NIF_TERM bin_term;
    u_char *bin_data = enif_make_new_binary(env, read, &bin_term);
    memcpy(bin_data, buffer, read);

    return make_ok_tuple2(env, bin_term);
}

ERL_FUNCTION(stream_write)
{
    uintptr_t stream = GET_HANDLE(argv[0], Stream);

    ErlNifBinary bin;
    IF_ERROR(!enif_inspect_binary(env, argv[1], &bin), "invalid data");
    GoSlice go_data = {bin.data, bin.size, bin.size};

    uint64_t written = StreamWrite(stream, go_data);
    IF_ERROR(written == -1, "failed to write");

    return enif_make_atom(env, "ok");
}

ERL_FUNCTION(stream_close)
{
    uintptr_t stream = GET_HANDLE(argv[0], Stream);
    StreamClose(stream);
    return enif_make_atom(env, "ok");
}

static ErlNifFunc nif_funcs[] = {
    NIF_ENTRY(listen_addr_strings, 1),
    NIF_ENTRY(host_new, 1),
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

ERL_NIF_INIT(Elixir.Libp2p, nif_funcs, load, NULL, upgrade, NULL)
