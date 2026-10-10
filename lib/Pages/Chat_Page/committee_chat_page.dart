import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:delego/api/api_client.dart';
import 'package:delego/auth/capabilities.dart';
import 'package:delego/widgets/neon.dart';

class _Committee {
  const _Committee(this.id, this.name);
  final int id;
  final String name;
}

class _Msg {
  _Msg(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        sender = '${j['sender']}',
        senderName = '${j['sender_name']}',
        type = '${j['type']}',
        body = '${j['body']}',
        at = DateTime.tryParse('${j['created_at']}')?.toLocal();

  final int id;
  final String sender;
  final String senderName;
  final String type;
  final String body;
  final DateTime? at;
}

/// What each message type looks like. The server owns the type names.
const _kinds = <String, ({String label, Color color, IconData icon})>{
  'free': (label: 'BREAK REQUEST', color: Color(0xFF2F55FF), icon: Icons.free_breakfast),
  'late': (label: 'RUNNING LATE', color: Color(0xFFFF7A1A), icon: Icons.timer),
  'accept': (label: 'ACCEPTED', color: Color(0xFF1B9E5A), icon: Icons.check_circle),
  'reject': (label: 'REJECTED', color: Color(0xFFD7263D), icon: Icons.cancel),
};

/// Break coordination: committees ask for a break, hospitality answers. Messages are
/// posted over REST and pushed live over a WebSocket; what you can send depends on the
/// permissions the server gave you.
class CommitteeChatPage extends StatefulWidget {
  const CommitteeChatPage({super.key});

  @override
  State<CommitteeChatPage> createState() => _CommitteeChatPageState();
}

class _CommitteeChatPageState extends State<CommitteeChatPage> {
  late final ApiClient _api;
  List<_Committee> _committees = [];
  int? _committeeId;
  List<_Msg> _messages = []; // oldest first
  String _myEmail = '';

  String? _error; // loading problem, shown with a retry
  bool _loading = true;
  bool _sending = false;
  bool _connected = false;
  bool _closedForGood = false; // the server refused this socket; do not retry

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _retry;
  int _retryCount = 0;
  int _session = 0; // bumped on every (re)connect or committee switch

  @override
  void initState() {
    super.initState();
    _api = context.read<ApiClient>();
    _start();
  }

