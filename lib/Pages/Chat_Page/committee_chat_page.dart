import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:delego/api/api_client.dart';
import 'package:delego/auth/capabilities.dart';
import 'package:delego/models/break_coordination.dart';
import 'package:delego/widgets/committee_picker.dart';
import 'package:delego/widgets/neon.dart';

class _Committee {
  const _Committee(this.id, this.name);
  final int id;
  final String name;
}

/// What each message type looks like, using the 4 signature Neon swatches:
/// - free (Request break)       -> Blue / Lime (kSwatches[2])
/// - late (Running late)        -> Lime / Orange (kSwatches[0])
/// - accept, agree (Accept)     -> Green / Cyan (kSwatches[3])
/// - reject, decline (Reject)   -> Pink / Yellow (kSwatches[1])
final _kinds = <String, ({String label, NeonSwatch swatch, IconData icon})>{
  'free': (
    label: 'BREAK REQUEST',
    swatch: kSwatches[2],
    icon: Icons.free_breakfast
  ),
  'late': (label: 'RUNNING LATE', swatch: kSwatches[0], icon: Icons.timer),
  'accept': (label: 'ACCEPTED', swatch: kSwatches[3], icon: Icons.check_circle),
  'reject': (label: 'REJECTED', swatch: kSwatches[1], icon: Icons.cancel),
  'agree': (
    label: 'OFFER ACCEPTED',
    swatch: kSwatches[3],
    icon: Icons.thumb_up
  ),
  'decline': (
    label: 'OFFER DECLINED',
    swatch: kSwatches[1],
    icon: Icons.schedule
  ),
};

/// Break coordination: an IHL committee's OC asks for a break at a time, and an admin
/// accepts or offers a later time. Messages are posted over REST and pushed live over a
/// WebSocket; what you can send depends on the permissions the server gave you.
///
/// The admin sees every committee. Everyone else coordinates one committee, picked on
/// first entry and remembered on this phone (prefs `break_committee_id`/
/// `break_committee_name`), changed from the menu.
class CommitteeChatPage extends StatefulWidget {
  const CommitteeChatPage({super.key});

  @override
  State<CommitteeChatPage> createState() => _CommitteeChatPageState();
}

