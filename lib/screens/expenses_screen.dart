import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/company.dart';
import '../models/expense.dart';
import '../models/project.dart';
import '../models/stage.dart';
import '../repositories/project_repository.dart';
import '../services/storage_service.dart';
import '../utils/auth_debug.dart';
import '../widgets/empty_state.dart';
import 'fullscreen_image_preview_screen.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({
    super.key,
    required this.project,
    required this.company,
    this.initialShowPaid = false,
  });

  final Project project;
  final CompanyMember company;
  final bool initialShowPaid;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final Set<String> _selectedExpenseIds = <String>{};
  final Map<String, Expense> _selectedExpenses = <String, Expense>{};
  bool _showPaid = false;
  bool _selectionMode = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _showPaid = widget.initialShowPaid;
  }

  Future<void> _openAddExpense(List<Stage> stages) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ExpenseForm(
        project: widget.project,
        company: widget.company,
        stages: _availableStagesForExpense(stages),
      ),
    );
  }

  List<Stage> _availableStagesForExpense(List<Stage> stages) {
    if (widget.company.role.isWorker) {
      return stages
          .where((stage) => stage.assignedUserIds.contains(widget.company.uid))
          .toList(growable: false);
    }

    return stages;
  }

  void _openPaidExpensesScreen() {
    debugPrint('[DialogFlow] paidExpenses navigation push');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExpensesScreen(
          project: widget.project,
          company: widget.company,
          initialShowPaid: true,
        ),
      ),
    );
  }

  void _returnFromPaidExpensesScreen() {
    debugPrint('[DialogFlow] paidExpenses navigation back to expenses');
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _showPaid = false);
  }

  void _toggleSelection(Expense expense, bool selected) {
    if (expense.isPaid) {
      return;
    }

    setState(() {
      if (selected) {
        _selectedExpenseIds.add(expense.id);
        _selectedExpenses[expense.id] = expense;
      } else {
        _selectedExpenseIds.remove(expense.id);
        _selectedExpenses.remove(expense.id);
      }
    });
  }

  void _cancelSelection() {
    setState(() {
      _selectionMode = false;
      _selectedExpenseIds.clear();
      _selectedExpenses.clear();
    });
  }

  Future<void> _markSelectedPaid() async {
    if (_selectedExpenses.isEmpty) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Отметить выбранные чеки как оплаченные?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Оплачено'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _saving = true);

    try {
      await context.read<ProjectRepository>().markExpensesPaid(
            projectId: widget.project.id,
            expenses: _selectedExpenses.values,
          );

      if (!mounted) {
        return;
      }

      _cancelSelection();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Чеки отмечены оплаченными')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось отметить чеки: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  /// Может ли текущий пользователь редактировать/удалять этот чек.
  ///
  /// Оплаченный чек заморожен для ВСЕХ ролей (см. firestore.rules) — это
  /// финансовый факт, который нельзя менять задним числом. Неоплаченный чек
  /// может редактировать/удалять владелец, менеджер или сам автор-подрядчик
  /// (только свой чек). Заказчик не может никогда.
  bool _canEditOrDelete(Expense expense) {
    if (expense.isPaid) {
      return false;
    }

    if (widget.company.role.isOwner || widget.company.role.isManager) {
      return true;
    }

    if (widget.company.role.isWorker) {
      return expense.createdBy == widget.company.uid;
    }

    return false;
  }

  Future<void> _editExpense(Expense expense) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditExpenseSheet(
        projectId: widget.project.id,
        expense: expense,
      ),
    );
  }

  Future<void> _deleteExpense(Expense expense) async {
    final amountLabel =
        NumberFormat.currency(locale: 'ru_RU', symbol: '₽').format(expense.amount);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Удалить чек на сумму $amountLabel?'),
        content: const Text(
          'Фото чека и запись о расходе будут удалены без возможности '
          'восстановления.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await context.read<ProjectRepository>().deleteExpense(expense);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Чек удалён')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить чек: $error')),
      );
    }
  }

  void _openReceiptPreview(Expense expense) {
    final receiptUrl = expense.receiptUrl;
    if (receiptUrl == null || receiptUrl.isEmpty) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullscreenImagePreviewScreen(
          imageUrl: receiptUrl,
          title: 'Чек',
          details: [
            NumberFormat.currency(locale: 'ru_RU', symbol: '₽')
                .format(expense.amount),
            expense.category.label,
            'Этап: ${expense.displayStageTitle}',
            'Дата: ${DateFormat('dd.MM.yyyy').format(expense.date)}',
            if (expense.comment?.isNotEmpty == true) expense.comment!,
            if (expense.isPaid && expense.paidAt != null)
              'Оплачено: ${DateFormat('dd.MM.yyyy').format(expense.paidAt!)}',
          ],
        ),
      ),
    );
  }

  Map<String, List<Expense>> _groupByStage(List<Expense> expenses) {
    final grouped = <String, List<Expense>>{};

    for (final expense in expenses) {
      grouped.putIfAbsent(expense.displayStageTitle, () => []).add(expense);
    }

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<ProjectRepository>();

    return StreamBuilder<List<Stage>>(
      stream: repository.watchProductionStages(widget.project.id),
      builder: (context, stagesSnapshot) {
        final stages = stagesSnapshot.data ?? const <Stage>[];

        return Scaffold(
          appBar: AppBar(
            leading: _selectionMode
                ? IconButton(
                    tooltip: 'Выйти из режима выбора',
                    onPressed: _saving ? null : _cancelSelection,
                    icon: const Icon(Icons.close),
                  )
                : null,
            title: Text(
              _selectionMode
                  ? 'Выбрано: ${_selectedExpenseIds.length}'
                  : (_showPaid ? 'Оплаченные чеки' : 'Чеки и расходы'),
            ),
            actions: [
              if (_selectionMode)
                IconButton(
                  tooltip: 'Отметить оплаченными',
                  onPressed: _saving || _selectedExpenseIds.isEmpty
                      ? null
                      : _markSelectedPaid,
                  icon: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.payments_outlined),
                )
              else
                PopupMenuButton<_ExpensesMenuAction>(
                  onSelected: (action) {
                    switch (action) {
                      case _ExpensesMenuAction.togglePaid:
                        if (_showPaid) {
                          _returnFromPaidExpensesScreen();
                        } else {
                          _openPaidExpensesScreen();
                        }
                      case _ExpensesMenuAction.selectExpenses:
                        setState(() {
                          _showPaid = false;
                          _selectionMode = true;
                          _selectedExpenseIds.clear();
                          _selectedExpenses.clear();
                        });
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _ExpensesMenuAction.togglePaid,
                      child: ListTile(
                        leading: const Icon(Icons.archive_outlined),
                        title: Text(
                          _showPaid ? 'Активные чеки' : 'Оплаченные чеки',
                        ),
                      ),
                    ),
                    if (!_showPaid &&
                        (widget.company.role.isOwner ||
                            widget.company.role.isManager))
                      const PopupMenuItem(
                        value: _ExpensesMenuAction.selectExpenses,
                        child: ListTile(
                          leading: Icon(Icons.checklist),
                          title: Text('Выбрать чеки'),
                        ),
                      ),
                  ],
                ),
            ],
          ),
          body: StreamBuilder<List<Expense>>(
            stream: repository.watchExpenses(widget.project.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  title: 'Не удалось загрузить расходы',
                  subtitle: snapshot.error.toString(),
                );
              }

              final allExpenses = snapshot.data ?? const <Expense>[];
              final activeExpenses =
                  allExpenses.where((expense) => !expense.isPaid).toList();
              final paidExpenses =
                  allExpenses.where((expense) => expense.isPaid).toList();
              final visibleExpenses = _showPaid ? paidExpenses : activeExpenses;
              final grouped = _groupByStage(visibleExpenses);
              final total = allExpenses.fold<double>(
                0,
                (sum, expense) => sum + expense.amount,
              );
              final unpaidTotal = activeExpenses.fold<double>(
                0,
                (sum, expense) => sum + expense.amount,
              );
              final paidTotal = paidExpenses.fold<double>(
                0,
                (sum, expense) => sum + expense.amount,
              );

              if (allExpenses.isEmpty) {
                return const EmptyState(
                  icon: Icons.receipt_long,
                  title: 'Расходов нет',
                  subtitle: 'Добавьте чек, сумму, категорию, этап и дату.',
                );
              }

              return ListView(
                key: PageStorageKey<String>('expenses_${widget.project.id}'),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  _SummaryCard(
                    total: total,
                    unpaid: unpaidTotal,
                    paid: paidTotal,
                  ),
                  const SizedBox(height: 12),
                  if (visibleExpenses.isEmpty)
                    EmptyState(
                      icon: Icons.receipt_long,
                      title: _showPaid
                          ? 'Оплаченных чеков пока нет'
                          : 'Активных чеков нет',
                      subtitle: _showPaid
                          ? 'Оплаченные чеки появятся здесь после отметки.'
                          : 'Все чеки оплачены или ещё не добавлены.',
                    )
                  else
                    for (final entry in grouped.entries)
                      _ExpenseGroup(
                        title: entry.key,
                        expenses: entry.value,
                        selectionMode: _selectionMode,
                        selectedIds: _selectedExpenseIds,
                        onSelectionChanged: _toggleSelection,
                        onOpen: _openReceiptPreview,
                        canEditOrDelete: _canEditOrDelete,
                        onEdit: _editExpense,
                        onDelete: _deleteExpense,
                      ),
                ],
              );
            },
          ),
          floatingActionButton: _selectionMode || _showPaid || !_canAddExpense
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _openAddExpense(stages),
                  icon: const Icon(Icons.add_a_photo),
                  label: const Text('Чек'),
                ),
        );
      },
    );
  }

  bool get _canAddExpense {
    return widget.company.role.isOwner ||
        widget.company.role.isManager ||
        widget.company.role.isWorker;
  }
}

