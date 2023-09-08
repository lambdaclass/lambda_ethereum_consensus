#include "main.h"
#include "utils.h"
#include <stdbool.h>
#include <erl_nif.h>

#define ERL_FUNCTION(FUNCTION_NAME) static ERL_NIF_TERM FUNCTION_NAME(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])

#define ERL_HANDLE_GETTER(NAME, RECV_TYPE, ATTR_TYPE, GETTER)              \
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

#define NIF_ENTRY(FUNCTION_NAME, ARITY, ...)              \
    {                                                     \
        #FUNCTION_NAME, ARITY, FUNCTION_NAME, __VA_ARGS__ \
    }

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
ErlNifResourceType *Listener;
ErlNifResourceType *Iterator;
ErlNifResourceType *Node;
ErlNifResourceType *PubSub;
ErlNifResourceType *Topic;
ErlNifResourceType *Subscription;
ErlNifResourceType *Message;

// Resource type helpers
void handle_cleanup(ErlNifEnv *env, void *obj)
{
    uintptr_t *handle = obj;
    DeleteHandle(*handle);
}

#define OPEN_RESOURCE_TYPE(NAME) ((NAME) = enif_open_resource_type(env, NULL, (#NAME), handle_cleanup, flags, NULL))

static int open_resource_types(ErlNifEnv *env, ErlNifResourceFlags flags)
{
    int failed = false;
    failed |= NULL == OPEN_RESOURCE_TYPE(Option);
    failed |= NULL == OPEN_RESOURCE_TYPE(Host);
    failed |= NULL == OPEN_RESOURCE_TYPE(Peerstore);
    failed |= NULL == OPEN_RESOURCE_TYPE(peer_ID);
    failed |= NULL == OPEN_RESOURCE_TYPE(Multiaddr_arr);
    failed |= NULL == OPEN_RESOURCE_TYPE(Stream);
    failed |= NULL == OPEN_RESOURCE_TYPE(Listener);
    failed |= NULL == OPEN_RESOURCE_TYPE(Iterator);
    failed |= NULL == OPEN_RESOURCE_TYPE(Node);
    failed |= NULL == OPEN_RESOURCE_TYPE(PubSub);
    failed |= NULL == OPEN_RESOURCE_TYPE(Topic);
    failed |= NULL == OPEN_RESOURCE_TYPE(Subscription);
    failed |= NULL == OPEN_RESOURCE_TYPE(Message);
    return failed;
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
    // NOTE: we need to release our reference, so it can be GC'd
    enif_release_resource(obj);
    return make_ok_tuple2(env, term);
}

static bool send_message(ErlNifPid *pid, ErlNifEnv *env, ERL_NIF_TERM message)
{
    // This function consumes the env and message.
    int result = enif_send(NULL, pid, env, message);
    // On error, the env isn't freed by the function.
    // This can only happen if the process from `pid` is dead.
    if (!result)
    {
        enif_free_env(env);
    }
    return result;
}

bool handler_send_message(void *pid_bytes, void *arg1)
{
    uintptr_t stream_handle = (uintptr_t)arg1;
    // Passed as void* to avoid including erl_nif.h in the header.
    ErlNifPid *pid = pid_bytes;
    ErlNifEnv *env = enif_alloc_env();

    ERL_NIF_TERM message = enif_make_tuple2(env, enif_make_atom(env, "req"), get_handle_result(env, Stream, stream_handle));
    return send_message(pid, env, message);
}

bool connect_send_message(void *pid_bytes, void *arg1)
{
    char *error = arg1;
    // Passed as void* to avoid including erl_nif.h in the header.
    ErlNifPid *pid = pid_bytes;
    ErlNifEnv *env = enif_alloc_env();

    ERL_NIF_TERM term = (error == NULL) ? enif_make_atom(env, "ok") : make_error_msg(env, error);
    ERL_NIF_TERM message = enif_make_tuple2(env, enif_make_atom(env, "connect"), term);
    return send_message(pid, env, message);
}

bool subscription_send_message(void *pid_bytes, void *arg1)
{
    uintptr_t gossip_msg = (uintptr_t)arg1;
    // Passed as void* to avoid including erl_nif.h in the header.
    ErlNifPid *pid = pid_bytes;
    ErlNifEnv *env = enif_alloc_env();

    ERL_NIF_TERM term = (gossip_msg == 0) ? enif_make_atom(env, "cancelled")
                                          : get_handle_result(env, Message, gossip_msg);

    ERL_NIF_TERM message = enif_make_tuple2(env, enif_make_atom(env, "sub"), term);
    return send_message(pid, env, message);
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

    // To avoid importing Erlang types in Go. Note that the size of
    // this is sizeof(unsigned long), but it's opaque, hence this.
    const int PID_SIZE = sizeof(ErlNifPid);
    ErlNifPid pid;
    IF_ERROR(!enif_self(env, &pid), "failed to get pid");
    GoSlice go_pid = {(void *)&pid, PID_SIZE, PID_SIZE};

    HostSetStreamHandler(host, proto_id, go_pid, handler_send_message);

    return enif_make_atom(env, "ok");
}