class _CommitteeChatPageState extends State<CommitteeChatPage>
    with WidgetsBindingObserver {
  static const _prefId = 'break_committee_id';
  static const _prefName = 'break_committee_name';
  static const _checkEvery = Duration(seconds: 30);

  late final ApiClient _api;
  late final bool _isAdmin;
  List<_Committee> _committees = [];
  int? _committeeId;
  String? _committeeName;
  List<BreakMsg> _messages = []; // oldest first
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

  Timer? _checkTimer;
  bool _checking = false;
  bool _inFront = true;

  @override
  void initState() {
    super.initState();
    _api = context.read<ApiClient>();
    _isAdmin = context.read<Capabilities>().isAdmin;
    WidgetsBinding.instance.addObserver(this);
    _checkTimer = Timer.periodic(_checkEvery, (_) => _check());
    _start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inFront = state == AppLifecycleState.resumed;
    // The socket may have died while the phone was locked or in the background.
    if (state == AppLifecycleState.resumed) _resync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _checkTimer?.cancel();
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
    final prefs = await SharedPreferences.getInstance();
    _myEmail = prefs.getString('email') ?? '';
    if (!_isAdmin) {
      final id = prefs.getInt(_prefId);
      if (!mounted) return;
      setState(() => _loading = false);
      if (id != null) await _select(id, prefs.getString(_prefName));
      return;
    }
    try {
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
      if (list.isNotEmpty) await _select(list.first.id, list.first.name);
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

  Future<void> _pick(int id, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefId, id);
    await prefs.setString(_prefName, name);
    if (mounted) await _select(id, name);
  }

  /// The saved committee is gone or no longer ours: forget it and ask again.
  Future<void> _forgetCommittee() async {
    _session++;
    _retry?.cancel();
    await _sub?.cancel();
    _channel?.sink.close();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefId);
    await prefs.remove(_prefName);
    if (!mounted) return;
    setState(() {
      _committeeId = null;
      _committeeName = null;
      _messages = [];
      _connected = false;
    });
    _say('That committee is no longer available. Choose again.');
  }

  Future<void> _changeCommittee() async {
    final picked = await Navigator.push<(int, String)>(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(title: const Text('Change committee')),
          body: _picker(
            selectedId: _committeeId,
            onPicked: (id, name) => Navigator.pop(ctx, (id, name)),
          ),
        ),
      ),
    );
    if (picked != null && picked.$1 != _committeeId) {
      await _pick(picked.$1, picked.$2);
    }
  }

  Widget _picker(
          {int? selectedId, required void Function(int, String) onPicked}) =>
      CommitteePicker(
        api: _api,
        endpoint: '/committees',
        question: 'Which committee are you coordinating?',
        icon: Icons.free_breakfast,
        selectedId: selectedId,
        onPicked: onPicked,
      );

  Future<void> _select(int id, String? name) async {
    final session = ++_session;
    _retry?.cancel();
    await _sub?.cancel();
    _channel?.sink.close();
    setState(() {
      _committeeId = id;
      _committeeName = name;
      _messages = [];
      _connected = false;
      _closedForGood = false;
      _retryCount = 0;
    });
    await _loadHistory(id);
    // Only if nothing (a resync, another switch) has opened a newer socket meanwhile.
    if (mounted && id == _committeeId && session == _session) _connect(id);
  }

  /// Fetches the committee's recent messages and merges them into the screen (by id, so
  /// nothing shown twice and nothing already shown dropped). Returns how many were new,
  /// or 0 when the fetch failed.
  Future<int> _loadHistory(int id) async {
    try {
      final res = await _api.get('/committees/$id/messages');
      if (!mounted || id != _committeeId) return 0;
      if (res.statusCode == 404 && !_isAdmin) {
        await _forgetCommittee();
        return 0;
      }
      if (res.statusCode != 200) return 0;
      final fetched = (jsonDecode(res.body) as List)
          .map((m) => BreakMsg(m as Map<String, dynamic>))
          .toList();
      final known = {for (final m in _messages) m.id};
      final fresh = fetched.where((m) => !known.contains(m.id)).toList();
      if (fresh.isNotEmpty) {
        setState(() => _messages = _merged(_messages, fresh));
      }
      return fresh.length;
    } on Forbidden {
      if (mounted && id == _committeeId && !_isAdmin) await _forgetCommittee();
    } on SessionExpired {
      // handled by ApiClient
    } catch (_) {
      // Offline for now: the next check, or the socket, catches up.
    }
    return 0;
  }

  static List<BreakMsg> _merged(List<BreakMsg> a, List<BreakMsg> b) =>
      [...a, ...b]..sort((x, y) => x.id.compareTo(y.id));

  /// Catch up and open a fresh socket: after the app comes back to the front, or when
  /// the regular check finds messages the socket never delivered (a socket can die
  /// without either side noticing, say when the venue Wi-Fi drops or the phone sleeps).
  Future<void> _resync() async {
    final id = _committeeId;
    if (id == null || _closedForGood) return;
    await _loadHistory(id);
    if (!mounted || id != _committeeId) return;
    final session = ++_session;
    _retry?.cancel();
    await _sub?.cancel();
    _channel?.sink.close();
    if (!mounted || id != _committeeId || session != _session) return;
    setState(() => _connected = false);
    _retryCount = 0;
    _connect(id);
  }

  /// Every [_checkEvery] while the screen is open and the app in front: anything the
  /// socket missed shows up anyway, and a socket that missed something is replaced.
  Future<void> _check() async {
    final id = _committeeId;
    if (id == null || !_inFront || _checking) return;
    _checking = true;
    try {
      final missed = await _loadHistory(id);
      if (missed > 0 && _connected && mounted && id == _committeeId) {
        await _resync();
      }
    } finally {
      _checking = false;
    }
  }

  // ------------------------------------------------------------- live feed

  Future<void> _connect(int id) async {
    final session = _session;
    final token = await _api.token;
    if (token == null || !mounted || session != _session) return;

    // https -> wss, http -> ws. The token goes in the first frame, not the URL.
    final base = _api.baseUrl.replaceFirst('http', 'ws');
    final channel =
        WebSocketChannel.connect(Uri.parse('$base/ws/committees/$id/chat'));
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
          _add(BreakMsg(jsonDecode(data as String) as Map<String, dynamic>));
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

    // 4403 no access, 4404 unknown committee: the saved committee is not ours any more.
    if (!_isAdmin && (code == 4403 || code == 4404)) {
      _forgetCommittee();
      return;
    }
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

  void _add(BreakMsg m) {
    if (!mounted || _messages.any((x) => x.id == m.id)) return;
    setState(() => _messages = _merged(_messages, [m]));
  }

  // --------------------------------------------------------------- sending

  Future<void> _send(String type,
      {String? body, Map<String, dynamic>? payload}) async {
    final id = _committeeId;
    if (id == null || _sending) return;
    setState(() => _sending = true);
    try {
      final res = await _api.postJson('/committees/$id/messages', {
        'type': type,
        if (body != null) 'body': body,
        if (payload != null) 'payload': payload,
      });
      if (!mounted) return;
      if (res.statusCode == 201) {
        // The socket echoes it too; _add ignores the duplicate.
        _add(BreakMsg(jsonDecode(res.body) as Map<String, dynamic>));
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

  /// "Request break": the OC picks the clock time the committee can break at. The time
  /// sent is exactly the one picked. The picker opens on PM (see [pickerStart]) and AM
  /// can still be chosen; a time already gone (say AM left on by mistake) is refused and
  /// the picker opens again on that time, saying so, to correct.
  Future<void> _requestBreak() async {
    var initial = TimeOfDay.fromDateTime(pickerStart(DateTime.now()));
    var heading = 'Free for a break at';
    while (true) {
      if (!mounted) return;
      final picked = await showTimePicker(
        context: context,
        initialTime: initial,
        helpText: heading,
        confirmText: 'Request',
        // 12 hour clock with the AM/PM switch, even on a phone set to 24 hour time. The
        // switch is pink so the half that is on stands out.
        builder: (context, child) {
          final theme = Theme.of(context);
          final pink = kSwatches[1];
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
            child: Theme(
              data: theme.copyWith(
                timePickerTheme: theme.timePickerTheme.copyWith(
                  dayPeriodColor: WidgetStateColor.resolveWith((states) =>
                      states.contains(WidgetState.selected)
                          ? Neon.pink
                          : Colors.transparent),
                  dayPeriodTextColor: WidgetStateColor.resolveWith((states) =>
                      states.contains(WidgetState.selected)
                          ? pink.nameColor
                          : theme.colorScheme.onSurface),
                  dayPeriodBorderSide: const BorderSide(color: Neon.pink),
                ),
              ),
              child: child!,
            ),
          );
        },
      );
      if (picked == null || !mounted) return;
      final at = breakTimeFor(picked.hour, picked.minute, DateTime.now());
      if (at == null) {
        final gone = DateTime(2000, 1, 1, picked.hour, picked.minute);
        heading = '${clockTime(gone)} has passed. Pick a later time';
        initial = picked;
        continue;
      }
      await _send('free',
          body: requestText(at), payload: {'at': atPayload(at)});
      return;
    }
  }

  void _sendLate(int minutes) =>
      _send('late', body: 'Running $minutes minutes late');

  /// An admin accepts: now (no time), or come in [delay] minutes.
  void _accept(int? delay) {
    final now = DateTime.now();
    _send('accept',
        body: acceptText(delay, now),
        payload: delay == null
            ? null
            : {'at': atPayload(now.add(Duration(minutes: delay)))});
  }

  /// An admin rejects and offers a time [delay] minutes from now.
  void _reject(int delay) {
    final now = DateTime.now();
    _send('reject',
        body: rejectText(delay, now),
        payload: {'at': atPayload(now.add(Duration(minutes: delay)))});
  }

  void _agree(BreakMsg offer) =>
      _send('agree', body: agreeText(offer.at!), payload: {
        'at': atPayload(offer.at!),
      });

  /// The OC declines the offer with a time of its own.
  void _decline(int delay) {
    final now = DateTime.now();
    _send('decline',
        body: declineText(delay, now),
        payload: {'at': atPayload(now.add(Duration(minutes: delay)))});
  }

  // ------------------------------------------------------------------ build

  String _time(DateTime? t) => t == null ? '' : clockTime(t);

  Widget _bubble(BreakMsg m, ColorScheme scheme) {
    final kind = _kinds[m.type] ??
        (label: m.type.toUpperCase(), swatch: kSwatches[2], icon: Icons.chat);
    final swatch = kind.swatch;
    final fg = swatch.nameColor;
    final mine = m.sender == _myEmail;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: swatch.colors,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(kind.icon, size: 14, color: fg),
                const SizedBox(width: 6),
                Text(kind.label, style: Neon.label(fg, size: 11, spacing: 1.5)),
              ],
            ),
            const SizedBox(height: 6),
            Text(m.body,
                style: TextStyle(
                    color: fg, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              '${mine ? 'You' : m.senderName} · ${_time(m.createdAt)}',
              style: TextStyle(color: fg.withValues(alpha: 0.78), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(
      String label, IconData icon, NeonSwatch swatch, VoidCallback onPressed) {
    final fg = swatch.nameColor;
    return Expanded(
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: swatch.colors.first,
          foregroundColor: fg,
          minimumSize: const Size.fromHeight(50),
        ),
        onPressed: _sending ? null : onPressed,
        icon: Icon(icon, size: 20),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label,
              maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  /// A button with a small triangle beside it that opens a menu of minutes
  /// ([breakDelays]). The main part does [onMain]; a menu choice calls [onMinutes].
  Widget _splitButton({
    required String label,
    required IconData icon,
    required NeonSwatch swatch,
    required VoidCallback onMain,
    required void Function(int minutes) onMinutes,
    required String Function(int minutes) itemLabel,
    required String tooltip,
  }) {
    final color = swatch.colors.first;
    final fg = swatch.nameColor;
    const radius = Radius.circular(20);
    return Expanded(
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: fg,
                minimumSize: const Size.fromHeight(50),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.horizontal(left: radius),
                ),
              ),
              onPressed: _sending ? null : onMain,
              icon: Icon(icon, size: 20),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          PopupMenuButton<int>(
            tooltip: tooltip,
            enabled: !_sending,
            onSelected: onMinutes,
            itemBuilder: (_) => [
              for (final m in breakDelays)
                PopupMenuItem(value: m, child: Text(itemLabel(m))),
            ],
            child: Container(
              height: 50,
              width: 40,
              decoration: BoxDecoration(
                color: _sending ? color.withValues(alpha: 0.4) : color,
                borderRadius: const BorderRadius.horizontal(right: radius),
              ),
              child: Icon(Icons.arrow_drop_down, color: fg, size: 30),
            ),
          ),
        ],
      ),
    );
  }

  /// A button that always asks first: a tap opens the menu of minutes ([breakDelays])
  /// under it, and nothing is sent until one is chosen.
  Widget _menuButton({
    required String label,
    required IconData icon,
    required NeonSwatch swatch,
    required void Function(int minutes) onMinutes,
    required String Function(int minutes) itemLabel,
  }) {
    final fg = swatch.nameColor;
    return Expanded(
      child: Builder(
        builder: (buttonContext) => FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: swatch.colors.first,
            foregroundColor: fg,
            minimumSize: const Size.fromHeight(50),
          ),
          onPressed: _sending
              ? null
              : () async {
                  final box = buttonContext.findRenderObject() as RenderBox;
                  final overlay = Overlay.of(buttonContext)
                      .context
                      .findRenderObject() as RenderBox;
                  final topLeft = box.localToGlobal(Offset(0, box.size.height),
                      ancestor: overlay);
                  final minutes = await showMenu<int>(
                    context: buttonContext,
                    position: RelativeRect.fromLTRB(
                      topLeft.dx,
                      topLeft.dy,
                      overlay.size.width - topLeft.dx - box.size.width,
                      0,
                    ),
                    items: [
                      for (final m in breakDelays)
                        PopupMenuItem(value: m, child: Text(itemLabel(m))),
                    ],
                  );
                  if (minutes != null && mounted) onMinutes(minutes);
                },
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(label,
                    maxLines: 1,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Icon(Icons.arrow_drop_down, size: 26),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "Running late" (5 min by default) with a menu for 5, 10 or 15 minutes.
  /// Uses the Lime / Orange signature swatch.
  Widget _lateSplitButton() => _splitButton(
        label: 'Running late',
        icon: Icons.timer,
        swatch: kSwatches[0],
        onMain: () => _sendLate(5),
        onMinutes: _sendLate,
        itemLabel: (m) => 'Late by $m minutes',
        tooltip: 'Choose how late',
      );

  Widget _offerRow(BreakMsg offer, ColorScheme scheme) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Admin: come at ${clockTime(offer.at!)}',
            style:
                TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Row(children: [
            _action('Accept offer', Icons.thumb_up, kSwatches[3],
                () => _agree(offer)),
            const SizedBox(width: 10),
            _splitButton(
              label: 'Decline',
              icon: Icons.schedule,
              swatch: kSwatches[1],
              onMain: () => _decline(5),
              onMinutes: _decline,
              itemLabel: (m) => 'Free in $m minutes',
              tooltip: 'When you will be free',
            ),
          ]),
        ],
      );

  Widget _connection(ColorScheme scheme) => Tooltip(
        message: _connected
            ? 'Live'
            : (_closedForGood ? 'Disconnected' : 'Reconnecting…'),
        child: Icon(
          _connected ? Icons.cloud_done : Icons.cloud_off,
          color: _connected ? const Color(0xFF1B9E5A) : scheme.error,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final caps = context.watch<Capabilities>();
    final canRequest = caps.can(Perm.chatSendRequest);
    final canRespond = caps.can(Perm.chatRespond);

    if (!_isAdmin && !_loading && _committeeId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Break Coordination')),
        body: _picker(onPicked: _pick),
      );
    }

    final offer = canRequest ? pendingOffer(_messages, DateTime.now()) : null;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Text(_isAdmin
            ? 'BREAK COORDINATION'
            : (_committeeName ?? 'Break Coordination')),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: _isAdmin ? 16 : 0),
            child: _connection(scheme),
          ),
          if (!_isAdmin)
            PopupMenuButton<String>(
              tooltip: 'Menu',
              onSelected: (v) {
                if (v == 'change') _changeCommittee();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'change', child: Text('Change committee')),
              ],
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
                        FilledButton(
                            onPressed: _start, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    if (_isAdmin)
                      SizedBox(
                        height: 52,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          itemCount: _committees.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final c = _committees[i];
                            return ChoiceChip(
                              label: Text(c.name),
                              selected: c.id == _committeeId,
                              onSelected: (_) => _select(c.id, c.name),
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
                                  style: TextStyle(
                                      color: scheme.onSurface
                                          .withValues(alpha: 0.6))),
                            )
                          : ListView.builder(
                              reverse:
                                  true, // newest at the bottom, stays pinned there
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                              itemCount: _messages.length,
                              itemBuilder: (_, i) => _bubble(
                                  _messages[_messages.length - 1 - i], scheme),
                            ),
                    ),
                    if (canRequest || canRespond)
                      SafeArea(
                        top: false,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHigh,
                            border: Border(
                                top: BorderSide(color: scheme.outlineVariant)),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (offer != null) ...[
                                _offerRow(offer, scheme),
                                const SizedBox(height: 10),
                              ],
                              if (canRequest)
                                Row(children: [
                                  _action('Request break', Icons.free_breakfast,
                                      kSwatches[2], _requestBreak),
                                  const SizedBox(width: 10),
                                  _lateSplitButton(),
                                ]),
                              if (canRequest && canRespond)
                                const SizedBox(height: 10),
                              if (canRespond)
                                Row(children: [
                                  _splitButton(
                                    label: 'Accept',
                                    icon: Icons.check,
                                    swatch: kSwatches[3],
                                    onMain: () => _accept(null),
                                    onMinutes: _accept,
                                    itemLabel: (m) => 'Come in $m minutes',
                                    tooltip: 'Accept for later',
                                  ),
                                  const SizedBox(width: 10),
                                  // Reject always asks when they can come instead.
                                  _menuButton(
                                    label: 'Reject',
                                    icon: Icons.close,
                                    swatch: kSwatches[1],
                                    onMinutes: _reject,
                                    itemLabel: (m) => 'Come in $m minutes',
                                  ),
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
