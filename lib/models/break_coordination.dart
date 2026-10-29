/// Break coordination between a committee room's OC and an admin.
///
/// The room asks for a break at a clock time (`free`) or says it is running late
/// (`late`). An admin accepts (`accept`, now or in a few minutes) or rejects with a
/// time to come instead (`reject`). When an admin names a time, the room agrees to it
/// (`agree`) or declines with a time of its own (`decline`). A time travels in the
/// message payload as `at` (ISO, UTC).
library;

/// The room's side of the conversation.
const roomActions = {'free', 'late', 'agree', 'decline'};

/// Admin's side.
const adminActions = {'accept', 'reject'};

/// The delays offered on the split buttons.
const breakDelays = [5, 10, 15];

/// An offer older than this is no longer waiting for an answer.
const offerLifetime = Duration(hours: 1);

class BreakMsg {
  BreakMsg(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        sender = '${j['sender']}',
        senderName = '${j['sender_name']}',
        type = '${j['type']}',
        body = '${j['body']}',
        at = _time((j['payload'] as Map?)?['at']),
        createdAt = _time(j['created_at']);

  final int id;
  final String sender;
  final String senderName;
  final String type;
  final String body;

  /// The time this message names (break at, come at), local; null when it names none.
  final DateTime? at;
  final DateTime? createdAt;

  static DateTime? _time(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;
}

/// `at` as the app sends it.
String atPayload(DateTime at) => at.toUtc().toIso8601String();

/// 12 hour clock time, like the picker: "1:30 PM", "12:05 PM", "9:00 AM".
String clockTime(DateTime t) {
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minute = t.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// Today at exactly the picked clock time, or null when that minute has already gone by.
/// The picked time is never swapped for another one: a time in the past is refused, so
/// the OC picks again instead of the app quietly sending something they did not choose.
/// The current minute itself still counts ("free now").
DateTime? breakTimeFor(int hour, int minute, DateTime now) {
  final at = DateTime(now.year, now.month, now.day, hour, minute);
  final thisMinute =
      DateTime(now.year, now.month, now.day, now.hour, now.minute);
  return at.isBefore(thisMinute) ? null : at;
}

/// Where the break time picker opens: always on PM, since breaks (lunch, high tea) are
/// in the afternoon. From noon on that is [now] rounded up to the next 5 minutes; before
/// noon it is 12:00 PM, so a quick tap never sends a time late at night.
DateTime pickerStart(DateTime now) {
  final next = nextFiveMinutes(now);
  if (next.hour >= 12) return next;
  return DateTime(now.year, now.month, now.day, 12);
}

/// [now] rounded up to the next 5 minutes.
DateTime nextFiveMinutes(DateTime now) {
  final add = 5 - now.minute % 5;
  final t = now.add(Duration(minutes: add));
  return DateTime(t.year, t.month, t.day, t.hour, t.minute);
}

String requestText(DateTime at) => 'Free for a break at ${clockTime(at)}';

String acceptText(int? delay, DateTime now) => delay == null
    ? 'Accepted - come down now'
    : 'Accepted - come in $delay min (${clockTime(now.add(Duration(minutes: delay)))})';

String rejectText(int delay, DateTime now) =>
    'Rejected - come in $delay min (${clockTime(now.add(Duration(minutes: delay)))})';

String agreeText(DateTime at) =>
    "Offer accepted - we'll come at ${clockTime(at)}";

String declineText(int delay, DateTime now) =>
    "Declined - we'll be free in $delay min (${clockTime(now.add(Duration(minutes: delay)))})";

/// An admin's latest offer of a time, if the room has not answered it yet: the newest
/// break message, when it is an accept or reject that names a time no more than
/// [offerLifetime] ago. Anything the room sends after it (including a new request)
/// answers it. Messages are oldest first.
BreakMsg? pendingOffer(List<BreakMsg> messages, DateTime now) {
  for (final m in messages.reversed) {
    if (roomActions.contains(m.type)) return null;
    if (adminActions.contains(m.type)) {
      final at = m.at;
      if (at == null || now.difference(at) > offerLifetime) return null;
      return m;
    }
  }
  return null;
}