ERL_FUNCTION(host_new_stream)
{
    uintptr_t host = GET_HANDLE(argv[0], Host);
    uintptr_t id = GET_HANDLE(argv[1], peer_ID);

    ErlNifBinary bin;
    IF_ERROR(!enif_inspect_binary(env, argv[2], &bin), "invalid protocol ID");
    GoString proto_id = {(const char *)bin.data, bin.size};

    uintptr_t result = HostNewStream(host, id, proto_id);
    return get_handle_result(env, Stream, result);
}

ERL_FUNCTION(_host_connect)
{
    uintptr_t host = GET_HANDLE(argv[0], Host);
    uintptr_t id = GET_HANDLE(argv[1], peer_ID);

    // To avoid importing Erlang types in Go. Note that the size of
    // this is sizeof(unsigned long), but it's opaque, hence this.
    const int PID_SIZE = sizeof(ErlNifPid);
    ErlNifPid pid;
    IF_ERROR(!enif_self(env, &pid), "failed to get pid");
    GoSlice go_pid = {(void *)&pid, PID_SIZE, PID_SIZE};

    HostConnect(host, id, go_pid, connect_send_message);
    return enif_make_atom(env, "ok");
}

ERL_HANDLE_GETTER(host_peerstore, Host, Peerstore, HostPeerstore)
ERL_HANDLE_GETTER(host_id, Host, peer_ID, HostID)
ERL_HANDLE_GETTER(host_addrs, Host, Multiaddr_arr, HostAddrs)

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

    PeerstoreAddAddrs(ps, id, addrs, ttl);
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

ERL_FUNCTION(stream_close_write)
{
    uintptr_t stream = GET_HANDLE(argv[0], Stream);
    StreamCloseWrite(stream);
    return enif_make_atom(env, "ok");
}

ERL_FUNCTION(stream_protocol)
{
    uintptr_t stream = GET_HANDLE(argv[0], Stream);

    int len = StreamProtocolLen(stream);
    ERL_NIF_TERM bin_term;
    u_char *bin = enif_make_new_binary(env, len, &bin_term);

    GoSlice go_buffer = {bin, len, len};
    StreamProtocol(stream, go_buffer);

    return make_ok_tuple2(env, bin_term);
}

/***************/
/** Discovery **/
/***************/

ERL_FUNCTION(listen_v5)
{
    ErlNifBinary bin;
    IF_ERROR(!enif_inspect_binary(env, argv[0], &bin), "invalid address");
    GoString go_addr = {(const char *)bin.data, bin.size};

    IF_ERROR(!enif_is_list(env, argv[1]), "bootnodes is not a list");
    const int MAX_BOOTNODES = 256;
    GoString bootnodes[MAX_BOOTNODES];
    int i = 0;

    ERL_NIF_TERM head, tail = argv[1];
    while (!enif_is_empty_list(env, tail) && i < MAX_BOOTNODES)
    {
        enif_get_list_cell(env, tail, &head, &tail);
        ErlNifBinary bin;
        IF_ERROR(!enif_inspect_binary(env, head, &bin), "invalid bootnode");
        GoString bootnode = {(const char *)bin.data, bin.size};
        bootnodes[i++] = bootnode;
    }
    GoSlice go_bootnodes = {bootnodes, i, MAX_BOOTNODES};

    uintptr_t handle = ListenV5(go_addr, go_bootnodes);

    return get_handle_result(env, Listener, handle);
}

ERL_FUNCTION(listener_random_nodes)
{
    uintptr_t listener = GET_HANDLE(argv[0], Listener);
    uintptr_t result = ListenerRandomNodes(listener);
    return get_handle_result(env, Iterator, result);
}

ERL_FUNCTION(iterator_next)
{
    uintptr_t listener = GET_HANDLE(argv[0], Iterator);
    bool result = IteratorNext(listener);
    return enif_make_atom(env, result ? "true" : "false");
}

ERL_HANDLE_GETTER(iterator_node, Iterator, Node, IteratorNode)

ERL_FUNCTION(node_tcp)
{
    uintptr_t node = get_handle_from_term(env, Node, argv[0]);
    IF_ERROR(node == 0, "invalid first argument");
    uint64_t tcp_port = NodeTCP(node);
    return (tcp_port == 0) ? enif_make_atom(env, "nil") : enif_make_uint64(env, tcp_port);
}

