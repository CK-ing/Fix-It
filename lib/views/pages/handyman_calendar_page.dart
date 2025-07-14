import 'dart:async';
import 'package:fixit_app_a186687/models/bookings_services.dart';
import 'package:fixit_app_a186687/views/pages/bookings_detail_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

// A local view model to combine booking data with homeowner details for the UI
class ScheduleEvent {
  final Booking booking;
  final String homeownerName;

  ScheduleEvent({required this.booking, required this.homeownerName});
}

class HandymanCalendarPage extends StatefulWidget {
  const HandymanCalendarPage({super.key});

  @override
  State<HandymanCalendarPage> createState() => _HandymanCalendarPageState();
}

class _HandymanCalendarPageState extends State<HandymanCalendarPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  User? _currentUser;

  // State for calendar and events
  Map<DateTime, List<ScheduleEvent>> _events = {};
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  late final ValueNotifier<List<ScheduleEvent>> _selectedEvents;

  // Loading and error state
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    _selectedDay = _focusedDay;
    _selectedEvents = ValueNotifier(_getEventsForDay(_selectedDay!));
    _loadHandymanSchedule();
  }

  @override
  void dispose() {
    _selectedEvents.dispose();
    super.dispose();
  }

  /// Fetches all relevant bookings for the handyman and processes them into a map of events.
  Future<void> _loadHandymanSchedule() async {
    if (_currentUser == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final handymanId = _currentUser!.uid;
    final bookingsQuery = _dbRef.child('bookings').orderByChild('handymanId').equalTo(handymanId);

    try {
      final snapshot = await bookingsQuery.get();

      if (!mounted) return;
      if (!snapshot.exists) {
        setState(() => _isLoading = false);
        return;
      }

      Map<String, Booking> bookingsMap = {};
      Set<String> homeownerIds = {};
      final bookingsData = Map<String, dynamic>.from(snapshot.value as Map);

      bookingsData.forEach((key, value) {
        final booking = Booking.fromSnapshot(snapshot.child(key));
        // Only include active, confirmed jobs in the schedule
        if (['Accepted', 'En Route', 'Ongoing'].contains(booking.status)) {
          bookingsMap[booking.bookingId] = booking;
          homeownerIds.add(booking.homeownerId);
        }
      });

      // Fetch homeowner details for all relevant bookings
      final homeownerDetailsMap = await _fetchHomeownerDetails(homeownerIds);

      if (!mounted) return;

      // Create the final event map
      Map<DateTime, List<ScheduleEvent>> events = {};
      bookingsMap.values.forEach((booking) {
        final homeownerName = homeownerDetailsMap[booking.homeownerId]?['name'] ?? 'Customer';
        final event = ScheduleEvent(booking: booking, homeownerName: homeownerName);
        final date = DateTime.utc(booking.scheduledDateTime.year, booking.scheduledDateTime.month, booking.scheduledDateTime.day);
        
        if (events[date] == null) {
          events[date] = [];
        }
        events[date]!.add(event);
      });
      
      // Sort events within each day by time
      events.forEach((date, eventList) {
        eventList.sort((a, b) => a.booking.scheduledDateTime.compareTo(b.booking.scheduledDateTime));
      });

      setState(() {
        _events = events;
        _isLoading = false;
        _selectedEvents.value = _getEventsForDay(_selectedDay!);
      });
    } catch (e) {
      print("Error loading handyman schedule: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = "Failed to load schedule.";
        });
      }
    }
  }

  /// Fetches user details for a given set of homeowner IDs.
  Future<Map<String, Map<String, dynamic>>> _fetchHomeownerDetails(Set<String> ids) async {
    if (ids.isEmpty) return {};
    Map<String, Map<String, dynamic>> detailsMap = {};
    final futures = ids.map((id) => _dbRef.child('users/$id').get());
    final results = await Future.wait(futures);
    for (var snapshot in results) {
      if (snapshot.exists) {
        detailsMap[snapshot.key!] = Map<String, dynamic>.from(snapshot.value as Map);
      }
    }
    return detailsMap;
  }

  List<ScheduleEvent> _getEventsForDay(DateTime day) {
    // Important: Use DateTime.utc to match the keys in the _events map
    return _events[DateTime.utc(day.year, day.month, day.day)] ?? [];
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
        _selectedEvents.value = _getEventsForDay(selectedDay);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Schedule'),
        elevation: 1,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    _buildCalendar(),
                    const Divider(height: 1),
                    _buildEventList(),
                  ],
                ),
    );
  }

  Widget _buildCalendar() {
    return TableCalendar<ScheduleEvent>(
      firstDay: DateTime.utc(DateTime.now().year - 1, 1, 1),
      lastDay: DateTime.utc(DateTime.now().year + 1, 12, 31),
      focusedDay: _focusedDay,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      onDaySelected: _onDaySelected,
      eventLoader: _getEventsForDay,
      calendarStyle: CalendarStyle(
        todayDecoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withOpacity(0.3),
          shape: BoxShape.circle,
        ),
        selectedDecoration: BoxDecoration(
          color: Colors.red.withOpacity(0.5),
          shape: BoxShape.circle,
        ),
        markerDecoration: BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
      ),
      headerStyle: const HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
      ),
    );
  }

  Widget _buildEventList() {
    return Expanded(
      child: ValueListenableBuilder<List<ScheduleEvent>>(
        valueListenable: _selectedEvents,
        builder: (context, value, _) {
          if (value.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_busy, size: 60, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text("No jobs scheduled for this day."),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: value.length,
            itemBuilder: (context, index) {
              final event = value[index];
              final booking = event.booking;
              final Color statusColor = _getStatusColor(booking.status);
              final String formattedTime = DateFormat.jm().format(booking.scheduledDateTime);
              final String endTime = DateFormat.jm().format(booking.scheduledDateTime.add(Duration(hours: booking.quantity)));

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: statusColor, width: 2),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                  title: Text(
                    booking.serviceName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text("Customer: ${event.homeownerName}"),
                      const SizedBox(height: 4),
                      Text("Time: $formattedTime - $endTime"),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BookingDetailPage(
                          bookingId: booking.bookingId,
                          userRole: 'Handyman',
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case "Accepted":
        return Colors.blue.shade700;
      case "En Route":
        return Colors.cyan.shade600;
      case "Ongoing":
        return Colors.lightBlue.shade600;
      default:
        return Colors.grey;
    }
  }
}
