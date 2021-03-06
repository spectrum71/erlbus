-module(chat_cowboy_ws_handler).

-export([init/3]).
-export([websocket_init/3]).
-export([websocket_handle/3]).
-export([websocket_info/3]).
-export([websocket_terminate/3]).

-define(CHATROOM_NAME, ?MODULE).
-define(TIMEOUT, 5 * 60 * 1000). % Innactivity Timeout
-define(DEFAULT_USERNAME, "-").

-record(state, {host, handler, username}).

%% API

init(_, _Req, _Opts) ->
  {upgrade, protocol, cowboy_websocket}.

websocket_init(_Type, Req, _Opts) ->
  % Create the handler from our custom callback
  Handler = ebus_proc:spawn_handler(fun chat_erlbus_handler:handle_msg/2, [self()]),
  ebus:sub(Handler, ?CHATROOM_NAME),
  {ok, Req, #state{host = get_host(Req), handler = Handler, username = ?DEFAULT_USERNAME}, ?TIMEOUT}.

websocket_handle({text, Msg}, Req, State) ->
  if
    State#state.username == ?DEFAULT_USERNAME ->
      {ok, Req, #state{host = State#state.host, handler = State#state.handler, username = Msg}};
    true ->
      ebus:pub(?CHATROOM_NAME, {State#state.username, State#state.host, Msg}),
      {ok, Req, State}
  end;
websocket_handle(_Data, Req, State) ->
  {ok, Req, State}.

websocket_info({message_published, {Sender, Host, Msg}}, Req, State) ->
  {reply, {text, jiffy:encode({[{sender, Sender}, {host, Host}, {msg, Msg}]})}, Req, State};
websocket_info(_Info, Req, State) ->
  {ok, Req, State}.

websocket_terminate(_Reason, _Req, State) ->
  % Unsubscribe the handler
  ebus:unsub(State#state.handler, ?CHATROOM_NAME),
  ok.

%% Private methods

get_host(Req) ->
  {{Host, Port}, _} = cowboy_req:peer(Req),
  Name = list_to_binary(string:join([inet_parse:ntoa(Host),
    ":", io_lib:format("~p", [Port])], "")),
  Name.
  