  @override
  void dispose() {
    _session++;
    _retry?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  // --------------------------------------------------------------- loading

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _myEmail = (await SharedPreferences.getInstance()).getString('email') ?? '';
      final res = await _api.get('/committees');
      if (res.statusCode != 200) throw 'Server returned ${res.statusCode}';
      final list = (jsonDecode(res.body) as List)
          .map((c) => _Committee((c['id'] as num).toInt(), '${c['name']}'))
          .toList();
      if (!mounted) return;
      setState(() {
        _committees = list;
        _loading = false;
      });
      if (list.isNotEmpty) await _select(list.first.id);
    } on Forbidden {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'You do not have access to break coordination.';
        });
      }
    } on SessionExpired {
      // ApiClient already sent the user back to login.
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load committees. Check your connection.';
        });
      }
    }
  }

  Future<void> _select(int id) async {
    _session++;
    _retry?.cancel();
    await _sub?.cancel();
    _channel?.sink.close();
    setState(() {
      _committeeId = id;
      _messages = [];
      _connected = false;
      _closedForGood = false;
      _retryCount = 0;
    });
    await _loadHistory(id);
    _connect(id);
  }

  Future<void> _loadHistory(int id) async {
    try {
      final res = await _api.get('/committees/$id/messages');
      if (res.statusCode != 200 || !mounted || id != _committeeId) return;
      setState(() {
        _messages = (jsonDecode(res.body) as List)
            .map((m) => _Msg(m as Map<String, dynamic>))
            .toList();
      });
    } on SessionExpired {
      // handled by ApiClient
    } catch (_) {
      // The socket still delivers new messages; history can be retried by reselecting.
    }
  }

  // ------------------------------------------------------------- live feed

  Future<void> _connect(int id) async {
    final session = _session;
    final token = await _api.token;
    if (token == null || !mounted || session != _session) return;

    // https -> wss, http -> ws. The token goes in the first frame, not the URL.
    final base = _api.baseUrl.replaceFirst('http', 'ws');
    final channel = WebSocketChannel.connect(Uri.parse('$base/ws/committees/$id/chat'));
    _channel = channel;
    channel.sink.add(jsonEncode({'token': token}));

    _sub = channel.stream.listen(
      (data) {
        if (session != _session) return;
        if (!_connected && mounted) {
          setState(() => _connected = true);
          _retryCount = 0;
        }
        try {
          _add(_Msg(jsonDecode(data as String) as Map<String, dynamic>));
        } catch (_) {}
      },
      onDone: () => _onClosed(session, id, channel.closeCode),
      onError: (_) => _onClosed(session, id, null),
      cancelOnError: true,
    );

    // The server sends nothing until a message arrives, so treat a socket that is
    // still open shortly after connecting as connected.
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && session == _session && channel.closeCode == null) {
        setState(() => _connected = true);
      }
    });
  }

  void _onClosed(int session, int id, int? code) {
    if (!mounted || session != _session) return;
    setState(() => _connected = false);

    // 4401 bad token, 4403 no access, 4404 unknown committee: retrying will not help.
    if (code == 4401 || code == 4403 || code == 4404) {
      setState(() => _closedForGood = true);
      return;
    }
    final wait = Duration(seconds: (2 << _retryCount.clamp(0, 4)));
    _retryCount++;
    _retry = Timer(wait, () async {
      if (!mounted || session != _session) return;
      await _loadHistory(id); // catch up on anything missed while offline
      if (mounted && session == _session) _connect(id);
    });
  }

  void _add(_Msg m) {
    if (!mounted || _messages.any((x) => x.id == m.id)) return;
    setState(() => _messages = [..._messages, m]);
  }

  // --------------------------------------------------------------- sending

  Future<void> _send(String type, {String? body}) async {
    final id = _committeeId;
    if (id == null || _sending) return;
    setState(() => _sending = true);
    try {
      final res = await _api.postJson('/committees/$id/messages', {
        'type': type,
        if (body != null) 'body': body,
      });
      if (!mounted) return;
      if (res.statusCode == 201) {
        // The socket echoes it too; _add ignores the duplicate.
        _add(_Msg(jsonDecode(res.body) as Map<String, dynamic>));
      } else {
        _say('Could not send (${res.statusCode}).');
      }
    } on Forbidden {
      if (mounted) _say('You are not allowed to send that.');
    } on SessionExpired {
      // handled by ApiClient
    } catch (_) {
      if (mounted) _say('Could not reach the server.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _say(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // ------------------------------------------------------------------ build

  String _time(DateTime? t) {
    if (t == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  Widget _bubble(_Msg m, ColorScheme scheme) {
    final kind = _kinds[m.type] ?? (label: m.type.toUpperCase(), color: scheme.primary, icon: Icons.chat);
    final mine = m.sender == _myEmail;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: kind.color,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(kind.icon, size: 14, color: Colors.white),
                const SizedBox(width: 6),
                Text(kind.label, style: Neon.label(Colors.white, size: 11, spacing: 1.5)),
              ],
            ),
            const SizedBox(height: 6),
            Text(m.body,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Text(
              '${mine ? 'You' : m.senderName} · ${_time(m.at)}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(String type, String label, IconData icon, Color color) {
    return Expanded(
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
        ),
        onPressed: _sending ? null : () => _send(type),
        icon: Icon(icon, size: 20),
        label: Text(label),
      ),
    );
  }

  void _sendLate(int minutes) =>
      _send('late', body: 'Running $minutes minutes late');

  /// "Running late" (5 min by default) with a small triangle beside it that opens
  /// a menu to choose 5, 10 or 15 minutes.
  Widget _lateSplitButton() {
    const color = Color(0xFFE5700F);
    const radius = Radius.circular(20);
    return Expanded(
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.horizontal(left: radius),
                ),
              ),
              onPressed: _sending ? null : () => _sendLate(5),
              icon: const Icon(Icons.timer, size: 20),
              label: const Text('Running late'),
            ),
          ),
          const SizedBox(width: 2),
          PopupMenuButton<int>(
            tooltip: 'Choose how late',
            enabled: !_sending,
            onSelected: _sendLate,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 5, child: Text('Late by 5 minutes')),
              PopupMenuItem(value: 10, child: Text('Late by 10 minutes')),
              PopupMenuItem(value: 15, child: Text('Late by 15 minutes')),
            ],
            child: Container(
              height: 50,
              width: 40,
              decoration: BoxDecoration(
                color: _sending ? color.withValues(alpha: 0.4) : color,
                borderRadius: const BorderRadius.horizontal(right: radius),
              ),
              child: const Icon(Icons.arrow_drop_down, color: Colors.white, size: 30),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final caps = context.watch<Capabilities>();
    final canRequest = caps.can(Perm.chatSendRequest);
    final canRespond = caps.can(Perm.chatRespond);

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Text('BREAK COORDINATION'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Tooltip(
              message: _connected ? 'Live' : (_closedForGood ? 'Disconnected' : 'Reconnecting…'),
              child: Icon(
                _connected ? Icons.cloud_done : Icons.cloud_off,
                color: _connected ? const Color(0xFF1B9E5A) : scheme.error,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _start, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    SizedBox(
                      height: 52,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _committees.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final c = _committees[i];
                          return ChoiceChip(
                            label: Text(c.name),
                            selected: c.id == _committeeId,
                            onSelected: (_) => _select(c.id),
                          );
                        },
                      ),
                    ),
                    if (_closedForGood)
                      Container(
                        width: double.infinity,
                        color: scheme.error,
                        padding: const EdgeInsets.all(8),
                        child: const Text(
                          'Live updates were refused by the server.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    Expanded(
                      child: _messages.isEmpty
                          ? Center(
                              child: Text('No messages yet.',
                                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6))),
                            )
                          : ListView.builder(
                              reverse: true, // newest at the bottom, stays pinned there
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                              itemCount: _messages.length,
                              itemBuilder: (_, i) =>
                                  _bubble(_messages[_messages.length - 1 - i], scheme),
                            ),
                    ),
                    if (canRequest || canRespond)
                      SafeArea(
                        top: false,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHigh,
                            border: Border(top: BorderSide(color: scheme.outlineVariant)),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (canRequest)
                                Row(children: [
                                  _action('free', 'Request break', Icons.free_breakfast, const Color(0xFF2F55FF)),
                                  const SizedBox(width: 10),
                                  _lateSplitButton(),
                                ]),
                              if (canRequest && canRespond) const SizedBox(height: 10),
                              if (canRespond)
                                Row(children: [
                                  _action('accept', 'Accept', Icons.check, const Color(0xFF1B9E5A)),
                                  const SizedBox(width: 10),
                                  _action('reject', 'Reject (full)', Icons.close, const Color(0xFFD7263D)),
                                ]),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
