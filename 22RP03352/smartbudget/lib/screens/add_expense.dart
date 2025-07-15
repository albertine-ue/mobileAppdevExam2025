import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/analytics_service.dart';
import '../main.dart'; // For selectedMonthYear
import '../services/gamification_service.dart';
import 'package:confetti/confetti.dart';

class AddExpenseScreen extends StatefulWidget {
  final int? selectedMonth;
  final int? selectedYear;
  const AddExpenseScreen({super.key, this.selectedMonth, this.selectedYear});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _dateController = TextEditingController();
  String? _selectedCategory;
  DateTime? _selectedDate;
  final User? currentUser = FirebaseAuth.instance.currentUser;
  final ScrollController _scrollController = ScrollController();
  bool _isSaving = false;
  String? _editingExpenseId; // To track which expense is being edited
  // Remove local _selectedMonth/_selectedYear
  ConfettiController? _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 2));
    // No need to set local state, use selectedMonthYear
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _dateController.dispose();
    _scrollController.dispose();
    _confettiController?.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  Future<void> _addExpense() async {
    if (currentUser == null) return;
    final amount = int.tryParse(_amountController.text.trim()) ?? 0;
    final note = _noteController.text.trim();
    final date = _selectedDate;
    final category = _selectedCategory;

    if (amount <= 0 || note.isEmpty || date == null || category == null || category.isEmpty) return;

    setState(() => _isSaving = true);

    try {
      final expensesRef = FirebaseFirestore.instance.collection('expenses').doc(currentUser!.uid).collection('user_expenses');
      int month = date.month;
      int year = date.year;
      // If we are not editing, perform the budget check
      if (_editingExpenseId == null) {
        final budgetsRef = FirebaseFirestore.instance.collection('budgets').doc(currentUser!.uid).collection('user_budgets');
        final budgetDoc = await budgetsRef.where('category', isEqualTo: category).where('month', isEqualTo: month).where('year', isEqualTo: year).limit(1).get();
        double budgetAmount = double.infinity;
        if (budgetDoc.docs.isNotEmpty) {
          budgetAmount = (budgetDoc.docs.first['amount'] as num).toDouble();
        }

        final expenseDocs = await expensesRef.where('category', isEqualTo: category).where('month', isEqualTo: month).where('year', isEqualTo: year).get();
        double currentExpenses = expenseDocs.docs.fold(0.0, (sum, doc) => sum + (doc['amount'] as num));

        if (currentExpenses + amount > budgetAmount) {
          final proceed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Warning: Budget Exceeded'),
              content: Text('This expense will exceed your budget for "$category". Are you sure you want to continue?'),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save Anyway')),
              ],
            ),
          );

          if (proceed != true) {
            setState(() => _isSaving = false);
            return;
          }
        }
      }

      final expenseData = {
        'category': category,
        'amount': amount,
        'note': note,
        'date': date,
        'month': month,
        'year': year,
      };

      if (_editingExpenseId != null) {
        // Update existing expense
        await expensesRef.doc(_editingExpenseId).update(expenseData);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Expense in "$category" updated!')),
          );
        }
      } else {
        // Add new expense
        await expensesRef.add({
          ...expenseData,
          'created_at': FieldValue.serverTimestamp(),
        });
        // Track expense addition
        await AnalyticsService.logExpenseAdded(
          category: category,
          amount: amount.toDouble(),
          note: note,
        );
        // Check for first expense badge for this month
        final badgeKey = 'first_expense_${year}_${month.toString().padLeft(2, '0')}';
        final monthExpenses = await expensesRef.where('month', isEqualTo: month).where('year', isEqualTo: year).get();
        if (monthExpenses.docs.length == 1 && !(await GamificationService.hasBadge(badgeKey))) {
          await GamificationService.awardBadge(badgeKey);
          if (mounted) _showBadgeDialog('First Expense', 'You added your first expense for this month! Keep it up!');
        }
        if (mounted) {
          selectedMonthYear.value = DateTime(year, month); // Update the notifier
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Expense for "$category" added!')),
          );
        }
      }

      _clearForm();

      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (_scrollController.hasClients) {
          _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
        }
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save expense: ${e.message}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
  
  void _startEditing(DocumentSnapshot expense) {
    setState(() {
      _editingExpenseId = expense.id;
      _amountController.text = expense['amount'].toString();
      _noteController.text = expense['note'];
      _selectedCategory = expense['category'];
      final date = (expense['date'] as Timestamp).toDate();
      _selectedDate = date;
      _dateController.text = DateFormat('dd/MM/yyyy').format(date);
    });
  }

  void _clearForm() {
    _editingExpenseId = null;
    _amountController.clear();
    _noteController.clear();
    _dateController.clear();
    setState(() {
      _selectedCategory = null;
      _selectedDate = null;
    });
  }

  Stream<List<String>> _getCategories() {
    if (currentUser == null) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection('budgets')
        .doc(currentUser!.uid)
        .collection('user_budgets')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => (doc.data()['category'] ?? '').toString()).where((cat) => cat.isNotEmpty).toList());
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime>(
      valueListenable: selectedMonthYear,
      builder: (context, selectedDate, _) {
        final _selectedMonth = selectedDate.month;
        final _selectedYear = selectedDate.year;
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: Colors.green[800],
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text(
              'ADD EXPENSE',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
            elevation: 0,
          ),
          body: Padding(
            padding: const EdgeInsets.all(10.0), // Reduced from 12.0
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Month/Year Pickers
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _selectedMonth,
                          items: List.generate(12, (index) => DropdownMenuItem(
                            value: index + 1,
                            child: Text(DateFormat.MMMM().format(DateTime(0, index + 1))),
                          )),
                          onChanged: (val) => setState(() => selectedMonthYear.value = DateTime(_selectedYear, val!)), // Update notifier
                          decoration: const InputDecoration(labelText: 'Month'),
                        ),
                      ),
                      const SizedBox(width: 8), // Reduced from 12
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _selectedYear,
                          items: List.generate(5, (index) {
                            int year = DateTime.now().year - 2 + index;
                            return DropdownMenuItem(value: year, child: Text('$year'));
                          }),
                          onChanged: (val) => setState(() => selectedMonthYear.value = DateTime(val!, _selectedMonth)), // Update notifier
                          decoration: const InputDecoration(labelText: 'Year'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8), // Reduced from 12
                  // Expense Table
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _ExpenseTable(
                      currentUser: currentUser,
                      onEdit: _startEditing,
                      month: _selectedMonth,
                      year: _selectedYear,
                    ),
                  ),
                  const SizedBox(height: 12), // Reduced from 16
                  if (_editingExpenseId != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6.0), // Reduced from 8.0
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Editing Expense',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Theme.of(context).colorScheme.primary),
                          ),
                          TextButton(
                            onPressed: _clearForm,
                            child: Text('Cancel Edit', style: TextStyle(fontSize: 13)), // Added fontSize
                          )
                        ],
                      ),
                    ),
                  const Text(
                    'Add new expense',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16), // Reduced from 18
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6), // Reduced from 8
                  // Amount
                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)), // Reduced from 20
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), // Reduced from 16
                    ),
                  ),
                  const SizedBox(height: 6), // Reduced from 8
                  // Category
                  StreamBuilder<List<String>>(
                    stream: _getCategories(),
                    builder: (context, snapshot) {
                      final categories = snapshot.data?.toSet().toList() ?? [];
                      if (!categories.contains(_selectedCategory)) {
                        _selectedCategory = null;
                      }
                      return DropdownButtonFormField<String>(
                        value: _selectedCategory,
                        items: categories
                            .map((cat) => DropdownMenuItem(
                                  value: cat,
                                  child: Text(cat),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedCategory = val);
                        },
                        decoration: InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)), // Reduced from 20
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), // Reduced from 16
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 6), // Reduced from 8
                  // Note
                  TextField(
                    controller: _noteController,
                    decoration: InputDecoration(
                      labelText: 'Note',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)), // Reduced from 20
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), // Reduced from 16
                    ),
                  ),
                  const SizedBox(height: 6), // Reduced from 8
                  // Date
                  TextField(
                    controller: _dateController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Date',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)), // Reduced from 20
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), // Reduced from 16
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.calendar_today, size: 20), // Added size
                        onPressed: _pickDate,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12), // Reduced from 16
                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[800],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16), // Reduced from 20
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10), // Reduced from 14
                      ),
                      onPressed: _isSaving ? null : _addExpense,
                      child: _isSaving
                          ? const SizedBox(
                              height: 18, // Reduced from 20
                              width: 18, // Reduced from 20
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2), // Reduced from 3
                            )
                          : Text(_editingExpenseId != null ? 'Update' : 'Save', style: const TextStyle(fontSize: 16)), // Reduced from 18
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showBadgeDialog(String title, String message) {
    _confettiController?.play();
    showDialog(
      context: context,
      builder: (context) => Stack(
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController!,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              colors: const [Colors.green, Colors.amber, Colors.blue, Colors.purple],
              numberOfParticles: 30,
              maxBlastForce: 20,
              minBlastForce: 8,
            ),
          ),
          AlertDialog(
            title: Row(
              children: [
                Icon(Icons.emoji_events, color: Colors.amber),
                SizedBox(width: 8),
                Text('Badge Unlocked!'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                SizedBox(height: 8),
                Text(message),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Awesome!'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExpenseTable extends StatefulWidget {
  final User? currentUser;
  final Function(DocumentSnapshot) onEdit;
  final int month;
  final int year;

  const _ExpenseTable({required this.currentUser, required this.onEdit, required this.month, required this.year});

  @override
  State<_ExpenseTable> createState() => _ExpenseTableState();
}

class _ExpenseTableState extends State<_ExpenseTable> {
  Future<void> _deleteExpense(String docId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Expense'),
        content: const Text('Are you sure you want to delete this expense? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('expenses')
            .doc(widget.currentUser!.uid)
            .collection('user_expenses')
            .doc(docId)
            .delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Expense deleted successfully')),
          );
        }
      } on FirebaseException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete expense: ${e.message}')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.currentUser == null) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('Not logged in.'),
      );
    }
    final expensesRef = FirebaseFirestore.instance
        .collection('expenses')
        .doc(widget.currentUser!.uid)
        .collection('user_expenses');
    return StreamBuilder<QuerySnapshot>(
      stream: expensesRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('No expenses yet.'),
          );
        }
        // Filter docs by month/year, fallback to date if fields missing
        final docs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (data.containsKey('month') && data.containsKey('year')) {
            return data['month'] == widget.month && data['year'] == widget.year;
          } else if (data['date'] != null) {
            final date = (data['date'] as Timestamp).toDate();
            return date.month == widget.month && date.year == widget.year;
          }
          return false;
        }).toList();
        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('No expenses yet.'),
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Id')),
              DataColumn(label: Text('Category')),
              DataColumn(label: Text('Amount')),
              DataColumn(label: Text('Note')),
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Actions')),
            ],
            rows: docs.asMap().entries.map((entry) {
              final index = entry.key;
              final doc = entry.value;
              final data = doc.data() as Map<String, dynamic>;
              final date = data['date'] is Timestamp ? (data['date'] as Timestamp).toDate() : null;
              return DataRow(cells: [
                DataCell(Text((index + 1).toString())),
                DataCell(Text(data['category'] ?? '')),
                DataCell(Text(data['amount']?.toString() ?? '')),
                DataCell(Text(data['note'] ?? '')),
                DataCell(Text(date != null ? DateFormat('dd/MM/yyyy').format(date) : '')),
                DataCell(
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => widget.onEdit(doc),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteExpense(doc.id),
                      ),
                    ],
                  ),
                ),
              ]);
            }).toList(),
          ),
        );
      },
    );
  }
} 