enum _ExpensesMenuAction {
  togglePaid,
  selectExpenses,
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.total,
    required this.unpaid,
    required this.paid,
  });

  final double total;
  final double unpaid;
  final double paid;

  @override
  Widget build(BuildContext context) {
    String money(double value) {
      return NumberFormat.currency(locale: 'ru_RU', symbol: '₽').format(value);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _SummaryRow(label: 'Итого расходов', value: money(total)),
            const Divider(),
            _SummaryRow(label: 'Не оплачено', value: money(unpaid)),
            const SizedBox(height: 8),
            _SummaryRow(label: 'Оплачено', value: money(paid)),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}

class _ExpenseGroup extends StatelessWidget {
  const _ExpenseGroup({
    required this.title,
    required this.expenses,
    required this.selectionMode,
    required this.selectedIds,
    required this.onSelectionChanged,
    required this.onOpen,
    required this.canEditOrDelete,
    required this.onEdit,
    required this.onDelete,
  });

  final String title;
  final List<Expense> expenses;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(Expense expense, bool selected) onSelectionChanged;
  final void Function(Expense expense) onOpen;
  final bool Function(Expense expense) canEditOrDelete;
  final void Function(Expense expense) onEdit;
  final void Function(Expense expense) onDelete;

  @override
  Widget build(BuildContext context) {
    final total =
        expenses.fold<double>(0, (sum, expense) => sum + expense.amount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
          child: Text(
            '$title — ${NumberFormat.currency(locale: 'ru_RU', symbol: '₽').format(total)}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        for (final expense in expenses)
          _ExpenseTile(
            expense: expense,
            selectionMode: selectionMode,
            selected: selectedIds.contains(expense.id),
            onSelectionChanged: (selected) =>
                onSelectionChanged(expense, selected),
            onOpen: () => onOpen(expense),
            canEditOrDelete: canEditOrDelete(expense),
            onEdit: () => onEdit(expense),
            onDelete: () => onDelete(expense),
          ),
      ],
    );
  }
}

enum _ExpenseTileMenuAction {
  edit,
  delete,
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({
    required this.expense,
    required this.selectionMode,
    required this.selected,
    required this.onSelectionChanged,
    required this.onOpen,
    required this.canEditOrDelete,
    required this.onEdit,
    required this.onDelete,
  });

  final Expense expense;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool> onSelectionChanged;
  final VoidCallback onOpen;
  final bool canEditOrDelete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: selectionMode
            ? () => onSelectionChanged(!selected)
            : (expense.receiptUrl == null ? null : onOpen),
        leading: selectionMode
            ? Checkbox(
                value: selected,
                onChanged: expense.isPaid
                    ? null
                    : (value) => onSelectionChanged(value ?? false),
              )
            : _ReceiptThumbnail(url: expense.receiptUrl),
        title: Text(expense.category.label),
        subtitle: Text(
          [
            DateFormat('dd.MM.yyyy').format(expense.date),
            if (expense.isPaid && expense.paidAt != null)
              'Оплачено: ${DateFormat('dd.MM.yyyy').format(expense.paidAt!)}',
            if (expense.comment?.isNotEmpty == true) expense.comment!,
          ].join(' · '),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              NumberFormat.currency(locale: 'ru_RU', symbol: '₽')
                  .format(expense.amount),
            ),
            if (!selectionMode && canEditOrDelete)
              PopupMenuButton<_ExpenseTileMenuAction>(
                tooltip: 'Действия',
                onSelected: (action) {
                  switch (action) {
                    case _ExpenseTileMenuAction.edit:
                      onEdit();
                    case _ExpenseTileMenuAction.delete:
                      onDelete();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _ExpenseTileMenuAction.edit,
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Редактировать'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _ExpenseTileMenuAction.delete,
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('Удалить'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptThumbnail extends StatelessWidget {
  const _ReceiptThumbnail({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final imageUrl = url;
    if (imageUrl == null || imageUrl.isEmpty) {
      return const Icon(Icons.receipt);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        placeholder: (context, _) => const SizedBox(
          width: 48,
          height: 48,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (context, _, __) => const SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }
}

class _ExpenseForm extends StatefulWidget {
  const _ExpenseForm({
    required this.project,
    required this.company,
    required this.stages,
  });

  final Project project;
  final CompanyMember company;
  final List<Stage> stages;

  @override
  State<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<_ExpenseForm> {
  final _amountController = TextEditingController();
  final _commentController = TextEditingController();
  final _picker = ImagePicker();

  ExpenseCategory _category = ExpenseCategory.materials;
  DateTime _date = DateTime.now();
  Stage? _stage;
  XFile? _receipt;
  Uint8List? _receiptPreviewBytes;
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _pickReceipt(ImageSource source) async {
    final receipt = await _picker.pickImage(source: source, imageQuality: 85);
    if (receipt == null) {
      return;
    }

    final bytes = await receipt.readAsBytes();
    if (!mounted) {
      return;
    }

    setState(() {
      _receipt = receipt;
      _receiptPreviewBytes = bytes;
    });
  }

  Future<void> _pickDate() async {
    final result = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: _date,
    );

    if (result != null && mounted) {
      setState(() => _date = result);
    }
  }

  Future<void> _save() async {
    final repository = context.read<ProjectRepository>();
    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
    final receipt = _receipt;

    if (receipt == null) {
      _showMessage('Добавьте фото чека.');
      return;
    }

    if (amount == null || amount <= 0) {
      _showMessage('Введите сумму чека.');
      return;
    }

    if (widget.company.role.isWorker) {
      final stage = _stage;
      if (stage == null ||
          !stage.assignedUserIds.contains(widget.company.uid)) {
        _showMessage('Подрядчик может добавить чек только в назначенный этап.');
        return;
      }
    }

    final user = FirebaseAuth.instance.currentUser;
    AuthDebug.logUser('ExpensesScreen._save', user);

    if (user == null) {
      _showMessage(const UserNotAuthenticatedException().message);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    try {
      final expenseId = repository.createExpenseId(widget.project.id);
      final upload = await StorageService.instance.uploadProjectImageDetailed(
        projectId: widget.project.id,
        folder: 'receipts',
        bytes: await receipt.readAsBytes(),
        contentType: receipt.mimeType ?? 'image/jpeg',
      );

      await repository.addExpense(
        widget.project.id,
        Expense(
          id: expenseId,
          projectId: widget.project.id,
          stageId: _stage?.id,
          stageTitle: _stage?.title ?? 'Иное',
          amount: amount,
          category: _category,
          date: _date,
          createdAt: DateTime.now(),
          createdBy: user.uid,
          isPaid: false,
          comment: _commentController.text.trim().isEmpty
              ? null
              : _commentController.text.trim(),
          receiptUrl: upload.downloadUrl,
          receiptStoragePath: upload.storagePath,
        ),
      );

      if (!mounted) {
        return;
      }

      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Чек добавлен')),
      );
    } catch (error) {
      _showMessage('Не удалось сохранить чек: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Новый расход',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 16),
              if (_receiptPreviewBytes != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child:
                        Image.memory(_receiptPreviewBytes!, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _pickReceipt(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Камера'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _pickReceipt(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Галерея'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Stage?>(
                initialValue: _stage,
                decoration: const InputDecoration(
                  labelText: 'Этап',
                  border: OutlineInputBorder(),
                ),
                items: [
                  if (!widget.company.role.isWorker)
                    const DropdownMenuItem<Stage?>(
                      value: null,
                      child: Text('Иное'),
                    ),
                  for (final stage in widget.stages)
                    DropdownMenuItem<Stage?>(
                      value: stage,
                      child: Text(stage.title),
                    ),
                ],
                onChanged:
                    _saving ? null : (value) => setState(() => _stage = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amountController,
                enabled: !_saving,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Сумма',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ExpenseCategory>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Категория',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final category in ExpenseCategory.values)
                    DropdownMenuItem(
                      value: category,
                      child: Text(category.label),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _category = value);
                        }
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _commentController,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Комментарий',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickDate,
                icon: const Icon(Icons.calendar_month),
                label: Text(DateFormat('dd.MM.yyyy').format(_date)),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Сохранение...' : 'Сохранить'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet редактирования суммы, категории и комментария чека.
///
/// Дата, фото чека, этап и статус оплаты здесь не редактируются: это
/// осознанное ограничение — firestore.rules разрешают менять только
/// amount/category/comment (см. changedOnly в match /expenses/{expenseId}).
/// Открыть форму можно только для неоплаченного чека — это уже проверяется
/// на уровне списка (_ExpensesScreenState._canEditOrDelete), но сам сейв
/// всё равно защищён и на уровне репозитория, и на уровне правил.
class _EditExpenseSheet extends StatefulWidget {
  const _EditExpenseSheet({
    required this.projectId,
    required this.expense,
  });

  final String projectId;
  final Expense expense;

  @override
  State<_EditExpenseSheet> createState() => _EditExpenseSheetState();
}

class _EditExpenseSheetState extends State<_EditExpenseSheet> {
  late final TextEditingController _amountController;
  late final TextEditingController _commentController;
  late ExpenseCategory _category;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.expense.amount.toStringAsFixed(2),
    );
    _commentController =
        TextEditingController(text: widget.expense.comment ?? '');
    _category = widget.expense.category;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));

    if (amount == null || amount <= 0) {
      _showMessage('Введите сумму чека.');
      return;
    }

    setState(() => _saving = true);

    try {
      await context.read<ProjectRepository>().updateExpense(
            projectId: widget.projectId,
            original: widget.expense,
            amount: amount,
            category: _category,
            comment: _commentController.text.trim().isEmpty
                ? null
                : _commentController.text.trim(),
          );

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      _showMessage('Не удалось сохранить чек: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Редактировать чек',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amountController,
                enabled: !_saving,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Сумма',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ExpenseCategory>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Категория',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final category in ExpenseCategory.values)
                    DropdownMenuItem(
                      value: category,
                      child: Text(category.label),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _category = value);
                        }
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _commentController,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Комментарий',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Сохранение...' : 'Сохранить'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
