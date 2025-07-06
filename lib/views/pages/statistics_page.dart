import 'dart:async';
import 'package:fixit_app_a186687/models/bookings_services.dart';
import 'package:fixit_app_a186687/models/handyman_services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/reviews.dart';

// Enum for the date filter options
enum DateRangeFilter { last7Days, last30Days, last6Months, allTime }

// A helper class to hold processed statistical data
class HandymanStats {
  // Current period stats
  final double totalRevenue;
  final int completedJobs;
  final double averageRating;
  final int ratingCount;
  final double recommendationRate;
  final int recommendedCount;
  
  // Trend data (comparison with previous period)
  final double? revenueTrend;
  final int? jobsTrend;
  final double? ratingTrend;
  final double? recommendationTrend;

  // Data for charts
  final List<FlSpot> revenueSpots;
  final Map<String, int> bookingStatusCounts;
  final Map<String, double> topCategoriesRevenue;
  final Map<int, RatingSource> ratingSources;

  HandymanStats({
    this.totalRevenue = 0.0,
    this.completedJobs = 0,
    this.averageRating = 0.0,
    required this.ratingCount,
    this.recommendationRate = 0.0,
    required this.recommendedCount,
    this.revenueTrend,
    this.jobsTrend,
    this.ratingTrend,
    this.recommendationTrend,
    this.revenueSpots = const [],
    this.bookingStatusCounts = const {},
    this.topCategoriesRevenue = const {},
    this.ratingSources = const {},
  });
}

// Helper class for stacked bar chart data
class RatingSource {
  final int standard;
  final int custom;
  RatingSource({required this.standard, required this.custom});
}