ERL_HANDLE_GETTER(node_multiaddr, Node, Multiaddr_arr, NodeMultiaddr)
ERL_HANDLE_GETTER(node_id, Node, peer_ID, NodeID)

/************/
/** PubSub **/
/************/

ERL_FUNCTION(new_gossip_sub)
{
    uintptr_t host = GET_HANDLE(argv[0], Host);
    uintptr_t result = NewGossipSub(host);
    return get_handle_result(env, PubSub, result);
}

ERL_FUNCTION(pub_sub_join)
{
    uintptr_t pubsub = GET_HANDLE(argv[0], PubSub);

    ErlNifBinary bin;
    IF_ERROR(!enif_inspect_binary(env, argv[1], &bin), "invalid topic");
    GoString go_topic = {(const char *)bin.data, bin.size};

    uintptr_t result = PubSubJoin(pubsub, go_topic);
    return get_handle_result(env, Topic, result);
}

ERL_FUNCTION(topic_subscribe)
{
    uintptr_t handle = GET_HANDLE(argv[0], Topic);
    // To avoid importing Erlang types in Go. Note that the size of
    // this is sizeof(unsigned long), but it's opaque, hence this.
    const int PID_SIZE = sizeof(ErlNifPid);
    ErlNifPid pid;
    IF_ERROR(!enif_self(env, &pid), "failed to get pid");
    GoSlice go_pid = {(void *)&pid, PID_SIZE, PID_SIZE};

    uintptr_t _res = TopicSubscribe(handle, go_pid, subscription_send_message);
    return get_handle_result(env, Subscription, _res);
}

ERL_FUNCTION(topic_publish)
{
    uintptr_t topic = GET_HANDLE(argv[0], Topic);

    ErlNifBinary bin;
    IF_ERROR(!enif_inspect_binary(env, argv[1], &bin), "invalid message");
    GoSlice go_message = {bin.data, bin.size, bin.size};

    uintptr_t result = TopicPublish(topic, go_message);
    IF_ERROR(result != 0, "failed to publish message");
    return enif_make_atom(env, "ok");
}

ERL_FUNCTION(subscription_cancel)
{
    uintptr_t subscription = GET_HANDLE(argv[0], Subscription);
    SubscriptionCancel(subscription);
    return enif_make_atom(env, "ok");
}

ERL_FUNCTION(message_data)
{
    uintptr_t msg = GET_HANDLE(argv[0], Message);

    int len = MessageDataLen(msg);
    ERL_NIF_TERM bin_term;
    u_char *bin = enif_make_new_binary(env, len, &bin_term);

    GoSlice go_buffer = {bin, len, len};
    MessageData(msg, go_buffer);

    return make_ok_tuple2(env, bin_term);
}

static ErlNifFunc nif_funcs[] = {
    NIF_ENTRY(listen_addr_strings, 1),
    NIF_ENTRY(host_new, 1),
    NIF_ENTRY(host_close, 1),
    NIF_ENTRY(host_set_stream_handler, 2),
    // TODO: check if host_new_stream is truly dirty
    NIF_ENTRY(host_new_stream, 3, ERL_NIF_DIRTY_JOB_IO_BOUND), // blocks negotiating protocol
    NIF_ENTRY(_host_connect, 2),
    NIF_ENTRY(host_peerstore, 1),
    NIF_ENTRY(host_id, 1),
    NIF_ENTRY(host_addrs, 1),
    NIF_ENTRY(peerstore_add_addrs, 4),
    NIF_ENTRY(stream_read, 1, ERL_NIF_DIRTY_JOB_IO_BOUND),  // blocks until reading
    NIF_ENTRY(stream_write, 2, ERL_NIF_DIRTY_JOB_IO_BOUND), // blocks when buffer is full
    NIF_ENTRY(stream_close, 1),
    NIF_ENTRY(stream_close_write, 1),
    NIF_ENTRY(stream_protocol, 1),
    NIF_ENTRY(listen_v5, 2),
    NIF_ENTRY(listener_random_nodes, 1),
    NIF_ENTRY(iterator_next, 1, ERL_NIF_DIRTY_JOB_IO_BOUND), // blocks until gets next node
    NIF_ENTRY(iterator_node, 1),
    NIF_ENTRY(node_tcp, 1),
    NIF_ENTRY(node_multiaddr, 1),
    NIF_ENTRY(node_id, 1),
    NIF_ENTRY(new_gossip_sub, 1),
    NIF_ENTRY(pub_sub_join, 2),
    NIF_ENTRY(topic_subscribe, 1),
    NIF_ENTRY(topic_publish, 2),
    NIF_ENTRY(subscription_cancel, 1),
    NIF_ENTRY(message_data, 1),
};

ERL_NIF_INIT(Elixir.Libp2p, nif_funcs, load, NULL, upgrade, NULL)
