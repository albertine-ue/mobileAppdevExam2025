import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/skill_model.dart';
import '../models/notification_model.dart';
import '../models/session_model.dart';
import '../services/app_service.dart';
import '../services/navigation_service.dart';
import 'login_screen.dart';
import 'find_partner_screen.dart';
import 'schedule_session_screen.dart';
import 'requested_skills_screen.dart';
import 'badges_screen.dart';

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic>? userData;

  const HomeScreen({super.key, this.userData});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NavigationService _navigationService = NavigationService();
  User? _user;
  Map<String, dynamic>? _userData;

  // Loading flags for each section
  bool _loadingUser = false;
  bool _loadingSkills = false;
  bool _loadingSessions = false;
  bool _loadingNotifications = false;
  bool _loadingStats = false;

  // Data
  List<Skill> _skillRequests = [];
  List<SessionModel> _recentSessions = [];
  List<NotificationModel> _recentNotifications = [];
  SkillStats? _skillStats;
  Map<String, dynamic>? _sessionStats;

  @override
  void initState() {
    super.initState();
    _user = _auth.currentUser;
    _userData = widget.userData;
    _navigationService.addListener(_onNavigationChanged);

    if (_user != null &&
        (_userData == null || _userData?['fullName'] == null)) {
      _loadUserData();
    } else if (_userData != null) {
      _startAllLoads();
    }
  }

  @override
  void dispose() {
    _navigationService.removeListener(_onNavigationChanged);
    super.dispose();
  }

  void _onNavigationChanged() {
    setState(() {});
  }

  Future<void> _loadUserData() async {
    if (_user == null) return;
    setState(() => _loadingUser = true);
    try {
      final doc = await _firestore.collection('users').doc(_user!.uid).get();
      if (doc.exists) {
        setState(() {
          _userData = doc.data();
        });
        _startAllLoads();
      }
    } catch (e) {
      setState(() => _loadingUser = false);
    }
  }

  void _startAllLoads() {
    _loadSkillRequests();
    _loadRecentSessions();
    _loadRecentNotifications();
    _loadStats();
  }

  Future<void> _loadSkillRequests() async {
    setState(() => _loadingSkills = true);
    if (_userData == null) return;
    try {
      final userSkills = List<String>.from(_userData!['skillsOffered'] ?? []);
      if (userSkills.isEmpty) {
        setState(() {
          _skillRequests = [];
          _loadingSkills = false;
        });
        return;
      }
      final querySnapshot = await _firestore
          .collection('users')
          .where('skillsToLearn', arrayContainsAny: userSkills)
          .where('uid', isNotEqualTo: _user!.uid)
          .where('isOnline', isEqualTo: true)
          .limit(5)
          .get();
      final requests = <Skill>[];
      for (final doc in querySnapshot.docs) {
        final userData = doc.data();
        final matchingSkills = userSkills
            .where((skill) =>
                (userData['skillsToLearn'] as List<dynamic>).contains(skill))
            .toList();
        if (matchingSkills.isNotEmpty) {
          final skill = Skill(
            id: doc.id,
            name: matchingSkills.first,
            description: 'Looking for ${matchingSkills.join(', ')}',
            category: 'Request',
            difficulty: 'Any',
            tags: matchingSkills,
            userId: doc.id,
            userName: userData['fullName'] ?? 'Unknown User',
            userPhotoUrl: userData['photoUrl'] ?? '',
            createdAt: (userData['updatedAt'] as Timestamp?)?.toDate() ??
                DateTime.now(),
            updatedAt: (userData['updatedAt'] as Timestamp?)?.toDate() ??
                DateTime.now(),
            location: userData['location'] ?? 'Unknown Location',
            availability: userData['availability'] ?? 'Unknown',
          );
          requests.add(skill);
        }
      }
      if (!mounted) return;
      setState(() {
        _skillRequests = requests;
        _loadingSkills = false;
      });
    } catch (e) {
      debugPrint('Error loading skill requests: $e');
      setState(() => _loadingSkills = false);
    }
  }

  Future<void> _loadRecentSessions() async {
    setState(() => _loadingSessions = true);
    if (_user == null) return;
    try {
      final sessions = await AppService.getUserSessions(_user!.uid);
      if (!mounted) return;
      setState(() {
        _recentSessions = sessions.take(3).toList();
        _loadingSessions = false;
      });
    } catch (e) {
      debugPrint('Error loading recent sessions: $e');
      setState(() => _loadingSessions = false);
    }
  }

  Future<void> _loadRecentNotifications() async {
    setState(() => _loadingNotifications = true);
    if (_user == null) return;
    try {
      final notifications =
          await AppService.getUserNotifications(_user!.uid, limit: 5);
      if (!mounted) return;
      setState(() {
        _recentNotifications = notifications;
        _loadingNotifications = false;
      });
    } catch (e) {
      debugPrint('Error loading recent notifications: $e');
      setState(() => _loadingNotifications = false);
    }
  }

  Future<void> _loadStats() async {
    setState(() => _loadingStats = true);
    if (_user == null) return;
    try {
      final skillStats = await AppService.getSkillStats(_user!.uid);
      final sessionStats = await AppService.getSessionStats(_user!.uid);
      if (!mounted) return;
      setState(() {
        _skillStats = skillStats;
        _sessionStats = sessionStats;
        _loadingStats = false;
      });
    } catch (e) {
      debugPrint('Error loading stats: $e');
      setState(() => _loadingStats = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await _auth.signOut();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      debugPrint('Error signing out: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final String userName = _userData?['fullName'] ?? 'User';
    return Scaffold(
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        onRefresh: () async {
          _startAllLoads();
        },
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Removed the top welcome message
                // _buildWelcomeCard(userName) remains below
                _buildWelcomeCard(userName),
                const SizedBox(height: 20),
                // Stats Cards
                if (_loadingStats)
                  _buildStatsSkeleton()
                else if (_skillStats != null || _sessionStats != null) ...[
                  _buildStatsSection(),
                  const SizedBox(height: 20),
                ],
                // Feature Grid
                _buildFeatureGrid(),
                const SizedBox(height: 24),
                // Skill Requests Section
                if (_loadingSkills)
                  _buildSkillRequestsSkeleton()
                else if (_skillRequests.isNotEmpty) ...[
                  _buildSkillRequestsSection(),
                  const SizedBox(height: 24),
                ],
                // Recent Sessions Section
                if (_loadingSessions)
                  _buildRecentSessionsSkeleton()
                else if (_recentSessions.isNotEmpty) ...[
                  _buildRecentSessionsSection(),
                  const SizedBox(height: 24),
                ],
                // Recent Notifications Section
                if (_loadingNotifications)
                  _buildRecentNotificationsSkeleton()
                else if (_recentNotifications.isNotEmpty) ...[
                  _buildRecentNotificationsSection(),
                  const SizedBox(height: 24),
                ],
                // Empty State
                if (!_loadingSkills &&
                    !_loadingSessions &&
                    !_loadingNotifications &&
                    _skillRequests.isEmpty &&
                    _recentSessions.isEmpty &&
                    _recentNotifications.isEmpty) ...[
                  _buildEmptyState(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeCard(String userName) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[800]!, Colors.blue[600]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: Colors.white.withOpacity(0.2),
                backgroundImage: _userData?['photoUrl'] != null
                    ? NetworkImage(_userData!['photoUrl'])
                    : null,
                child: _userData?['photoUrl'] == null
                    ? Text(
                        userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome back, $userName!',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ready to learn something new today?',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white),
                onPressed: _signOut,
                tooltip: 'Logout',
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              // Skills Counter
              StreamBuilder<List<Skill>>(
                stream: _user == null
                    ? null
                    : AppService.listenToSkills(userId: _user!.uid),
                builder: (context, snapshot) {
                  final count = snapshot.hasData ? snapshot.data!.length : 0;
                  return _buildStatItem(
                    icon: Icons.school,
                    value: count.toString(),
                    label: 'Skills',
                    color: Colors.white,
                  );
                },
              ),
              const SizedBox(width: 20),
              // Sessions Counter
              StreamBuilder<List<SessionModel>>(
                stream: _user == null
                    ? null
                    : AppService.listenToUserSessions(_user!.uid),
                builder: (context, snapshot) {
                  final completed = snapshot.hasData
                      ? snapshot.data!
                          .where((s) => s.status == SessionStatus.completed)
                          .length
                      : 0;
                  return _buildStatItem(
                    icon: Icons.event,
                    value: completed.toString(),
                    label: 'Sessions',
                    color: Colors.white,
                  );
                },
              ),
              const SizedBox(width: 20),
              // Alerts Counter
              StreamBuilder<List<NotificationModel>>(
                stream: _user == null
                    ? null
                    : AppService.listenToNotifications(_user!.uid),
                builder: (context, snapshot) {
                  final unread = snapshot.hasData
                      ? snapshot.data!.where((n) => !n.isRead).length
                      : 0;
                  return _buildStatItem(
                    icon: Icons.notifications,
                    value: unread.toString(),
                    label: 'Alerts',
                    color: Colors.white,
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: color.withOpacity(0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsSection() {
    return Row(
      children: [
        // Skills Stat Card
        Expanded(
          child: StreamBuilder<List<Skill>>(
            stream: _user == null
                ? null
                : AppService.listenToSkills(userId: _user!.uid),
            builder: (context, snapshot) {
              final skills = snapshot.data ?? [];
              final totalSkills = skills.length;
              final activeSkills = skills.where((s) => s.isActive).length;
              return _buildStatCard(
                title: 'Skills',
                value: totalSkills.toString(),
                subtitle: 'Active: $activeSkills',
                icon: Icons.school,
                color: Colors.blue,
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        // Sessions Stat Card
        Expanded(
          child: StreamBuilder<List<SessionModel>>(
            stream: _user == null
                ? null
                : AppService.listenToUserSessions(_user!.uid),
            builder: (context, snapshot) {
              final sessions = snapshot.data ?? [];
              final completed = sessions
                  .where((s) => s.status == SessionStatus.completed)
                  .length;
              final total = sessions.length;
              final completionRate =
                  total > 0 ? (completed / total) * 100 : 0.0;
              return _buildStatCard(
                title: 'Sessions',
                value: completed.toString(),
                subtitle: '${completionRate.toStringAsFixed(1)}% completion',
                icon: Icons.event,
                color: Colors.green,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSessionStatCard() {
    if (_user == null) {
      return _buildStatCard(
        title: 'Sessions',
        value: '0',
        subtitle: '0.0% completion',
        icon: Icons.event,
        color: Colors.green,
      );
    }
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('sessions')
          .where('participants', arrayContains: _user!.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return _buildStatCard(
            title: 'Sessions',
            value: '0',
            subtitle: '0.0% completion',
            icon: Icons.event,
            color: Colors.green,
          );
        }
        final allSessions = snapshot.data!.docs;
        final completedSessions = allSessions
            .where((doc) => (doc['status'] ?? '') == 'completed')
            .length;
        final totalSessions = allSessions.length;
        final completionRate =
            totalSessions > 0 ? (completedSessions / totalSessions) * 100 : 0.0;
        return _buildStatCard(
          title: 'Sessions',
          value: completedSessions.toString(),
          subtitle: '${completionRate.toStringAsFixed(1)}% completion',
          icon: Icons.event,
          color: Colors.green,
        );
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureGrid() {
    const int unreadCount = 0;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.1,
      children: [
        _featureButton(
          icon: Icons.search,
          label: 'Find Partner',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const FindPartnerScreen(),
              ),
            );
          },
        ),
        _featureButton(
          icon: Icons.event,
          label: 'My Sessions',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ScheduleSessionScreen(),
              ),
            );
          },
        ),
        _featureButton(
          icon: Icons.chat_bubble_outline,
          label: 'Messenger',
          badge: unreadCount > 0 ? unreadCount.toString() : null,
          onTap: () {
            // Navigator.push(
            //   context,
            //   MaterialPageRoute(
            //     builder: (context) => const ChatListScreen(),
            //   ),
            // );
          },
        ),
        _featureButton(
          icon: Icons.emoji_events,
          label: 'My Badges',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const BadgesScreen(),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSkillRequestsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Skill Requests',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        RequestedSkillsScreen(requests: _skillRequests),
                  ),
                );
              },
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._skillRequests.map((skill) => _buildSkillRequestCard(skill)),
      ],
    );
  }

  Widget _buildSkillRequestCard(Skill skill) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: Colors.blue[100],
          backgroundImage: skill.userPhotoUrl.isNotEmpty
              ? NetworkImage(skill.userPhotoUrl)
              : null,
          child: skill.userPhotoUrl.isEmpty
              ? Text(
                  skill.userName.isNotEmpty
                      ? skill.userName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(color: Colors.blue),
                )
              : null,
        ),
        title: Text(
          skill.userName,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Looking for: ${skill.tags.take(2).join(', ')}',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  skill.location,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(width: 16),
                Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  skill.timeAgo,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            skill.availability,
            style: TextStyle(
              color: Colors.green[700],
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RequestedSkillsScreen(
                  requests: _skillRequests, initialSkill: skill),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecentSessionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Sessions',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 8),
        ..._recentSessions.map((session) => _buildSessionCard(session)),
      ],
    );
  }

  Widget _buildSessionCard(SessionModel session) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(session.typeIcon, size: 32, color: session.statusColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        session.description,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        session.formattedScheduledTime,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: session.statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    session.status.toString().split('.').last,
                    style: TextStyle(
                      color: session.statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            if (session.status != SessionStatus.completed)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.check_circle, color: Colors.green),
                  label: const Text('Mark as Completed'),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Confirm Completion'),
                        content: const Text(
                            'Are you sure you want to mark this session as completed?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Confirm'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      final updated = session.endSession();
                      final success = await AppService.updateSession(updated);
                      if (success && mounted) {
                        setState(() {}); // Refresh UI
                      }
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentNotificationsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Notifications',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 8),
        ..._recentNotifications
            .map((notification) => _buildNotificationCard(notification)),
      ],
    );
  }

  Widget _buildNotificationCard(NotificationModel notification) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: notification.priorityColor.withOpacity(0.1),
          child: Icon(
            notification.typeIcon,
            color: notification.priorityColor,
            size: 20,
          ),
        ),
        title: Text(
          notification.title,
          style: TextStyle(
            fontWeight:
                notification.isRead ? FontWeight.normal : FontWeight.bold,
            fontSize: 15,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              notification.preview,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              notification.timeAgo,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
        trailing: !notification.isRead
            ? Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: notification.priorityColor,
                  shape: BoxShape.circle,
                ),
              )
            : null,
        onTap: () {
          // Handle notification tap
          if (!notification.isRead) {
            AppService.markAsRead(notification.id);
          }
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          children: [
            Icon(
              Icons.rocket_launch,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Welcome to SkillSwap!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start by adding your skills or finding partners to learn from',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    // Navigate to add skills
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add Skills'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[800],
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const FindPartnerScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.search),
                  label: const Text('Find Partners'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _featureButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? badge,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Stack(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 36, color: Colors.blue[700]),
                    const SizedBox(height: 10),
                    Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                if (badge != null)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Skeleton Widgets ---
  Widget _buildStatsSkeleton() {
    return Row(
      children: [
        Expanded(child: _skeletonBox(height: 80)),
        const SizedBox(width: 12),
        Expanded(child: _skeletonBox(height: 80)),
      ],
    );
  }

  Widget _buildSkillRequestsSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _skeletonBox(height: 24, width: 120),
        const SizedBox(height: 12),
        _skeletonBox(height: 60),
        const SizedBox(height: 8),
        _skeletonBox(height: 60),
      ],
    );
  }

  Widget _buildRecentSessionsSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _skeletonBox(height: 24, width: 120),
        const SizedBox(height: 12),
        _skeletonBox(height: 60),
        const SizedBox(height: 8),
        _skeletonBox(height: 60),
      ],
    );
  }

  Widget _buildRecentNotificationsSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _skeletonBox(height: 24, width: 120),
        const SizedBox(height: 12),
        _skeletonBox(height: 60),
        const SizedBox(height: 8),
        _skeletonBox(height: 60),
      ],
    );
  }

  Widget _skeletonBox({double height = 20, double width = double.infinity}) {
    return Container(
      width: width,
      height: height,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}
