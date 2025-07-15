import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/water_log_service.dart';
import '../screens/log_water_screen.dart';
import '../widgets/usage_chart.dart';
import '../widgets/add_house_info_form.dart';
import '../widgets/daily_water_log_form.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/water_log.dart'; // Added import for WaterLog
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import '../screens/login_screen.dart';

class DashboardPage extends StatelessWidget {
  final User user;
  final WaterLogService waterLogService;

  const DashboardPage({
    Key? key,
    required this.user,
    required this.waterLogService,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('daily_water_logs')
          .where('userEmail', isEqualTo: user.email)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Welcome to AquaTrack Dashboard')),
            body: Center(child: Text('Error: \n${snapshot.error}')),
          );
        }
        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('Welcome to AquaTrack Dashboard')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final docs = snapshot.data!.docs;
        // Parse logs
        final logs = docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final date = DateTime.tryParse(data['date'] ?? '') ?? DateTime.now();
          final totalLiters = (data['totalLiters'] is num) ? (data['totalLiters'] as num).toDouble() : 0.0;
          return {
            'date': date,
            'totalLiters': totalLiters,
            'activityType': data['activityType'],
            'amount': data['amount'],
            'unit': data['unit'],
            'note': data['note'],
          };
        }).toList();
        // For UsageChart, convert logs to WaterLog objects (if needed)
        final chartLogs = docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return WaterLog(
            timestamp: DateTime.tryParse(data['date'] ?? '') ?? DateTime.now(),
            activityType: data['activityType']?.toString() ?? '',
            amount: (data['amount'] is num) ? (data['amount'] as num).toDouble() : 0.0,
            unit: data['unit']?.toString() ?? '',
            note: data['note']?.toString(),
          );
        }).toList();
        // Calculate stats
        final now = DateTime.now();
        final todayLogs = logs.where((log) =>
          log['date'].year == now.year &&
          log['date'].month == now.month &&
          log['date'].day == now.day
        ).toList();
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        final weekLogs = logs.where((log) {
          final d = log['date'];
          return d.isAfter(weekStart.subtract(const Duration(days: 1))) && d.isBefore(now.add(const Duration(days: 1)));
        }).toList();
        final totalAmount = todayLogs.fold<double>(0, (sum, log) => sum + (log['totalLiters'] ?? 0.0));
        final activityCount = todayLogs.length;
        final weekTotal = weekLogs.fold<double>(0, (sum, log) => sum + (log['totalLiters'] ?? 0.0));
        final goalPercent = user.waterUsageGoalPercent;
        final goalTarget = weekTotal > 0 ? weekTotal * (1 - goalPercent / 100) : 0;

        return Scaffold(
          appBar: AppBar(title: const Text('Welcome to AquaTrack Dashboard')),
          drawer: Drawer(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Onboard Info'),
                  onTap: () {
                    Navigator.pop(context);
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Onboarding Information'),
                        content: const Text('Welcome to AquaTrack! Here you can track your household water usage, set goals, and view your progress. Use the dashboard to log water usage and monitor your achievements.'),
                        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                      ),
                    );
                  },
                ),
                DrawerHeader(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade700, Colors.blue.shade400],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: Icon(Icons.water_drop, size: 36, color: Colors.blue.shade700),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        user.email.isNotEmpty ? user.email : 'Welcome!',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'AquaTrack User',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                // Replace House Info ListTile with ExpansionTile
                ExpansionTile(
                  leading: const Icon(Icons.house),
                  title: const Text('House Info'),
                  children: [
                    ListTile(
                      leading: const Icon(Icons.add_home),
                      title: const Text('Add House Info'),
                      onTap: () {
                        Navigator.pop(context);
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Add House Info'),
                            content: AddHouseInfoForm(email: user.email),
                            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                            actions: [], // Form handles its own actions
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.manage_accounts),
                      title: const Text('Manage House Info'),
                      onTap: () async {
                        Navigator.pop(context);
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) {
                            return FutureBuilder<Widget>(
                              future: (() async {
                                final doc = await FirebaseFirestore.instance.collection('users').doc(user.email).get();
                                if (!doc.exists) {
                                  return AlertDialog(
                                    title: const Text('Manage House Info'),
                                    content: const Text('No house info found.'),
                                    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                                  );
                                }
                                final data = doc.data()!;
                                return AlertDialog(
                                  title: const Text('Manage House Info'),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Household Size:  ${data['householdSize'] ?? '-'}'),
                                      Text('Location:  ${data['location'] ?? '-'}'),
                                      Text('Goal:  ${data['waterUsageGoalPercent'] ?? '-'}%'),
                                      Text('Reasons:  ${(data['goalReasons'] as List?)?.join(", ") ?? '-'}'),
                                      if (data['goalReasonOther'] != null && (data['goalReasonOther'] as String).isNotEmpty)
                                        Text('Other Reason:  ${data['goalReasonOther']}'),
                                      Text('Water Bill:  ${data['averageWaterBill'] ?? '-'}'),
                                      Text('Meter Option:  ${data['usesSmartMeter'] == true ? 'Smart Meter' : 'Manual'}'),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Close'),
                                    ),
                                    TextButton(
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text('Delete House Info'),
                                            content: const Text('Are you sure you want to delete your house info? This cannot be undone.'),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                                            ],
                                          ),
                                        );
                                        if (confirm == true) {
                                          await FirebaseFirestore.instance.collection('users').doc(user.email).delete();
                                          if (context.mounted) {
                                            Navigator.pop(context); // Close the manage dialog
                                            showDialog(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: const Text('Deleted'),
                                                content: const Text('House info deleted.'),
                                                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                                              ),
                                            );
                                          }
                                        }
                                      },
                                      child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(context); // Close the manage dialog
                                        showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text('Edit House Info'),
                                            content: AddHouseInfoForm(
                                              email: user.email,
                                              initialHouseholdSize: data['householdSize'] is int ? data['householdSize'] : int.tryParse(data['householdSize']?.toString() ?? ''),
                                              initialLocation: data['location'] as String?,
                                              initialGoalPercent: data['waterUsageGoalPercent'] is int ? data['waterUsageGoalPercent'] : (data['waterUsageGoalPercent'] is double ? (data['waterUsageGoalPercent'] as double).toInt() : int.tryParse(data['waterUsageGoalPercent']?.toString() ?? '')),
                                              initialGoalReasons: (data['goalReasons'] as List?)?.map((e) => e.toString()).toList(),
                                              initialGoalReasonOther: data['goalReasonOther'] as String?,
                                              initialWaterBill: data['averageWaterBill'] is double ? data['averageWaterBill'] : (data['averageWaterBill'] is int ? (data['averageWaterBill'] as int).toDouble() : double.tryParse(data['averageWaterBill']?.toString() ?? '')),
                                              initialMeterOption: data['usesSmartMeter'] == true ? 'smart' : 'manual',
                                            ),
                                            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                                            actions: [],
                                          ),
                                        );
                                      },
                                      child: const Text('Edit'),
                                    ),
                                  ],
                                );
                              })(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return const AlertDialog(
                                    title: Text('Manage House Info'),
                                    content: SizedBox(height: 60, child: Center(child: CircularProgressIndicator())),
                                  );
                                }
                                return snapshot.data!;
                              },
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
                // Replace Recent Logs ListTile with ExpansionTile
                ExpansionTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Recent Logs'),
                  children: [
                    ListTile(
                      leading: const Icon(Icons.check_circle_outline),
                      title: const Text('Check Water Usage'),
                      onTap: () {
                        Navigator.pop(context);
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Daily Water Usage Log'),
                            content: DailyWaterLogForm(
                              initialLocation: null,
                              onSubmit: (data) async {
                                Navigator.pop(context); // Close the form dialog
                                try {
                                  await FirebaseFirestore.instance.collection('daily_water_logs').add({
                                    'userEmail': user.email,
                                    ...data,
                                    'date': (data['date'] as DateTime).toIso8601String(),
                                  });
                                  // Show success dialog
                                  if (context.mounted) {
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Saved'),
                                        content: const Text('Your daily water log has been saved.'),
                                        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Error'),
                                        content: Text('Failed to save: $e'),
                                        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                            actions: [],
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.list_alt),
                      title: const Text('View Recent Log'),
                      onTap: () {
                        Navigator.pop(context);
                        showDialog(
                          context: context,
                          builder: (context) {
                            return FutureBuilder<QuerySnapshot>(
                              future: FirebaseFirestore.instance
                                  .collection('daily_water_logs')
                                  .where('userEmail', isEqualTo: user.email)
                                  .orderBy('date', descending: true)
                                  .limit(7)
                                  .get(),
                              builder: (context, snapshot) {
                                if (snapshot.hasError) {
                                  return AlertDialog(
                                    title: const Text('Error'),
                                    content: Text('Error: \n${snapshot.error}'),
                                    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                                  );
                                }
                                if (!snapshot.hasData) {
                                  return const AlertDialog(
                                    title: Text('Recent Logs'),
                                    content: SizedBox(height: 60, child: Center(child: CircularProgressIndicator())),
                                  );
                                }
                                final docs = snapshot.data!.docs;
                                if (docs.isEmpty) {
                                  return AlertDialog(
                                    title: const Text('Recent Logs'),
                                    content: const Text('No recent logs found.'),
                                    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                                  );
                                }
                                return AlertDialog(
                                  title: const Text('Recent Logs'),
                                  content: SizedBox(
                                    width: 350,
                                    height: 400,
                                    child: ListView.separated(
                                      shrinkWrap: true,
                                      itemCount: docs.length,
                                      separatorBuilder: (_, __) => const Divider(),
                                      itemBuilder: (context, i) {
                                        final data = docs[i].data() as Map<String, dynamic>;
                                        final date = DateTime.tryParse(data['date'] ?? '') ?? DateTime.now();
                                        final totalLiters = data['totalLiters'] ?? '-';
                                        final tip = data['tip'] ?? '';
                                        return ListTile(
                                          title: Text('${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'),
                                          subtitle: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('Total: ${totalLiters.toStringAsFixed(1)} liters'),
                                              if (tip.isNotEmpty) Text('Tip: $tip'),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
                ListTile(
                  leading: const Icon(Icons.person),
                  title: const Text('Profile'),
                  onTap: () {
                    Navigator.pop(context);
                    showDialog(
                      context: context,
                      builder: (context) {
                        return FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance.collection('users').doc(user.email).get(),
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return AlertDialog(
                                title: const Text('Profile'),
                                content: Text('Error: \n${snapshot.error}'),
                                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                              );
                            }
                            if (!snapshot.hasData) {
                              return const AlertDialog(
                                title: Text('Profile'),
                                content: SizedBox(height: 60, child: Center(child: CircularProgressIndicator())),
                              );
                            }
                            final data = snapshot.data!.data() as Map<String, dynamic>?;
                            if (data == null) {
                              return AlertDialog(
                                title: const Text('Profile'),
                                content: const Text('No profile data found.'),
                                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                              );
                            }
                            return AlertDialog(
                              title: const Text('Profile'),
                              content: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Email: ${data['email'] ?? '-'}'),
                                    Text('Household Size: ${data['householdSize']?.toString() ?? 'Not set'}'),
                                    Text('Water Usage Goal: ${data['waterUsageGoalPercent']?.toString() ?? 'Not set'}%'),
                                    Text('Average Water Bill: ${data['averageWaterBill']?.toString() ?? 'Not set'}'),
                                    Text('Smart Meter: ${data['usesSmartMeter'] == true ? 'Yes' : 'No'}'),
                                  ],
                                ),
                              ),
                              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                            );
                          },
                        );
                      },
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.emoji_events),
                  title: const Text('Achievements'),
                  onTap: () {
                    Navigator.pop(context);
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Achievements'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Need Payment Method to Unlock Premium'),
                            const SizedBox(height: 16),
                            ListTile(
                              leading: const Icon(Icons.star, color: Colors.amber),
                              title: const Text('Premium'),
                              onTap: () {
                                Navigator.pop(context);
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Go Premium'),
                                    content: const Text('Unlock premium features for just 5 USD!'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          showDialog(
                                            context: context,
                                            builder: (context) {
                                              String paymentMethod = 'PayPal';
                                              final controller = TextEditingController();
                                              return StatefulBuilder(
                                                builder: (context, setState) => AlertDialog(
                                                  title: const Text('Choose Payment Method'),
                                                  content: Column(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      DropdownButton<String>(
                                                        value: paymentMethod,
                                                        items: [
                                                          DropdownMenuItem(
                                                            value: 'PayPal',
                                                            child: Row(
                                                              children: [
                                                                Icon(Icons.account_balance_wallet, color: Colors.blue),
                                                                const SizedBox(width: 8),
                                                                const Text('PayPal'),
                                                              ],
                                                            ),
                                                          ),
                                                          DropdownMenuItem(
                                                            value: 'Mobile Money',
                                                            child: Row(
                                                              children: [
                                                                Icon(Icons.phone_android, color: Colors.amber),
                                                                const SizedBox(width: 8),
                                                                const Text('Mobile Money'),
                                                              ],
                                                            ),
                                                          ),
                                                          DropdownMenuItem(
                                                            value: 'Bank of Kigali',
                                                            child: Row(
                                                              children: [
                                                                Icon(Icons.account_balance, color: Colors.green),
                                                                const SizedBox(width: 8),
                                                                const Text('Bank of Kigali'),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                        onChanged: (v) => setState(() => paymentMethod = v!),
                                                      ),
                                                      const SizedBox(height: 12),
                                                      if (paymentMethod == 'Mobile Money')
                                                        TextField(
                                                          controller: controller,
                                                          decoration: const InputDecoration(labelText: 'Mobile Money Number'),
                                                          keyboardType: TextInputType.phone,
                                                        ),
                                                      if (paymentMethod == 'PayPal' || paymentMethod == 'Bank of Kigali')
                                                        TextField(
                                                          controller: controller,
                                                          decoration: const InputDecoration(labelText: 'Account Number'),
                                                          keyboardType: TextInputType.text,
                                                        ),
                                                      const SizedBox(height: 16),
                                                      const Text('Amount: 5 USD'),
                                                    ],
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(context),
                                                      child: const Text('Cancel'),
                                                    ),
                                                    ElevatedButton(
                                                      onPressed: () async {
                                                        Navigator.pop(context);
                                                        // Show simple notification dialog
                                                        if (context.mounted) {
                                                          showDialog(
                                                            context: context,
                                                            builder: (context) => AlertDialog(
                                                              title: const Text('Payment Processed'),
                                                              content: const Text('Your payment is processed. Feature will be unlocked soon.'),
                                                              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                                                            ),
                                                          );
                                                        }
                                                      },
                                                      child: const Text('Pay'),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          );
                                        },
                                        child: const Text('Subscribe'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: const Text('Settings'),
                  onTap: () {
                    Navigator.pop(context);
                    showDialog(
                      context: context,
                      builder: (context) {
                        bool isDarkTheme = false;
                        bool notificationsOn = true;
                        return StatefulBuilder(
                          builder: (context, setState) => AlertDialog(
                            title: const Text('Settings'),
                            content: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Theme'),
                                      Switch(
                                        value: isDarkTheme,
                                        onChanged: (v) => setState(() => isDarkTheme = v),
                                      ),
                                      Text(isDarkTheme ? 'Dark' : 'Light'),
                                    ],
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Notifications'),
                                      Switch(
                                        value: notificationsOn,
                                        onChanged: (v) => setState(() => notificationsOn = v),
                                      ),
                                      Text(notificationsOn ? 'On' : 'Off'),
                                    ],
                                  ),
                                  const Divider(),
                                  const Text('App Version: 1.0.0'),
                                  const SizedBox(height: 8),
                                  const Text('About:'),
                                  const Text('AquaTrack helps you track and reduce your household water usage.'),
                                  const SizedBox(height: 8),
                                  const Text('Contact: support@aquatrack.com'),
                                  const SizedBox(height: 8),
                                  GestureDetector(
                                    onTap: () {},
                                    child: const Text('Privacy Policy', style: TextStyle(decoration: TextDecoration.underline, color: Colors.blue)),
                                  ),
                                ],
                              ),
                            ),
                            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                          ),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 24),
                Divider(),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text('Logout', style: TextStyle(color: Colors.red)),
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Confirm Logout'),
                        content: const Text('Are you sure you want to log out?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Logout', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (context) => LoginScreen(
                            onLogin: (user) {}, // TODO: Replace with your actual onLogin callback
                            onCreateAccount: () {}, // TODO: Replace with your actual onCreateAccount callback
                          ),
                        ),
                        (route) => false,
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Welcome, ${user.email}!',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 18),
                // Row for the first two cards
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      // Today's Water Usage
                      Expanded(
                        child: Card(
                          color: Colors.blue.shade700,
                          elevation: 8,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Today's Water Usage",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  totalAmount == 0 ? 'No usage logged yet.' : '${totalAmount.toStringAsFixed(1)} liters',
                                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  activityCount == 1 ? '1 activity logged' : '$activityCount activities logged',
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // This Week's Usage
                      Expanded(
                        child: Card(
                          color: Colors.blue.shade600,
                          elevation: 6,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "This Week's Usage",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  weekTotal == 0 ? 'No usage logged yet.' : '${weekTotal.toStringAsFixed(1)} liters',
                                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Goal Progress full width
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Card(
                    color: Colors.blue.shade50,
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Goal Progress',
                            style: TextStyle(
                              color: Color(0xFF1976D2),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            goalTarget == 0 ? 'Set a goal in onboarding.' : 'Target: ${goalTarget.toStringAsFixed(1)} liters/week',
                            style: const TextStyle(
                              color: Color(0xFF1976D2),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (weekTotal > 0 && goalTarget > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: LinearProgressIndicator(
                                value: (weekTotal / goalTarget).clamp(0, 1),
                                backgroundColor: Colors.blue.shade100,
                                color: Colors.blue.shade700,
                                minHeight: 10,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // UsageChart and button (optional: you can update UsageChart to use logs)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: UsageChart(logs: chartLogs),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 24.0),
                      child: Text(
                        '© SHYAKA Aimable Mobile App development',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }
}
