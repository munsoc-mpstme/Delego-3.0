import 'package:flutter/material.dart';
import 'package:delego/constants/backend.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async'; // For Future/async operations

// --- BACKEND AND CLIENT SETUP ---

// 1. Real HTTP Client
final http.Client httpClient = http.Client();

// 2. Real SharedPreferences Instance Getter
Future<SharedPreferences> getSharedPreferencesInstance() => SharedPreferences.getInstance();

// Mock implementations removed

// --- DATA MODEL (remains the same) ---

class Room {
  final String id;
  final String committeeName;
  final String roomCode;
  final String floor;

  Room({
    required this.id,
    required this.committeeName,
    required this.roomCode,
    required this.floor,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'] as String,
      committeeName: json['committee_name'] as String,
      roomCode: json['room_code'] as String,
      floor: json['floor'] as String,
    );
  }
}

class RoomPage extends StatefulWidget {
  const RoomPage({super.key});
  @override
  _RoomPageState createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  List<Room> _rooms = [];
  bool _isLoading = true;
  String? _error;

  static const String _cacheKey = 'allotedRoomsData';
  static const String _timestampKey = 'allotedRoomsTimestamp';
  static const int _cacheDurationMs = 120 * 60 * 1000;

  @override
  void initState() {
    super.initState();
    _fetchRooms();
  }

  Future<void> _fetchRooms() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final prefs = await SharedPreferences.getInstance();
    final cachedData = prefs.getString(_cacheKey);
    final cacheTimestamp = prefs.getString(_timestampKey);
    final now = DateTime.now().millisecondsSinceEpoch;

    bool cacheValid = false;
    if (cachedData != null && cacheTimestamp != null) {
      final lastFetched = int.tryParse(cacheTimestamp) ?? 0;
      if (now - lastFetched < _cacheDurationMs) {
        _rooms = _parseRooms(cachedData);
        cacheValid = true;
        setState(() { _isLoading = false; });
        return;
      }
    }
    try {
      final url = Uri.parse('${Backend.baseUrl}/rooms');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final responseBody = response.body;
        _rooms = _parseRooms(responseBody);
        await prefs.setString(_cacheKey, responseBody);
        await prefs.setString(_timestampKey, now.toString());
      } else {
        final responseData = json.decode(response.body);
        final errorMessage = responseData['message'] ?? 'Server error: Status Code ${response.statusCode}';
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (_rooms.isEmpty) {
        _error = 'Data not available: ${e.toString().contains('Exception:') ? e.toString().replaceFirst('Exception: ', '') : 'Please check your connection.'}';
      } else {
        _error = 'Could not update data. Displaying cached information. Error: ${e.toString().contains('Exception:') ? e.toString().replaceFirst('Exception: ', '') : 'Network failed.'}';
      }
    }
    setState(() {
      _isLoading = false;
    });
  }

  List<Room> _parseRooms(String jsonString) {
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((json) => Room.fromJson(json)).toList();
    } catch (_) { return []; }
  }

  Widget _buildRoomCard(Room room, ColorScheme scheme, TextTheme textTheme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      padding: const EdgeInsets.all(25),
      width: double.infinity,
      decoration: ShapeDecoration(
        color: scheme.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.92),
        ),
        shadows: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                room.committeeName,
                style: textTheme.titleLarge?.copyWith(
                  color: scheme.onPrimary,
                  fontSize: 20.23, fontWeight: FontWeight.w600, fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                room.roomCode,
                style: textTheme.titleLarge?.copyWith(
                  color: scheme.onPrimary,
                  fontSize: 20.23, fontWeight: FontWeight.w600, fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                room.floor,
                style: textTheme.titleMedium?.copyWith(
                  color: scheme.onPrimary.withValues(alpha: 0.85),
                  fontSize: 18.65, fontWeight: FontWeight.w600, fontFamily: 'Poppins',
                ),
              ),
            ],
          ),
          SizedBox(
            height: 70,
            width: 70,
            child: Image.asset('assets/icons/loc.png'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget content;
    if (_isLoading && _rooms.isEmpty) {
      content = Center(child: CircularProgressIndicator(color: scheme.primary));
    } else if (_rooms.isEmpty && _error != null) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 60, color: scheme.error),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(color: scheme.error),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchRooms,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Fetch'),
              ),
            ],
          ),
        ),
      );
    } else {
      content = ListView.builder(
        itemCount: _rooms.length,
        itemBuilder: (context, index) {
          return _buildRoomCard(_rooms[index], scheme, textTheme);
        },
      );
    }

    // Show snackBar for stale cache after widget build
    if (_error != null && !_isLoading && _rooms.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_error!),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      });
    }

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        iconTheme: IconThemeData(color: scheme.onPrimary),
        centerTitle: true,
        title: Text(
          'Allotted Rooms',
          style: textTheme.titleLarge?.copyWith(
            color: scheme.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 0.0,
      ),
      body: content,
    );
  }
}