class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  User? _currentUser;

  // State
  bool _isLoading = true;
  String? _error;
  DateRangeFilter _selectedFilter = DateRangeFilter.last30Days;

  // Raw data holders
  List<Map<String, dynamic>> _allPayments = [];
  List<Booking> _allBookings = [];
  List<Review> _allReviews = [];
  List<HandymanService> _allServices = [];

  // Processed stats holder
  HandymanStats _currentStats = HandymanStats(
  ratingCount: 0,
  recommendedCount: 0,
);

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    _loadAndProcessData();
  }

  Future<void> _loadAndProcessData() async {
    if (_currentUser == null) {
      setState(() { _isLoading = false; _error = "User not found."; });
      return;
    }
    setState(() { _isLoading = true; _error = null; });

    try {
      final handymanId = _currentUser!.uid;
      final results = await Future.wait([
        _dbRef.child('payments').orderByChild('handymanId').equalTo(handymanId).get(),
        _dbRef.child('bookings').orderByChild('handymanId').equalTo(handymanId).get(),
        _dbRef.child('reviews').orderByChild('handymanId').equalTo(handymanId).get(),
        _dbRef.child('services').orderByChild('handymanId').equalTo(handymanId).get(),
      ]);

      if (!mounted) return;
      
      final paymentsSnapshot = results[0];
      _allPayments.clear();
      if (paymentsSnapshot.exists) {
        (paymentsSnapshot.value as Map<dynamic, dynamic>).forEach((key, value) {
           _allPayments.add(Map<String, dynamic>.from(value as Map));
        });
      }

      final bookingsSnapshot = results[1];
      _allBookings.clear();
      if (bookingsSnapshot.exists) {
        for (var child in bookingsSnapshot.children) {
          _allBookings.add(Booking.fromSnapshot(child));
        }
      }

      final reviewsSnapshot = results[2];
      _allReviews.clear();
      if (reviewsSnapshot.exists) {
        for (var child in reviewsSnapshot.children) {
          _allReviews.add(Review.fromSnapshot(child));
        }
      }

      final servicesSnapshot = results[3];
      _allServices.clear();
      if (servicesSnapshot.exists) {
        for (var child in servicesSnapshot.children) {
           _allServices.add(HandymanService.fromMap(Map<String, dynamic>.from(child.value as Map), child.key!));
        }
      }
      
      _filterAndCalculateStats();

    } catch (e) {
      print("Error loading statistics data: $e");
      setState(() => _error = "Failed to load data.");
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }
  
  void _filterAndCalculateStats() {
    final now = DateTime.now();
    DateTime currentStartDate;
    DateTime? previousStartDate;
    DateTime? previousEndDate;

    switch (_selectedFilter) {
      case DateRangeFilter.last7Days:
        currentStartDate = now.subtract(const Duration(days: 7));
        previousStartDate = now.subtract(const Duration(days: 14));
        previousEndDate = currentStartDate;
        break;
      case DateRangeFilter.last30Days:
        currentStartDate = now.subtract(const Duration(days: 30));
        previousStartDate = now.subtract(const Duration(days: 60));
        previousEndDate = currentStartDate;
        break;
      case DateRangeFilter.last6Months:
        currentStartDate = DateTime(now.year, now.month - 6, now.day);
        previousStartDate = DateTime(now.year, now.month - 12, now.day);
        previousEndDate = currentStartDate;
        break;
      case DateRangeFilter.allTime:
        currentStartDate = DateTime(2000);
        previousStartDate = null; // No previous period for "All Time"
        previousEndDate = null;
        break;
    }

    // --- Calculate stats for the CURRENT period ---
    final currentPeriodStats = _calculateStatsForPeriod(currentStartDate, now);
    
    // --- Calculate stats for the PREVIOUS period (for trends) ---
    HandymanStats? previousPeriodStats;
    if (previousStartDate != null && previousEndDate != null) {
      previousPeriodStats = _calculateStatsForPeriod(previousStartDate, previousEndDate);
    }
    
    // --- Calculate Trends ---
    double? revenueTrend;
    if (previousPeriodStats?.totalRevenue != null && previousPeriodStats!.totalRevenue > 0) {
      revenueTrend = (currentPeriodStats.totalRevenue - previousPeriodStats.totalRevenue) / previousPeriodStats.totalRevenue;
    }

    setState(() {
      _currentStats = HandymanStats(
        totalRevenue: currentPeriodStats.totalRevenue,
        completedJobs: currentPeriodStats.completedJobs,
        averageRating: currentPeriodStats.averageRating,
        ratingCount: currentPeriodStats.ratingCount,
        recommendationRate: currentPeriodStats.recommendationRate,
        recommendedCount: currentPeriodStats.recommendedCount,
        revenueTrend: revenueTrend,
        jobsTrend: previousPeriodStats != null ? currentPeriodStats.completedJobs - previousPeriodStats.completedJobs : null,
        ratingTrend: previousPeriodStats != null ? currentPeriodStats.averageRating - previousPeriodStats.averageRating : null,
        recommendationTrend: previousPeriodStats != null ? currentPeriodStats.recommendationRate - previousPeriodStats.recommendationRate : null,
        revenueSpots: currentPeriodStats.revenueSpots,
        bookingStatusCounts: currentPeriodStats.bookingStatusCounts,
        topCategoriesRevenue: currentPeriodStats.topCategoriesRevenue,
        ratingSources: currentPeriodStats.ratingSources,
      );
    });
  }

  // --- NEW: Helper function to calculate stats for a given period ---
  HandymanStats _calculateStatsForPeriod(DateTime startDate, DateTime endDate) {
  final filteredPayments = _allPayments.where(
    (p) => DateTime.fromMillisecondsSinceEpoch(p['createdAt']).isAfter(startDate) &&
           DateTime.fromMillisecondsSinceEpoch(p['createdAt']).isBefore(endDate)
  ).toList();

  final filteredBookings = _allBookings.where(
    (b) => b.bookingDateTime.isAfter(startDate) &&
           b.bookingDateTime.isBefore(endDate)
  ).toList();

  final filteredReviews = _allReviews.where(
    (r) => r.createdAt.isAfter(startDate) &&
           r.createdAt.isBefore(endDate)
  ).toList();

  final totalRevenue = filteredPayments.map((p) => (p['amount'] as num) / 100.0).fold(0.0, (a, b) => a + b);
  final completedJobs = filteredBookings.where((b) => b.status == 'Completed').length;
  final int ratingCount = filteredReviews.length;
    final int recommendedCount = filteredReviews.where((r) => r.recommended).length;

    final double averageRating = ratingCount > 0 ? filteredReviews.map((r) => r.rating).reduce((a, b) => a + b) / ratingCount : 0.0;
    final double recommendationRate = ratingCount > 0 ? (recommendedCount / ratingCount) * 100 : 0.0;

  // 🧑‍💻 NEW: Build revenue intervals
  final now = DateTime.now();
  Duration intervalDuration;

  switch (_selectedFilter) {
    case DateRangeFilter.last7Days:
      intervalDuration = const Duration(days: 2);
      break;
    case DateRangeFilter.last30Days:
      intervalDuration = const Duration(days: 7);
      break;
    case DateRangeFilter.last6Months:
      intervalDuration = const Duration(days: 45);
      break;
    case DateRangeFilter.allTime:
      intervalDuration = const Duration(days: 90);
      break;
  }

  // Build a map with default 0 revenue for each interval
  final intervalDates = <DateTime>[];
  var current = DateTime(startDate.year, startDate.month, startDate.day);
  while (current.isBefore(endDate)) {
    intervalDates.add(current);
    current = current.add(intervalDuration);
  }

  final revenueByInterval = <double, double>{};
  for (var date in intervalDates) {
    revenueByInterval[date.millisecondsSinceEpoch.toDouble()] = 0.0;
  }

  // Allocate each payment to its interval
  for (var payment in filteredPayments) {
    final paymentDate = DateTime.fromMillisecondsSinceEpoch(payment['createdAt']);
    final intervalStart = intervalDates.lastWhere(
      (d) => !paymentDate.isBefore(d),
      orElse: () => intervalDates.first,
    );
    final key = intervalStart.millisecondsSinceEpoch.toDouble();
    revenueByInterval[key] = (revenueByInterval[key] ?? 0.0) + (payment['amount'] as num) / 100.0;
  }

  final revenueSpots = revenueByInterval.entries
      .map((e) => FlSpot(e.key, e.value))
      .toList()
    ..sort((a, b) => a.x.compareTo(b.x));

  // 🔷 Booking statuses
  Map<String, int> bookingStatusCounts = {
    'Completed': completedJobs,
    'Cancelled': filteredBookings.where((b) => b.status == 'Cancelled').length,
    'Declined': filteredBookings.where((b) => b.status == 'Declined').length
  };
  bookingStatusCounts.removeWhere((key, value) => value == 0);

  // 🔷 Top categories
  Map<String, double> topCategoriesRevenue = {};
  final serviceIdToCategoryMap = {for (var s in _allServices) s.id: s.category};
  for (var booking in filteredBookings.where((b) => b.status == 'Completed')) {
    final category = (booking.serviceId != null && booking.serviceId!.isNotEmpty
            ? serviceIdToCategoryMap[booking.serviceId]
            : 'Custom Job') ?? 'Other';
    topCategoriesRevenue.update(
      category,
      (value) => value + (booking.total / 100.0),
      ifAbsent: () => (booking.total / 100.0),
    );
  }

  // 🔷 Ratings breakdown
  Map<int, RatingSource> ratingSources = {
    1: RatingSource(standard: 0, custom: 0),
    2: RatingSource(standard: 0, custom: 0),
    3: RatingSource(standard: 0, custom: 0),
    4: RatingSource(standard: 0, custom: 0),
    5: RatingSource(standard: 0, custom: 0),
  };
  final bookingIdToTypeMap = {
    for (var b in _allBookings) b.bookingId: b.customRequestId != null ? 'custom' : 'standard'
  };
  for (var review in filteredReviews) {
    final bookingType = bookingIdToTypeMap[review.bookingId];
    if (bookingType == 'standard') {
      ratingSources.update(
        review.rating,
        (val) => RatingSource(standard: val.standard + 1, custom: val.custom),
      );
    } else if (bookingType == 'custom') {
      ratingSources.update(
        review.rating,
        (val) => RatingSource(standard: val.standard, custom: val.custom + 1),
      );
    }
  }

  return HandymanStats(
    totalRevenue: totalRevenue,
    completedJobs: completedJobs,
    averageRating: averageRating,
    ratingCount: ratingCount, 
    recommendationRate: recommendationRate,
    recommendedCount: recommendedCount,
    revenueSpots: revenueSpots,
    bookingStatusCounts: bookingStatusCounts,
    topCategoriesRevenue: topCategoriesRevenue,
    ratingSources: ratingSources,
  );
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Statistics')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _buildDashboard(),
    );
  }

  Widget _buildDashboard() {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _buildFilterBar(),
        const SizedBox(height: 16),
        _buildKpiSection(),
        const SizedBox(height: 24),
        _buildChartCard("Revenue Over Time", _buildRevenueChart()),
        const SizedBox(height: 16),
        _buildChartCard("Booking Status Breakdown", _buildStatusPieChart()),
         const SizedBox(height: 16),
        _buildChartCard("Top Categories by Revenue", _buildTopCategoriesChart()),
        const SizedBox(height: 16),
        _buildChartCard("Ratings Breakdown", _buildRatingsStackedBarChart()),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildFilterBar() { return SegmentedButton<DateRangeFilter>( segments: const [ ButtonSegment(value: DateRangeFilter.last7Days, label: Text('7 Days')), ButtonSegment(value: DateRangeFilter.last30Days, label: Text('30 Days')), ButtonSegment(value: DateRangeFilter.last6Months, label: Text('6 Months')), ButtonSegment(value: DateRangeFilter.allTime, label: Text('All Time')), ], selected: {_selectedFilter}, onSelectionChanged: (newSelection) { setState(() { _selectedFilter = newSelection.first; _filterAndCalculateStats(); }); }, ); }
  
  Widget _buildKpiSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth < 600 ? 2 : 4; // Responsive grid
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: crossAxisCount == 2 ? 1.6 : 1.6, // Adjust aspect ratio
          children: [
            _buildKpiCard('Total Revenue', 'RM ${_currentStats.totalRevenue.toStringAsFixed(2)}', Icons.monetization_on_outlined, Colors.green, _currentStats.revenueTrend),
            _buildKpiCard('Completed Jobs', _currentStats.completedJobs.toString(), Icons.check_circle_outline, Colors.blue, _currentStats.jobsTrend?.toDouble()),
            _buildKpiCard(
              'Average Rating',
              '${_currentStats.averageRating.toStringAsFixed(2)} (${_currentStats.ratingCount})',
              Icons.star_outline,
              Colors.orange,
              _currentStats.ratingTrend,
            ),
            _buildKpiCard(
              'Recommended',
              '${_currentStats.recommendationRate.toStringAsFixed(0)}% (${_currentStats.ratingCount})',
              Icons.thumb_up_outlined,
              Colors.purple,
              _currentStats.recommendationTrend,
            ),
          ],
        );
      }
    );
  }

  Widget _buildKpiCard(String label, String value, IconData icon, Color color, [double? trend]) {
    return Card( elevation: 2, child: Padding( padding: const EdgeInsets.all(12.0), child: Column( crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color),
          if (trend != null && trend != 0)
            Row(
              children: [
                Icon(trend > 0 ? Icons.arrow_upward : Icons.arrow_downward, color: trend > 0 ? Colors.green : Colors.red, size: 14),
                Text('${(trend * 100).toStringAsFixed(0)}%', style: TextStyle(color: trend > 0 ? Colors.green : Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            )
        ],
      ),
      const Spacer(), Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), Text(label, style: TextStyle(color: Colors.grey[600])), ], ), ), );
  }
  
  Widget _buildChartCard(String title, Widget chart) { return Card( elevation: 2, child: Padding( padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const SizedBox(height: 24), SizedBox(height: 200, child: chart), ], ), ), ); }

  Widget _buildRevenueChart() {
  if (_currentStats.revenueSpots.length < 2) {
    return const Center(child: Text("Not enough data to display a trend."));
  }

  final minX = _currentStats.revenueSpots.first.x;
  final maxX = _currentStats.revenueSpots.last.x;

  // Compute 5 evenly spaced tick positions
  final tickPositions = List<double>.generate(5, (i) {
    return minX + ((maxX - minX) / 4) * i;
  });

  return LineChart(
    LineChartData(
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (spot) => Colors.black87,
          getTooltipItems: (spots) => spots.map((spot) {
            final date = DateFormat.yMMMd().format(
              DateTime.fromMillisecondsSinceEpoch(spot.x.toInt()),
            );
            return LineTooltipItem(
              'RM ${spot.y.toStringAsFixed(2)}\n',
              const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
              children: [
                TextSpan(
                  text: date,
                  style: const TextStyle(
                      color: Colors.white70, fontWeight: FontWeight.normal),
                ),
              ],
            );
          }).toList(),
        ),
      ),
      gridData: const FlGridData(show: false),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (value, meta) {
              if (value == meta.min || value == meta.max) {
                return const SizedBox.shrink();
              }
              return SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(value.toInt().toString()),
              );
            },
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            getTitlesWidget: (value, meta) {
              // Only show labels at our 5 evenly spaced ticks
              const tolerance = 1000000; // ~1s in ms
              final match = tickPositions.any((tick) => (value - tick).abs() < tolerance);
              if (!match) return const SizedBox.shrink();

              final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
              return SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(
                  DateFormat('d/M').format(date),
                  style: const TextStyle(fontSize: 10),
                ),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: _currentStats.revenueSpots,
          isCurved: true,
          color: Colors.green,
          barWidth: 3,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
              show: true, color: Colors.green.withOpacity(0.2)),
        ),
      ],
    ),
  );
}

  Widget _buildStatusPieChart() {
    final statusColors = {'Completed': Colors.green, 'Cancelled': Colors.grey, 'Declined': Colors.red};
    final total = _currentStats.bookingStatusCounts.values.fold(0, (a, b) => a + b);
    if (total == 0) return const Center(child: Text("No booking history for this period."));

    return Column(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              pieTouchData: PieTouchData(
                touchCallback: (event, pieTouchResponse) { /* Can add interaction here */ }
              ),
              sections: _currentStats.bookingStatusCounts.entries.map((entry) {
                final percentage = (entry.value / total) * 100;
                return PieChartSectionData(
                  color: statusColors[entry.key] ?? Colors.blue,
                  value: entry.value.toDouble(),
                  title: '${percentage.toStringAsFixed(0)}%',
                  radius: 80,
                  titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white, shadows: [Shadow(color: Colors.black, blurRadius: 2)]),
                );
              }).toList(),
              sectionsSpace: 2,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _currentStats.bookingStatusCounts.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: _buildLegendItem(statusColors[entry.key]!, '${entry.key} (${entry.value})'),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTopCategoriesChart() {
    final entries = _currentStats.topCategoriesRevenue.entries.toList()
      ..sort((a,b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return const Center(child: Text("No revenue from services yet."));
    final top5 = entries.take(5).toList();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        gridData: const FlGridData(show: false),
        barTouchData: BarTouchData(
  touchTooltipData: BarTouchTooltipData(
    getTooltipColor: (group) => Colors.black87, // Use this callback instead
    getTooltipItem: (group, groupIndex, rod, rodIndex) {
      final categoryName = entries[groupIndex].key;
      return BarTooltipItem(
        '$categoryName\n',
        const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        children: [
          TextSpan(
            text: 'RM ${rod.toY.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.normal),
          ),
        ],
      );
    },
  ),
),
        barGroups: top5.asMap().entries.map((entry) {
          return BarChartGroupData(
            x: entry.key,
            barRods: [BarChartRodData(toY: entry.value.value, color: Colors.blue, width: 22, borderRadius: BorderRadius.zero)]
          );
        }).toList(),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, 
          getTitlesWidget: (value, meta) {
            // Skip min and max
            if (value == meta.min || value == meta.max) {
              return const SizedBox.shrink();
            }
            return SideTitleWidget(
              axisSide: meta.axisSide,
              child: Text(value.toInt().toString()),
            );
          }

            )
            ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
              return SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(
                  top5[value.toInt()].key.split(' ').first,
                  style: const TextStyle(fontSize: 10),
                ),
              );
            },
          )),
        ),
      ),
    );
  }

  Widget _buildRatingsStackedBarChart() {
    final sources = _currentStats.ratingSources;
    if (sources.values.every((s) => s.standard == 0 && s.custom == 0)) {
      return const Center(child: Text("No ratings received in this period."));
    }
    
    return Column(
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              gridData: const FlGridData(show: false),
              barTouchData: BarTouchData(
  touchTooltipData: BarTouchTooltipData(
    getTooltipColor: (group) => Colors.black87, // Use this callback instead
    getTooltipItem: (group, groupIndex, rod, rodIndex) {
  final ratingValue = group.x.toInt();
  final standardCount = _currentStats.ratingSources[ratingValue]?.standard ?? 0;
  final customCount = _currentStats.ratingSources[ratingValue]?.custom ?? 0;
  String standardText = 'Standard: $standardCount';
  String customText = 'Custom: $customCount';
  return BarTooltipItem(
    '$standardText\n$customText',
    const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.bold,
    ),
  );
},
  ),
),
              barGroups: List.generate(5, (index) {
                final rating = index + 1;
                final standardCount = sources[rating]?.standard.toDouble() ?? 0;
                final customCount = sources[rating]?.custom.toDouble() ?? 0;
                return BarChartGroupData(
                  x: rating,
                  barRods: [
                    BarChartRodData(
                      toY: standardCount + customCount,
                      color: Colors.transparent,
                      width: 22,
                      borderRadius: BorderRadius.zero,
                      rodStackItems: [
                        BarChartRodStackItem(0, standardCount, Colors.teal),
                        BarChartRodStackItem(standardCount, standardCount + customCount, Colors.cyan),
                      ],
                    ),
                  ],
                );
              }),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (value, meta) => SideTitleWidget(axisSide: meta.axisSide, child: Text(value.toInt().toString())))),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    return SideTitleWidget(axisSide: meta.axisSide, child: Text('${value.toInt()} ★', style: const TextStyle(fontSize: 10)));
                  },
                )),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildLegendItem(Colors.teal, 'Standard Services'),
            const SizedBox(width: 16),
            _buildLegendItem(Colors.cyan, 'Custom Requests'),
          ],
        )
      ],
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
  
  double _getChartInterval() {
    switch (_selectedFilter) {
      case DateRangeFilter.last7Days: return const Duration(days: 2).inMilliseconds.toDouble();
      case DateRangeFilter.last30Days: return const Duration(days: 7).inMilliseconds.toDouble();
      case DateRangeFilter.last6Months: return const Duration(days: 45).inMilliseconds.toDouble();
      case DateRangeFilter.allTime: return const Duration(days: 90).inMilliseconds.toDouble();
    }
  }
}
