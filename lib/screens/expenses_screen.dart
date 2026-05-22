import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/expense.dart';
import '../models/project.dart';
import '../repositories/project_repository.dart';
import '../services/storage_service.dart';
import '../widgets/empty_state.dart';

class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key, required this.project});

  final Project project;

  Future<void> _openAddExpense(BuildContext context) async {
    // BottomSheet удобен для короткой формы: пользователь остается в разделе
    // расходов и после сохранения сразу видит новый чек в списке.
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ExpenseForm(projectId: project.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<ProjectRepository>();

    return Scaffold(
      appBar: AppBar(title: const Text('Чеки и расходы')),
      body: StreamBuilder<List<Expense>>(
        stream: repository.watchExpenses(project.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final expenses = snapshot.data ?? [];
          if (expenses.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long,
              title: 'Расходов нет',
              subtitle: 'Добавьте чек, сумму, категорию и дату.',
            );
          }

          // Считаем сумму на клиенте для простого MVP.
          // Если расходов станет очень много, это можно вынести в агрегаты.
          final total = expenses.fold<double>(0, (sum, item) => sum + item.amount);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  title: const Text('Итого расходов'),
                  trailing: Text(
                    NumberFormat.currency(locale: 'ru_RU', symbol: '₽').format(total),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final expense in expenses)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: expense.receiptUrl == null
                        ? const Icon(Icons.receipt)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              expense.receiptUrl!,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                            ),
                          ),
                    title: Text(expense.category.label),
                    subtitle: Text(
                      [
                        DateFormat('dd.MM.yyyy').format(expense.date),
                        if (expense.comment?.isNotEmpty == true) expense.comment!,
                      ].join(' · '),
                    ),
                    trailing: Text(
                      NumberFormat.currency(locale: 'ru_RU', symbol: '₽')
                          .format(expense.amount),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddExpense(context),
        icon: const Icon(Icons.add_a_photo),
        label: const Text('Чек'),
      ),
    );
  }
}

class _ExpenseForm extends StatefulWidget {
  const _ExpenseForm({required this.projectId});

  final String projectId;

  @override
  State<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<_ExpenseForm> {
  final _amountController = TextEditingController();
  final _commentController = TextEditingController();
  ExpenseCategory _category = ExpenseCategory.materials;
  DateTime _date = DateTime.now();
  XFile? _receipt;
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _pickReceipt() async {
    // Открываем галерею и просим image_picker немного сжать изображение.
    // Это ускоряет загрузку и экономит место в Firebase Storage.
    final receipt = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    setState(() => _receipt = receipt);
  }

  Future<void> _pickDate() async {
    // Системный date picker снижает риск неправильного ввода даты руками.
    final result = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: _date,
    );
    if (result != null) {
      setState(() => _date = result);
    }
  }

  Future<void> _save() async {
    final repository = context.read<ProjectRepository>();

    // Пользователь может ввести сумму через точку или запятую.
    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      return;
    }

    setState(() => _saving = true);
    String? receiptUrl;
    final receipt = _receipt;
    if (receipt != null) {
      // Сначала грузим фото в Storage, затем сохраняем ссылку в Firestore.
      receiptUrl = await StorageService.instance.uploadProjectImage(
        projectId: widget.projectId,
        folder: 'receipts',
        bytes: await receipt.readAsBytes(),
      );
    }

    await repository.addExpense(
      widget.projectId,
      Expense(
        id: '',
        amount: amount,
        category: _category,
        date: _date,
        createdBy: FirebaseAuth.instance.currentUser!.uid,
        comment: _commentController.text.trim(),
        receiptUrl: receiptUrl,
      ),
    );

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Новый расход',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Сумма',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ExpenseCategory>(
              value: _category,
              decoration: const InputDecoration(
                labelText: 'Категория',
                border: OutlineInputBorder(),
              ),
              items: ExpenseCategory.values
                  .map(
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Text(category.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _category = value);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _commentController,
              decoration: const InputDecoration(
                labelText: 'Комментарий',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_month),
                    label: Text(DateFormat('dd.MM.yyyy').format(_date)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickReceipt,
                    icon: const Icon(Icons.image),
                    label: Text(_receipt == null ? 'Фото чека' : 'Выбрано'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Сохранение...' : 'Сохранить'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
